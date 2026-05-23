suppressPackageStartupMessages({})

# Canonical WSG list (bundle species presence-filtered, link#157)
cfg <- link::lnk_config("bcfishpass")
loaded <- link::lnk_load_overrides(cfg)
wsg_pres <- loaded$wsg_species_presence
spp_cols <- tolower(cfg$species)
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1,
                 function(r) any(r %in% c("t","TRUE",TRUE)))
all_wsgs <- sort(wsg_pres$watershed_group_code[has_spp])

# Parse --host-speeds=m4=1.0,m1=0.83,cy=1.83 into a named numeric vector
parse_speeds <- function(s) {
  pairs <- strsplit(s, ",", fixed = TRUE)[[1]]
  vec <- numeric(0)
  for (p in pairs) {
    kv <- strsplit(p, "=", fixed = TRUE)[[1]]
    if (length(kv) != 2L) stop("bad --host-speeds entry: ", p)
    vec[trimws(kv[1])] <- as.numeric(kv[2])
  }
  vec
}
speeds <- parse_speeds("m4=1.0,m1=0.83,cy=1.83")
if (!all(c("m4","m1","cy") %in% names(speeds))) {
  stop("--host-speeds must include m4, m1, cy (got: ",
       paste(names(speeds), collapse = ","), ")")
}

# Hosts in the plan: m4, m1, cy1..cyN_CY (each cypher workspace is its
# own host). Per-cypher speed: take `cyN` from --host-speeds if present,
# else fall back to the generic `cy` factor.
cy_ws_csv <- "job1,job2,job3"
cy_ws <- strsplit(cy_ws_csv, ",", fixed = TRUE)[[1]]
n_cy <- length(cy_ws)
cy_host_keys <- if (n_cy == 1L) "cy" else paste0("cy", seq_len(n_cy))
host_keys <- c("m4", "m1", cy_host_keys)
host_factor <- numeric(length(host_keys))
names(host_factor) <- host_keys
host_factor["m4"] <- speeds["m4"]
host_factor["m1"] <- speeds["m1"]
for (i in seq_along(cy_host_keys)) {
  k <- cy_host_keys[i]
  host_factor[k] <- if (!is.na(speeds[k])) speeds[k] else speeds["cy"]
}

# Per-WSG timing CSVs from prior runs (any host, any run). Drop rows with
# status != "ok" so error-stub rows don't pollute the time estimates.
logs_root <- "/Users/airvine/Projects/repo/link/data-raw/logs"
csv_dirs <- file.path(logs_root,
                      c("provincial_parity",
                        paste0("provincial_", "bcfishpass")))
csv_dirs <- unique(csv_dirs[dir.exists(csv_dirs)])
csvs <- unlist(lapply(csv_dirs, function(d)
  list.files(d, pattern = "_per_wsg_times\\.csv$", full.names = TRUE)))

times <- if (length(csvs) > 0L) {
  rows <- do.call(rbind, lapply(csvs, function(p) {
    df <- tryCatch(read.csv(p, stringsAsFactors = FALSE),
                   error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0L) return(NULL)
    # Map nodename -> short code. Fallback: drop unknown hosts.
    df$host_short <- ifelse(grepl("MacBook-Pro-2", df$host),       "m4",
                      ifelse(grepl("Allans|MacBook-Pro$", df$host), "m1",
                      ifelse(grepl("cypher", df$host),               "cy",
                             NA_character_)))
    ok <- df[df$status == "ok" & !is.na(df$host_short), ]
    ok[, c("wsg", "elapsed_s", "host_short")]
  }))
  rows
} else {
  NULL
}

