# Schema-delta query: compare per-species spawning / rearing km between
# two persistent fresh schemas. The "methodology delta" interpretation
# (e.g. default vs default_extrabreaks) is a use-case framing — what
# the script actually does is query side-by-side state from any two
# `<schema>.streams` + `<schema>.streams_habitat_<sp>` pairs.
#
# Schemas are populated by lnk_pipeline_persist via a provincial trifecta
# run (see wsgs_dispatch.sh). This script reads streams +
# streams_habitat_<sp> from each schema and emits:
#   1. Province-wide totals per species (spawn / rear / accessible km)
#   2. Per-species delta summary (km, percent, # WSGs shifted)
#   3. Top WSGs by absolute delta per species
#   4. Optional: writes the rollups to data-raw/logs/methodology_delta/
#
# Usage:
#   Rscript data-raw/query_schema_delta.R \
#     <baseline_schema> <experiment_schema> [species_csv]
#
# Example (today's run):
#   Rscript data-raw/query_schema_delta.R fresh_default fresh_default_extrabreaks
#
# Yesterday's SK-only equivalent (kept as reference shape):
#   Rscript data-raw/query_schema_delta.R fresh fresh_default sk

suppressPackageStartupMessages({
  library(DBI); library(RPostgres); library(dplyr); library(tidyr)
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Usage: Rscript query_schema_delta.R <baseline_schema> <experiment_schema> [species_csv]")
}
SCHEMA_A <- args[1]   # baseline (e.g. fresh_default)
SCHEMA_B <- args[2]   # experiment (e.g. fresh_default_extrabreaks)
SP_FILTER <- if (length(args) >= 3) {
  toupper(strsplit(args[3], ",")[[1]])
} else {
  NULL
}

conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
on.exit(try(DBI::dbDisconnect(conn), silent = TRUE), add = TRUE)

# Discover species (intersect of streams_habitat_<sp> tables that exist
# in both schemas, optionally filtered to user-supplied species list).
discover_species <- function(schema) {
  tbls <- DBI::dbGetQuery(conn, sprintf(
    "SELECT tablename FROM pg_tables
     WHERE schemaname = %s
       AND tablename LIKE 'streams_habitat\\_%%' ESCAPE '\\'",
    DBI::dbQuoteLiteral(conn, schema)))$tablename
  toupper(sub("^streams_habitat_", "", tbls))
}
species <- intersect(discover_species(SCHEMA_A), discover_species(SCHEMA_B))
if (!is.null(SP_FILTER)) species <- intersect(species, SP_FILTER)
if (length(species) == 0L) {
  stop("No overlapping species between ", SCHEMA_A, " and ", SCHEMA_B)
}
cat(sprintf("Comparing %s vs %s on species: %s\n",
            SCHEMA_A, SCHEMA_B, paste(species, collapse = ", ")))

# Province-wide per-species per-schema totals.
totals_for <- function(schema, sp) {
  DBI::dbGetQuery(conn, sprintf("
    SELECT %s AS schema_name, %s AS species,
      ROUND(SUM(CASE WHEN h.accessible    THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS access_km,
      ROUND(SUM(CASE WHEN h.spawning      THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS spawn_km,
      ROUND(SUM(CASE WHEN h.rearing       THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS rear_km,
      ROUND(SUM(CASE WHEN h.lake_rearing  THEN s.length_metre ELSE 0 END)::numeric / 1000, 1) AS lake_rear_km
    FROM %s.streams s
    JOIN %s.streams_habitat_%s h
      ON h.id_segment = s.id_segment
     AND h.watershed_group_code = s.watershed_group_code",
    DBI::dbQuoteLiteral(conn, schema),
    DBI::dbQuoteLiteral(conn, sp),
    schema, schema, tolower(sp)))
}
totals <- do.call(rbind, c(
  lapply(species, function(sp) totals_for(SCHEMA_A, sp)),
  lapply(species, function(sp) totals_for(SCHEMA_B, sp))))

# Wide form: one row per species, columns per (metric × schema).
totals_w <- pivot_wider(totals, names_from = schema_name,
                        values_from = c(access_km, spawn_km, rear_km, lake_rear_km))
# Compute deltas (B - A) and pct.
delta_cols <- c("access_km", "spawn_km", "rear_km", "lake_rear_km")
for (col in delta_cols) {
  a <- totals_w[[paste0(col, "_", SCHEMA_A)]]
  b <- totals_w[[paste0(col, "_", SCHEMA_B)]]
  totals_w[[paste0(col, "_d")]]  <- round(b - a, 2)
  totals_w[[paste0(col, "_pct")]] <- ifelse(a > 0,
    round(100 * (b - a) / a, 2), NA)
}

cat("\n=== Province-wide totals + delta ===\n")
disp_cols <- c("species",
  paste0("spawn_km_",   SCHEMA_A), paste0("spawn_km_",   SCHEMA_B), "spawn_km_d", "spawn_km_pct",
  paste0("rear_km_",    SCHEMA_A), paste0("rear_km_",    SCHEMA_B), "rear_km_d",  "rear_km_pct")
print(as.data.frame(totals_w[, disp_cols]), row.names = FALSE)

# Per-WSG delta — find the biggest movers.
top_wsg_for <- function(sp, n = 10) {
  q <- sprintf("
    WITH a AS (
      SELECT s.watershed_group_code AS wsg,
        SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)/1000.0 AS spawn_km,
        SUM(CASE WHEN h.rearing  THEN s.length_metre ELSE 0 END)/1000.0 AS rear_km
      FROM %s.streams s JOIN %s.streams_habitat_%s h
        ON h.id_segment = s.id_segment
       AND h.watershed_group_code = s.watershed_group_code
      GROUP BY s.watershed_group_code
    ), b AS (
      SELECT s.watershed_group_code AS wsg,
        SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)/1000.0 AS spawn_km,
        SUM(CASE WHEN h.rearing  THEN s.length_metre ELSE 0 END)/1000.0 AS rear_km
      FROM %s.streams s JOIN %s.streams_habitat_%s h
        ON h.id_segment = s.id_segment
       AND h.watershed_group_code = s.watershed_group_code
      GROUP BY s.watershed_group_code
    )
    SELECT COALESCE(a.wsg, b.wsg) AS wsg,
      ROUND(COALESCE(a.spawn_km, 0)::numeric, 2) AS spawn_a,
      ROUND(COALESCE(b.spawn_km, 0)::numeric, 2) AS spawn_b,
      ROUND((COALESCE(b.spawn_km, 0) - COALESCE(a.spawn_km, 0))::numeric, 2) AS spawn_d,
      ROUND(COALESCE(a.rear_km,  0)::numeric, 2) AS rear_a,
      ROUND(COALESCE(b.rear_km,  0)::numeric, 2) AS rear_b,
      ROUND((COALESCE(b.rear_km,  0) - COALESCE(a.rear_km,  0))::numeric, 2) AS rear_d
    FROM a FULL OUTER JOIN b ON a.wsg = b.wsg
    ORDER BY abs(COALESCE(b.spawn_km, 0) - COALESCE(a.spawn_km, 0)) DESC
    LIMIT %d",
    SCHEMA_A, SCHEMA_A, tolower(sp),
    SCHEMA_B, SCHEMA_B, tolower(sp),
    n)
  DBI::dbGetQuery(conn, q)
}

cat("\n=== Top 10 WSGs by absolute spawn-km shift, per species ===\n")
for (sp in species) {
  cat(sprintf("\n--- %s ---\n", sp))
  print(top_wsg_for(sp, 10), row.names = FALSE)
}

# Coverage: how many WSGs shifted at all (>1 km).
cat("\n=== Shift breadth per species ===\n")
breadth <- do.call(rbind, lapply(species, function(sp) {
  rows <- top_wsg_for(sp, 9999L)
  data.frame(
    species = sp,
    wsgs_with_sp = nrow(rows),
    spawn_shift_gt_1km = sum(abs(rows$spawn_d) > 1, na.rm = TRUE),
    spawn_b_only      = sum(rows$spawn_a == 0 & rows$spawn_b > 0, na.rm = TRUE),
    spawn_a_only      = sum(rows$spawn_a > 0 & rows$spawn_b == 0, na.rm = TRUE),
    rear_shift_gt_1km = sum(abs(rows$rear_d) > 1, na.rm = TRUE),
    stringsAsFactors = FALSE)
}))
print(breadth, row.names = FALSE)

# Persist the totals + breadth to disk for the research record.
out_dir <- file.path("data-raw", "logs", "methodology_delta")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
ts <- format(Sys.time(), "%Y%m%d_%H%M")
fname <- sprintf("%s_%s_vs_%s.rds", ts, SCHEMA_B, SCHEMA_A)
saveRDS(list(totals = totals_w, breadth = breadth,
             schema_a = SCHEMA_A, schema_b = SCHEMA_B,
             species = species),
        file.path(out_dir, fname))
cat(sprintf("\nSaved: %s\n", file.path(out_dir, fname)))
