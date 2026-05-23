suppressPackageStartupMessages({})

# Canonical WSG list (bundle species presence-filtered, link#157)
cfg <- link::lnk_config("default")
loaded <- link::lnk_load_overrides(cfg)
wsg_pres <- loaded$wsg_species_presence
spp_cols <- tolower(cfg$species)
has_spp <- apply(wsg_pres[, spp_cols, drop = FALSE], 1,
                 function(r) any(r %in% c("t","TRUE",TRUE)))
all_wsgs <- sort(wsg_pres$watershed_group_code[has_spp])

# --wsgs=A,B,C subset filter. Intersect with the species-presence-filtered
# bundle WSGs; error if any provided WSG isn't in the bundle (catches typos
# pre-dispatch instead of partial-host-error mid-run).
wsgs_filter_str <- "CARP,CRKD,FINA,FINL,FIRE,FOXR,INGR,LOMI,MESI,NATR,OSPK,PARA,PARS,PCEA,TOOD,UOMI"
if (nzchar(wsgs_filter_str)) {
  filter <- trimws(strsplit(wsgs_filter_str, ",", fixed = TRUE)[[1]])
  unknown <- setdiff(filter, all_wsgs)
  if (length(unknown) > 0) {
    stop("--wsgs contains WSGs not in bundle species-presence set (or with no species we model): ",
         paste(unknown, collapse = ", "), call. = FALSE)
  }
  all_wsgs <- sort(intersect(all_wsgs, filter))
  cat("[LPT] --wsgs filter active: ", length(all_wsgs), " WSGs\n", sep = "")
}

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
speeds <- parse_speeds("m4=1.0,m1=0.79,cy=1.23")
if (!all(c("m4","m1","cy") %in% names(speeds))) {
  stop("--host-speeds must include m4, m1, cy (got: ",
       paste(names(speeds), collapse = ","), ")")
}

# Hosts in the plan: m4, m1, cy1..cyN_CY (each cypher workspace is its
# own host). Per-cypher speed: take `cyN` from --host-speeds if present,
# else fall back to the generic `cy` factor.
cy_ws_csv <- ""
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
                        paste0("provincial_", "default")))
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
  # Fallback: host_speeds-weighted alphabetical split. Each host gets
  # floor((n * speed_factor) / sum(speed_factors)) WSGs; remainder
  # distributed to highest-factor hosts first. Without this weighting,
  # equal-split sends 217/5 = 44 WSGs to every host — cyphers finish in
  # 60% of M4's wall and M4 in 83% of M1's wall, wasting cypher capacity
  # AND making M1 the long pole. (Bug discovered 2026-05-13 mid-dispatch;
  # host_factor from --host-speeds is required for fair fallback.)
  cat("[LPT] no timing CSVs found; using host_speeds-weighted split\n")
  n <- length(all_wsgs)
  weights <- host_factor[host_keys]
  share <- weights / sum(weights)
  sizes <- floor(n * share)
  remainder <- n - sum(sizes)
  if (remainder > 0) {
    ord <- order(-weights)
    for (i in seq_len(remainder)) sizes[ord[i]] <- sizes[ord[i]] + 1
  }
  cat("[LPT] weighted sizes: ",
      paste0(names(sizes), "=", sizes, collapse = ", "), "\n", sep = "")
  lo <- 1L
  for (i in seq_along(host_keys)) {
    if (sizes[i] == 0) {
      buckets[[host_keys[i]]] <- character(0)
      next
    }
    hi <- lo + sizes[i] - 1L
    buckets[[host_keys[i]]] <- all_wsgs[lo:hi]
    lo <- hi + 1L
  }
}

# Emit shell-parseable assignments
for (h in host_keys) {
  cat(toupper(h), "=", paste(buckets[[h]], collapse = ","), "\n", sep = "")
}