# Compute per-WSG M4-equivalent intrinsic work. Back-normalize each
# sample's elapsed by the CLI host_factor (the same factor the LPT
# projection uses). This is consistent and avoids a feedback loop:
# using OBSERVED per-host mean as the divisor inflates the factor when
# prior buckets were imbalanced (large WSGs on cy + small on m4 →
# observed mean ratio reflects bucket bias × true slowness, not
# slowness alone), and subsequent runs amplify the imbalance.
#
# Note: this trusts --host-speeds as ground truth. Update the defaults
# (or the CLI value) when host speeds drift — re-measure with an ADMS
# smoke on each host.
buckets <- vector("list", length(host_keys))
names(buckets) <- host_keys
load <- numeric(length(host_keys))
names(load) <- host_keys

if (!is.null(times) && nrow(times) > 0L) {
  # Tag any rows whose host_short isn't a recognized key with NA and
  # warn — silent drops let new/renamed hosts vanish from the LPT input.
  unknown_hosts <- setdiff(unique(times$host_short), c("m4", "m1", "cy"))
  if (length(unknown_hosts) > 0L) {
    cat("[LPT] WARN: dropped ", sum(times$host_short %in% unknown_hosts),
        " timing rows with unrecognized host_short: ",
        paste(unknown_hosts, collapse = ", "), "\n", sep = "")
    times <- times[!(times$host_short %in% unknown_hosts), ]
  }
  # Back-normalize: elapsed / host_factor[host_short]. Cypher rows use
  # the generic "cy" factor (per-cypher overrides like cy1/cy2 apply
  # only to the LPT projection step, not to back-normalization — the
  # CSV's host_short is always "cy", never "cy1").
  norm_factor <- speeds[c("m4", "m1", "cy")]
  times$m4_equiv <- times$elapsed_s / norm_factor[times$host_short]
  per_wsg <- aggregate(m4_equiv ~ wsg, data = times, FUN = median)
  cat("[LPT] timing CSVs found: ", length(csvs),
      "  WSGs with samples: ", nrow(per_wsg), "\n", sep = "")
  cat("[LPT] back-normalize host_factor (--host-speeds): ",
      paste0(names(norm_factor), "=", round(norm_factor, 2),
             collapse = ", "), "\n", sep = "")

  # Reconcile against canonical: missing WSGs get the median m4_equiv.
  missing_wsgs <- setdiff(all_wsgs, per_wsg$wsg)
  if (length(missing_wsgs) > 0L) {
    med <- median(per_wsg$m4_equiv, na.rm = TRUE)
    per_wsg <- rbind(per_wsg,
      data.frame(wsg = missing_wsgs, m4_equiv = med))
    cat("[LPT] WSGs missing from timing CSVs (assigned median ",
        round(med, 1), "s): ", length(missing_wsgs), "\n", sep = "")
  }
  per_wsg <- per_wsg[per_wsg$wsg %in% all_wsgs, , drop = FALSE]
  per_wsg <- per_wsg[order(-per_wsg$m4_equiv), ]

  # Greedy LPT assignment
  for (i in seq_len(nrow(per_wsg))) {
    candidate <- load + per_wsg$m4_equiv[i] * host_factor
    pick <- names(which.min(candidate))
    buckets[[pick]] <- c(buckets[[pick]], per_wsg$wsg[i])
    load[pick] <- candidate[pick]
  }
  cat("[LPT] projected finish (min): ",
      paste0(names(load), "=", round(load/60, 1),
             collapse = ", "), "\n", sep = "")
} else {
  # Fallback: deterministic ceil(n/H) split. Guards small-n edge case
  # where m4_n + m1_n could exceed n (round-1 code-check finding).
  cat("[LPT] no timing CSVs found; using deterministic split\n")
  n <- length(all_wsgs)
  n_hosts <- length(host_keys)
  chunk <- ceiling(n / n_hosts)
  for (i in seq_along(host_keys)) {
    lo <- (i - 1) * chunk + 1
    hi <- min(i * chunk, n)
    buckets[[host_keys[i]]] <- if (lo > n) character(0) else all_wsgs[lo:hi]
  }
}

# Emit shell-parseable assignments
for (h in host_keys) {
  cat(toupper(h), "=", paste(buckets[[h]], collapse = ","), "\n", sep = "")
}
