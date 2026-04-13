# data-raw/compare_bcfishpass.R
#
# Compare link + fresh vs bcfishpass v0.5.0 habitat classification.
# Portable across watershed groups.
#
# Requirements:
#   - Local Docker fwapg on port 5432 (writable)
#   - SSH tunnel to bcfishpass DB on port 63333 (read-only reference)
#   - bcfishobs.observations loaded
#   - Packages: link (>= 0.1.0), fresh (>= 0.13.2)
#
# Usage:
#   source("data-raw/compare_bcfishpass.R")

# ===========================================================================
# CONFIG — change these for different WSGs
# ===========================================================================
wsg <- "ADMS"
species_compare <- c("BT", "CH", "CO", "SK")
bcfishpass_data <- "~/Projects/repo/bcfishpass/data"
rules_path <- "inst/extdata/parameters_habitat_rules_bcfishpass.yaml"
params_fresh_path <- "inst/extdata/parameters_fresh_bcfishpass.csv"

# ===========================================================================
# Step 1: Connect
# ===========================================================================
message("=== Step 1: Connect ===")
conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")
conn_ref <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 63333, dbname = "bcfishpass", user = "newgraph")
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS fresh")

# ===========================================================================
# Step 2: Load crossings
# ===========================================================================
message("\n=== Step 2: Load crossings ===")
crossings_all <- read.csv(system.file("extdata", "crossings.csv", package = "fresh"),
  stringsAsFactors = FALSE)
crossings <- crossings_all[crossings_all$watershed_group_code == wsg, ]
# Always text for consistent joins
crossings$aggregated_crossings_id <- as.character(crossings$aggregated_crossings_id)
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "crossings"),
  crossings, overwrite = TRUE)
message("  Crossings: ", nrow(crossings))

# ===========================================================================
# Step 3: Apply bcfishpass overrides
# ===========================================================================
message("\n=== Step 3: Apply overrides ===")

# Modelled crossing fixes
fixes_all <- read.csv(file.path(bcfishpass_data, "user_modelled_crossing_fixes.csv"),
  stringsAsFactors = FALSE)
