# Balance the provincial WSG split across M4 + M1 + cypher.
#
# Reads per-WSG wall times from a prior provincial run's host logs and
# applies greedy LPT (Longest Processing Time first) bin-packing to
# produce three host buckets that should finish in roughly equal wall
# clock time.
#
# Yesterday's sequential 1/3 split idled the fast hosts ~30-45 min while
# cypher caught up. This script projects ~10-15 min savings per run.
#
# Usage:
#   Rscript data-raw/balance_provincial_buckets.R
#
# Hardcoded inputs (override above when re-running with new baseline):
#   - Yesterday's host log paths (one per host)
#   - Today's M4-relative speed factors from a current ADMS smoke
#
# Output: M4 / M1 / CY bucket strings ready to feed into trifecta_*.sh.

suppressPackageStartupMessages({})

# ---- Inputs ---------------------------------------------------------------

logs_dir <- "/Users/airvine/Projects/repo/link/data-raw/logs"

# Prefer per-WSG CSVs (emitted by run_provincial_parity.R after this script
# was added). Fall back to text-log regex parsing for older runs.
csvs <- list.files(file.path(logs_dir, "provincial_parity"),
                   pattern = "_per_wsg_times\\.csv$", full.names = TRUE)
csvs <- c(csvs, list.files(file.path(logs_dir, "provincial_default"),
                           pattern = "_per_wsg_times\\.csv$", full.names = TRUE))
if (length(csvs) == 0) {
  m4_log <- file.path(logs_dir, "202605031423_trifecta_provincial_m4.txt")
  m1_log <- file.path(logs_dir, "202605031423_trifecta_provincial_m1.txt")
  cy_log <- "/Users/airvine/Projects/repo/rtj/scripts/cypher/logs/202605031423_cypher-run_202605031423_trifecta_provincial_cypher.txt"
}

# Host speed factors (M4 = reference). Use yesterday's per-host MEAN
# wall time across 77 WSGs as the predictor — it averages out per-WSG
# variance and warmup costs. A single-WSG smoke today is too noisy
# (cold-start dominates the sample). Cross-check today's smoke against
# this for sanity, but don't drive the LPT off the smoke.
#
# Yesterday's per-host means (s/WSG):
#   M4 81.9, M1 73.5, cypher 107.7
# Factors vs M4:
host_factor <- c(m4 = 1.00, m1 = 73.5 / 81.9, cy = 107.7 / 81.9)

# ---- Parse logs (POSIX-compatible regex, no \s) ---------------------------

parse_log <- function(path, host) {
  txt <- readLines(path, warn = FALSE)
  out <- list()
  cur_wsg <- NULL
  start_re <- "^[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+([A-Z]{3,5})[[:space:]]+\\.\\.\\."
  done_re  <- "^done ([0-9.]+)s,"
  for (line in txt) {
    m <- regmatches(line, regexec(start_re, line))[[1]]
    if (length(m) == 2) {
      cur_wsg <- m[2]
      next
    }
    m2 <- regmatches(line, regexec(done_re, line))[[1]]
    if (length(m2) == 2 && !is.null(cur_wsg)) {
      out[[length(out) + 1]] <- list(
        wsg = cur_wsg, time_s = as.numeric(m2[2]), host = host)
      cur_wsg <- NULL
    }
  }
  do.call(rbind, lapply(out, as.data.frame))
}

if (length(csvs) > 0) {
  cat("Loading per-WSG times from CSVs:\n  ",
      paste(basename(csvs), collapse = "\n  "), "\n", sep = "")
  rows <- do.call(rbind, lapply(csvs, function(p) {
    df <- read.csv(p, stringsAsFactors = FALSE)
    if (nrow(df) == 0) return(NULL)
    # Map nodename → host short code
    df$host <- ifelse(grepl("MacBook-Pro-2", df$host),       "m4",
              ifelse(grepl("Allans|MacBook-Pro$", df$host),  "m1",
              ifelse(grepl("cypher", df$host),               "cy",
                     df$host)))
    df[df$status == "ok", c("wsg", "elapsed_s", "host")]
  }))
  rows$time_s <- rows$elapsed_s
  # Dedup (wsg, host) by median across runs. Multiple CSVs in the live
  # dir produce one row per (run, wsg) — without this step the same WSG
  # appears N times in the LPT input and gets assigned to N buckets.
  all_w <- aggregate(time_s ~ wsg + host, data = rows, FUN = median)
  m4 <- all_w[all_w$host == "m4", ]
  m1 <- all_w[all_w$host == "m1", ]
  cy <- all_w[all_w$host == "cy", ]
} else {
  m4 <- parse_log(m4_log, "m4")
  m1 <- parse_log(m1_log, "m1")
  cy <- parse_log(cy_log, "cy")
  all_w <- rbind(m4, m1, cy)
}
cat(sprintf("WSGs loaded: m4=%d m1=%d cy=%d total=%d\n",
            nrow(m4), nrow(m1), nrow(cy), nrow(all_w)))

