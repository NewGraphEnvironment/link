# Compare two provincial rollup directories of per-WSG RDS files.
#
# Each RDS holds a tibble with columns
#   wsg, species, habitat_type, unit, link_value, bcfishpass_value, diff_pct
# (the output of compare_bcfishpass_wsg). This script reads two directories
# (e.g. logs/provincial_default/ vs logs/provincial_default_extrabreaks/),
# joins on wsg+species+habitat_type+unit, and emits per-species delta
# summaries.
#
# Useful when the persistent schemas can't be co-queried (e.g. one host
# ran out of disk before consolidation) — the per-WSG RDS files survive
# host failures and let us compute the methodology delta from rollup
# tibbles alone.
#
# Usage:
#   Rscript data-raw/compare_rollups.R \
#     <baseline_dir> <experiment_dir> [species_csv]
#
# Example:
#   Rscript data-raw/compare_rollups.R \
#     data-raw/logs/provincial_default \
#     data-raw/logs/provincial_default_extrabreaks

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript compare_rollups.R <baseline_dir> <experiment_dir> [species_csv]")
}
DIR_A <- args[1]
DIR_B <- args[2]
SP_FILTER <- if (length(args) >= 3) toupper(strsplit(args[3], ",")[[1]]) else NULL

read_dir <- function(d) {
  fs <- list.files(d, pattern = "\\.rds$", full.names = TRUE)
  rows <- list()
  for (f in fs) {
    obj <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(obj)) next
    if (is.list(obj) && !is.null(obj$error)) next  # error stub
    if (!is.data.frame(obj)) next
    rows[[length(rows) + 1]] <- obj
  }
  do.call(rbind, rows)
}

a <- read_dir(DIR_A)
b <- read_dir(DIR_B)
cat(sprintf("Baseline rows:   %d  (%d WSGs, %s)\n",
            nrow(a), length(unique(a$wsg)), DIR_A))
cat(sprintf("Experiment rows: %d  (%d WSGs, %s)\n",
            nrow(b), length(unique(b$wsg)), DIR_B))

# Restrict to km comparisons + spawn/rear (the methodology-delta primitives).
keep <- c("spawning", "rearing", "rearing_stream",
          "rearing_lake_centerline", "rearing_wetland_centerline")
a <- a[a$unit == "km" & a$habitat_type %in% keep, ]
b <- b[b$unit == "km" & b$habitat_type %in% keep, ]
if (!is.null(SP_FILTER)) {
  a <- a[a$species %in% SP_FILTER, ]
  b <- b[b$species %in% SP_FILTER, ]
}

# Join on (wsg, species, habitat_type, unit).
m <- merge(a, b,
           by = c("wsg", "species", "habitat_type", "unit"),
           suffixes = c("_a", "_b"),
           all = TRUE)
m$d_km  <- round(m$link_value_b - m$link_value_a, 2)
m$d_pct <- ifelse(m$link_value_a > 0,
                  round(100 * m$d_km / m$link_value_a, 2), NA)

# --- Province-wide totals per (species, habitat_type) -----------
cat("\n=== Province-wide deltas (km) ===\n")
totals <- aggregate(cbind(link_value_a, link_value_b, d_km) ~ species + habitat_type,
                    data = m, FUN = sum, na.rm = TRUE)
totals <- totals[order(totals$species, totals$habitat_type), ]
totals$d_pct <- ifelse(totals$link_value_a > 0,
                       round(100 * totals$d_km / totals$link_value_a, 2), NA)
totals$link_value_a <- round(totals$link_value_a, 1)
totals$link_value_b <- round(totals$link_value_b, 1)
totals$d_km <- round(totals$d_km, 1)
print(totals, row.names = FALSE)

# --- Top WSGs per species by absolute spawn-km shift ------------
cat("\n=== Top 10 spawn-km shifts per species ===\n")
sp_unique <- sort(unique(m$species))
for (sp in sp_unique) {
  sub <- m[m$species == sp & m$habitat_type == "spawning", ]
  sub <- sub[order(-abs(sub$d_km)), ]
  if (nrow(sub) == 0) next
  cat(sprintf("\n--- %s ---\n", sp))
  print(head(sub[, c("wsg", "link_value_a", "link_value_b", "d_km", "d_pct")], 10),
        row.names = FALSE)
}

# --- Save snapshot ---------------------------------------------
out_dir <- file.path("data-raw", "logs", "methodology_delta")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
ts <- format(Sys.time(), "%Y%m%d_%H%M")
fname <- sprintf("%s_rollup_%s_vs_%s.rds",
                 ts, basename(DIR_B), basename(DIR_A))
saveRDS(list(per_wsg = m, totals = totals,
             dir_a = DIR_A, dir_b = DIR_B),
        file.path(out_dir, fname))
cat(sprintf("\nSaved: %s\n", file.path(out_dir, fname)))