fixes <- fixes_all[fixes_all$watershed_group_code == wsg, ]
names(fixes)[names(fixes) == "modelled_crossing_id"] <- "aggregated_crossings_id"
fixes$aggregated_crossings_id <- as.character(fixes$aggregated_crossings_id)
if (nrow(fixes) > 0) {
  fixes_csv <- tempfile(fileext = ".csv")
  write.csv(fixes, fixes_csv, row.names = FALSE)
  link::lnk_load(conn, csv = fixes_csv, to = "working.crossing_fixes",
    cols_id = "aggregated_crossings_id", cols_required = "structure")
  DBI::dbExecute(conn, "
    UPDATE working.crossings c SET barrier_status = 'PASSABLE'
    FROM working.crossing_fixes f
    WHERE c.aggregated_crossings_id = f.aggregated_crossings_id::text
      AND f.structure IN ('NONE', 'OBS')")
  unlink(fixes_csv)
}

# PSCIS barrier status overrides
pscis_all <- read.csv(file.path(bcfishpass_data, "user_pscis_barrier_status.csv"),
  stringsAsFactors = FALSE)
pscis <- pscis_all[pscis_all$watershed_group_code == wsg, ]
names(pscis)[names(pscis) == "stream_crossing_id"] <- "aggregated_crossings_id"
names(pscis)[names(pscis) == "user_barrier_status"] <- "barrier_status"
pscis$aggregated_crossings_id <- as.character(pscis$aggregated_crossings_id)
if (nrow(pscis) > 0) {
  pscis_csv <- tempfile(fileext = ".csv")
  write.csv(pscis, pscis_csv, row.names = FALSE)
  link::lnk_load(conn, csv = pscis_csv, to = "working.pscis_fixes",
    cols_id = "aggregated_crossings_id", cols_required = "barrier_status")
  link::lnk_override(conn, crossings = "working.crossings",
    overrides = "working.pscis_fixes",
    col_id = "aggregated_crossings_id", cols_update = "barrier_status")
  unlink(pscis_csv)
}

message("\nBarrier status:")
print(DBI::dbGetQuery(conn,
  "SELECT barrier_status, count(*) as n FROM working.crossings
   GROUP BY barrier_status ORDER BY n DESC"), row.names = FALSE)

# ===========================================================================
# Step 4: Build break sources
# ===========================================================================
message("\n=== Step 4: Break sources ===")
crossings_spec <- list(
  table = "working.crossings",
  label_col = "barrier_status",
  label_map = c("BARRIER" = "barrier", "POTENTIAL" = "potential",
                "PASSABLE" = "passable", "UNKNOWN" = "unknown"))

falls_all <- read.csv(system.file("extdata", "falls.csv", package = "fresh"),
  stringsAsFactors = FALSE)
falls <- falls_all[falls_all$watershed_group_code == wsg & falls_all$barrier_ind == TRUE, ]
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "falls"),
  falls, overwrite = TRUE)
falls_spec <- list(table = "working.falls", label = "blocked")
message("  Falls: ", nrow(falls))

# ===========================================================================
# Step 5: Pre-compute barriers + overrides
# ===========================================================================
message("\n=== Step 5: Barrier overrides ===")

# Pre-compute gradient barriers
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.streams_blk")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.streams_blk AS
  SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = '%s'
    AND edge_type != 6010", wsg))
fresh::frs_break_find(conn, "working.streams_blk",
  attribute = "gradient",
  classes = c("1500" = 0.15, "2000" = 0.20, "2500" = 0.25, "3000" = 0.30),
  to = "working.gradient_barriers_raw")

# Enrich with ltree + round measures
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.natural_barriers")
DBI::dbExecute(conn, "
  CREATE TABLE working.natural_barriers AS
  SELECT g.blue_line_key, round(g.downstream_route_measure) AS downstream_route_measure,
    g.label, s.wscode_ltree, s.localcode_ltree
  FROM working.gradient_barriers_raw g
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON g.blue_line_key = s.blue_line_key
    AND g.downstream_route_measure >= s.downstream_route_measure
    AND g.downstream_route_measure < s.upstream_route_measure")
DBI::dbExecute(conn, "
  INSERT INTO working.natural_barriers
  SELECT f.blue_line_key, round(f.downstream_route_measure), 'blocked',
    s.wscode_ltree, s.localcode_ltree
  FROM working.falls f
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON f.blue_line_key = s.blue_line_key
    AND f.downstream_route_measure >= s.downstream_route_measure
    AND f.downstream_route_measure < s.upstream_route_measure")
n_barriers <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.natural_barriers")[[1]]
message("  Natural barriers: ", n_barriers)

# Load habitat confirmations
link::lnk_load(conn,
  csv = file.path(bcfishpass_data, "user_habitat_classification.csv"),
  to = "working.user_habitat_classification",
  cols_id = "blue_line_key",
  cols_required = c("species_code", "upstream_route_measure", "habitat_ind"))

# Compute overrides
params_fresh_df <- read.csv(params_fresh_path, stringsAsFactors = FALSE)
devtools::load_all()
lnk_barrier_overrides(conn,
  barriers = "working.natural_barriers",
  observations = "bcfishobs.observations",
  habitat = "working.user_habitat_classification",
  params = params_fresh_df,
  to = "working.barrier_overrides")

# ===========================================================================
# Step 6: Run fresh — single detection, single truth
# ===========================================================================
message("\n=== Step 6: Run fresh ===")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams CASCADE")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams_habitat CASCADE")

# Add gradient_NNNN label to pre-computed barriers for access gating
DBI::dbExecute(conn, "ALTER TABLE working.gradient_barriers_raw ADD COLUMN IF NOT EXISTS label_access text")
DBI::dbExecute(conn, "UPDATE working.gradient_barriers_raw SET label_access = 'gradient_' || lpad(gradient_class::text, 4, '0')")

# Pass pre-computed barriers as a break source — ONE detection, used for BOTH
# overrides (step 5) AND segmentation (step 6). No internal gradient detection.
gradient_spec <- list(
  table = "working.gradient_barriers_raw",
  label_col = "label_access"
)

t0 <- proc.time()
result <- fresh::frs_habitat(conn,
  wsg = wsg,
  species = species_compare,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(crossings_spec, falls_spec, gradient_spec),
  breaks_gradient = numeric(0),  # disable internal — we supply barriers
  rules = rules_path,
  params_fresh = params_fresh_df,
  barrier_overrides = "working.barrier_overrides",
  verbose = TRUE
)
elapsed <- (proc.time() - t0)["elapsed"]
message("frs_habitat completed in ", round(elapsed, 1), " seconds")

# ===========================================================================
# Step 7: Compare
# ===========================================================================
message("\n=== Step 7: Compare ===")

ours <- DBI::dbGetQuery(conn, sprintf("
  SELECT h.species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_km
  FROM fresh.streams s JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  WHERE h.species_code IN (%s)
  GROUP BY h.species_code ORDER BY h.species_code",
  paste0("'", species_compare, "'", collapse = ", ")))

ref_list <- lapply(species_compare, function(sp) {
  DBI::dbGetQuery(conn_ref, sprintf("
    SELECT '%s' AS species_code,
      round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS spawning_km,
      round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_km
    FROM bcfishpass.streams s
    JOIN bcfishpass.habitat_linear_%s h ON s.segmented_stream_id = h.segmented_stream_id
    WHERE s.watershed_group_code = '%s'", sp, tolower(sp), wsg))
})
ref <- do.call(rbind, ref_list)

comparison <- data.frame(
  species = rep(species_compare, each = 2),
  habitat = rep(c("spawning", "rearing"), length(species_compare)),
  ours = NA_real_, ref = NA_real_, stringsAsFactors = FALSE)
for (i in seq_len(nrow(comparison))) {
  sp <- comparison$species[i]; hab <- comparison$habitat[i]
  ours_row <- ours[ours$species_code == sp, ]
  ref_row <- ref[ref$species_code == sp, ]
  comparison$ours[i] <- if (nrow(ours_row) > 0) ours_row[[paste0(hab, "_km")]] else 0
  comparison$ref[i] <- if (nrow(ref_row) > 0) ref_row[[paste0(hab, "_km")]] else 0
}
comparison$diff_pct <- ifelse(comparison$ref == 0, NA,
  round(100 * (comparison$ours - comparison$ref) / comparison$ref, 1))

message("\n--- Comparison (", wsg, ") ---")
print(comparison, row.names = FALSE)
message("\nAll within 5%: ", all(abs(comparison$diff_pct[!is.na(comparison$diff_pct)]) < 5))

DBI::dbDisconnect(conn_ref)
DBI::dbDisconnect(conn)
message("\nDone.")