# ---- Speed-factor normalization ------------------------------------------

# Yesterday's per-WSG mean time on each host gives a rough host-speed
# estimate. Divide each WSG's recorded time by its host's yesterday
# factor to convert to "M4-equivalent" intrinsic work.
yest_factor <- c(
  m4 = 1.0,
  m1 = mean(m1$time_s) / mean(m4$time_s),
  cy = mean(cy$time_s) / mean(m4$time_s))
cat("Yesterday host factors (per-WSG mean): ",
    paste0(names(yest_factor), "=", round(yest_factor, 2), collapse = ", "),
    "\n", sep = "")
cat("Today host factors    (ADMS smoke):    ",
    paste0(names(host_factor), "=", round(host_factor, 2), collapse = ", "),
    "\n", sep = "")
all_w$m4_equiv <- all_w$time_s / yest_factor[all_w$host]

# ---- Reconcile against canonical WSG list --------------------------------
# Any WSG that errored last run (e.g. CHUK no-species) won't have a time.
# Fetch the canonical 232-WSG list from wsg_species_presence and assign
# any unseen WSGs the median time so they enter the LPT plan.
suppressPackageStartupMessages({library(link)})
cfg <- lnk_config("bcfishpass")  # canonical bundle for provincial dispatch
loaded <- lnk_load_overrides(cfg)
# Filter to bundle species only — broader inclusion (e.g. ct/dv/gr/rb) lets
# WSGs through that the bundle can't classify (link#157).
spp_cols <- tolower(cfg$species)
wsg_pres <- loaded$wsg_species_presence
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1,
                 function(r) any(r %in% c("t","TRUE",TRUE)))
canonical <- sort(wsg_pres$watershed_group_code[has_spp])
missing <- setdiff(canonical, all_w$wsg)
if (length(missing) > 0) {
  cat("\nMissing from logs (assigning median time):\n  ",
      paste(missing, collapse = ", "), "\n", sep = "")
  med <- median(all_w$time_s, na.rm = TRUE)
  add <- data.frame(wsg = missing, time_s = med, host = "m4",
                    m4_equiv = med, stringsAsFactors = FALSE)
  all_w <- rbind(all_w, add)
}

# ---- Greedy LPT bin-packing ----------------------------------------------

# Dedup across hosts: a WSG that ran on both m4 AND m1 (rare but possible
# across multi-run histories) would otherwise appear twice and be assigned
# to two buckets. Median collapses to one m4_equiv per WSG.
all_w <- aggregate(m4_equiv ~ wsg, data = all_w, FUN = median)
all_w <- all_w[order(-all_w$m4_equiv), ]
load <- c(m4 = 0, m1 = 0, cy = 0)
buckets <- list(m4 = character(), m1 = character(), cy = character())
for (i in seq_len(nrow(all_w))) {
  candidate_finish <- load + all_w$m4_equiv[i] * host_factor
  pick <- names(which.min(candidate_finish))
  buckets[[pick]] <- c(buckets[[pick]], all_w$wsg[i])
  load[pick] <- candidate_finish[pick]
}

# ---- Report --------------------------------------------------------------

cat("\n=== Balanced plan ===\n")
for (h in c("m4", "m1", "cy")) {
  cat(sprintf("%s: %3d WSGs  projected %5.1f min\n",
              h, length(buckets[[h]]), load[h] / 60))
}
cat(sprintf("Predicted wall (slowest host): %.1f min\n", max(load) / 60))
cat("Yesterday wall: 138.2 min (cypher bottleneck, sequential thirds)\n")
cat(sprintf("Estimated savings: %.0f min\n", 138.2 - max(load) / 60))

cat("\n# Paste into trifecta override or run host-by-host:\n\n")
for (h in c("m4", "m1", "cy")) {
  cat(sprintf("%s_BUCKET=\"%s\"\n", toupper(h),
              paste(sort(buckets[[h]]), collapse = ",")))
}
