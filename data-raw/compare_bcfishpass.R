# data-raw/compare_bcfishpass.R
#
# Compare link + fresh vs bcfishpass habitat classification for a
# watershed group. Exercises the six `lnk_pipeline_*` helpers in
# order and diffs the result against the bcfishpass reference tables
# on the read-only tunnel DB.
#
# Requirements:
#   - Local Docker fwapg on port 5432 (writable)
#   - SSH tunnel to bcfishpass reference DB on port 63333 (read-only)
#   - bcfishobs.observations loaded in local fwapg
#   - Packages: link (>= 0.2.0), fresh (>= 0.14.0)
#
# Usage:
#   Rscript data-raw/compare_bcfishpass.R                 # defaults to ADMS
#   Rscript data-raw/compare_bcfishpass.R BULK

t_start <- proc.time()
devtools::load_all()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
wsg <- if (length(commandArgs(TRUE)) > 0) commandArgs(TRUE)[1] else "ADMS"
schema <- paste0("working_", tolower(wsg))
cfg <- link::lnk_config("bcfishpass")

message("Watershed group: ", wsg)
message("Working schema:  ", schema)

# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass", user = "newgraph")
on.exit({
  DBI::dbDisconnect(conn)
  DBI::dbDisconnect(conn_ref)
}, add = TRUE)

# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------
message("\n=== setup ===")
link::lnk_pipeline_setup(conn, schema, overwrite = TRUE)

message("\n=== load ===")
link::lnk_pipeline_load(conn, aoi = wsg, cfg = cfg, schema = schema)

message("\n=== prepare ===")
link::lnk_pipeline_prepare(conn, aoi = wsg, cfg = cfg, schema = schema)

message("\n=== break ===")
link::lnk_pipeline_break(conn, aoi = wsg, cfg = cfg, schema = schema)

message("\n=== classify ===")
t0 <- proc.time()
link::lnk_pipeline_classify(conn, aoi = wsg, cfg = cfg, schema = schema)
message("  classification: ",
  round((proc.time() - t0)["elapsed"], 1), "s")

message("\n=== connect ===")
link::lnk_pipeline_connect(conn, aoi = wsg, cfg = cfg, schema = schema)

# ---------------------------------------------------------------------------
# Comparison against bcfishpass reference on tunnel DB
# ---------------------------------------------------------------------------
message("\n=== compare ===")

# Resolve species the same way as lnk_pipeline_classify
species_compare <- link:::.lnk_pipeline_classify_species(cfg, wsg)
message("Species: ", paste(species_compare, collapse = ", "))

ours <- DBI::dbGetQuery(conn, sprintf("
  SELECT h.species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
      / 1000, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric
      / 1000, 2) AS rearing_km
  FROM fresh.streams s JOIN fresh.streams_habitat h
    ON s.id_segment = h.id_segment
  WHERE h.species_code IN (%s)
  GROUP BY h.species_code ORDER BY h.species_code",
  paste0("'", species_compare, "'", collapse = ", ")))

ref_list <- lapply(species_compare, function(sp) {
  ref_cols <- DBI::dbGetQuery(conn_ref, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'bcfishpass' AND table_name = 'habitat_linear_%s'",
    tolower(sp)))
  has_rearing <- "rearing" %in% ref_cols$column_name
  rear_expr <- if (has_rearing) {
    "CASE WHEN h.rearing THEN s.length_metre ELSE 0 END"
  } else {
    "0"
  }
  DBI::dbGetQuery(conn_ref, sprintf("
    SELECT '%s' AS species_code,
      round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric
        / 1000, 2) AS spawning_km,
      round(SUM(%s)::numeric / 1000, 2) AS rearing_km
    FROM bcfishpass.streams s
    JOIN bcfishpass.habitat_linear_%s h
      ON s.segmented_stream_id = h.segmented_stream_id
    WHERE s.watershed_group_code = '%s'",
    sp, rear_expr, tolower(sp), wsg))
})
ref <- do.call(rbind, ref_list)

comparison <- data.frame(
  species = rep(species_compare, each = 2),
  habitat = rep(c("spawning", "rearing"), length(species_compare)),
  ours = NA_real_, ref = NA_real_, stringsAsFactors = FALSE)
for (i in seq_len(nrow(comparison))) {
  sp  <- comparison$species[i]
  hab <- comparison$habitat[i]
  ours_row <- ours[ours$species_code == sp, ]
  ref_row  <- ref[ref$species_code == sp, ]
  comparison$ours[i] <-
    if (nrow(ours_row) > 0) ours_row[[paste0(hab, "_km")]] else 0
  comparison$ref[i] <-
    if (nrow(ref_row) > 0) ref_row[[paste0(hab, "_km")]] else 0
}
comparison$diff_pct <- ifelse(comparison$ref == 0, NA,
  round(100 * (comparison$ours - comparison$ref) / comparison$ref, 1))

message("\n--- Comparison (", wsg, ") ---")
print(comparison, row.names = FALSE)
all_within <- all(abs(comparison$diff_pct[!is.na(comparison$diff_pct)]) < 5)
message("\nAll within 5%: ", all_within)

elapsed_total <- round((proc.time() - t_start)["elapsed"], 1)
message("\nDone. Total: ", elapsed_total, " seconds")
