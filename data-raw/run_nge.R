# data-raw/run_nge.R
#
# Run the link + fresh pipeline with NGE defaults for any watershed group.
# This is the production template — not the bcfishpass comparison script.
#
# Prerequisites:
#   - Local Docker fwapg on port 5432 (or PG_*_SHARE env vars)
#   - bcfishobs.observations loaded (run bcfishobs/scripts/setup.sh)
#   - Packages: link (>= 0.0.0.9000), fresh (>= 0.12.9)
#
# Usage:
#   source("data-raw/run_nge.R")

# --- Config ---
wsg <- "ADMS"
species <- c("BT", "CH", "CO", "SK")
bcfishpass_data <- "~/Projects/repo/bcfishpass/data"

# ===========================================================================
# Step 1: Connect
# ===========================================================================
message("=== Step 1: Connect ===")
conn <- link::lnk_db_conn()
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS fresh")

# ===========================================================================
# Step 2: Load crossings + apply overrides
# ===========================================================================
message("\n=== Step 2: Load crossings + overrides ===")

# Crossings from fresh
crossings_csv <- system.file("extdata", "crossings.csv", package = "fresh")
crossings_all <- read.csv(crossings_csv, stringsAsFactors = FALSE)
crossings <- crossings_all[crossings_all$watershed_group_code == wsg, ]
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "crossings"),
                  crossings, overwrite = TRUE)
message("  Crossings: ", nrow(crossings))

# Modelled crossing fixes
fixes <- read.csv(file.path(bcfishpass_data, "user_modelled_crossing_fixes.csv"),
                  stringsAsFactors = FALSE)
fixes <- fixes[fixes$watershed_group_code == wsg, ]
names(fixes)[names(fixes) == "modelled_crossing_id"] <- "aggregated_crossings_id"
if (nrow(fixes) > 0) {
  fixes_csv <- tempfile(fileext = ".csv")
  write.csv(fixes, fixes_csv, row.names = FALSE)
  link::lnk_load(conn, csv = fixes_csv, to = "working.fixes",
    cols_id = "aggregated_crossings_id", cols_required = "structure")
  DBI::dbExecute(conn, "
    UPDATE working.crossings c SET barrier_status = 'PASSABLE'
    FROM working.fixes f
    WHERE c.aggregated_crossings_id::text = f.aggregated_crossings_id::text
      AND f.structure IN ('NONE', 'OBS')")
  unlink(fixes_csv)
}

# PSCIS barrier status overrides
pscis_status <- read.csv(file.path(bcfishpass_data, "user_pscis_barrier_status.csv"),
                         stringsAsFactors = FALSE)
pscis_status <- pscis_status[pscis_status$watershed_group_code == wsg, ]
names(pscis_status)[names(pscis_status) == "stream_crossing_id"] <- "aggregated_crossings_id"
names(pscis_status)[names(pscis_status) == "user_barrier_status"] <- "barrier_status"
if (nrow(pscis_status) > 0) {
  pscis_csv <- tempfile(fileext = ".csv")
  write.csv(pscis_status, pscis_csv, row.names = FALSE)
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
# Step 3: Build break sources
# ===========================================================================
message("\n=== Step 3: Break sources ===")

# Crossings — don't block natural access
crossings_spec <- list(
  table = "working.crossings",
  label_col = "barrier_status",
  label_map = c(
    "BARRIER" = "barrier",
    "POTENTIAL" = "potential",
    "PASSABLE" = "passable",
    "UNKNOWN" = "unknown"
  )
)

# Falls
falls_csv <- system.file("extdata", "falls.csv", package = "fresh")
falls_all <- read.csv(falls_csv, stringsAsFactors = FALSE)
falls <- falls_all[falls_all$watershed_group_code == wsg &
                    falls_all$barrier_ind == TRUE, ]
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "falls"),
                  falls, overwrite = TRUE)
message("  Falls: ", nrow(falls))

falls_spec <- list(table = "working.falls", label = "blocked")

# ===========================================================================
# Step 4: Build barrier overrides
# ===========================================================================
message("\n=== Step 4: Barrier overrides ===")

# Pre-compute gradient barriers
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.streams_blk")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.streams_blk AS
  SELECT DISTINCT blue_line_key FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = '%s'", wsg))

fresh::frs_break_find(conn, "working.streams_blk",
  attribute = "gradient",
  classes = c("1500" = 0.15, "2000" = 0.20, "2500" = 0.25, "3000" = 0.30),
  to = "working.gradient_barriers_raw")

# Enrich with ltree
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
# Add falls
DBI::dbExecute(conn, "
  INSERT INTO working.natural_barriers
  SELECT f.blue_line_key, round(f.downstream_route_measure), 'blocked',
    s.wscode_ltree, s.localcode_ltree
  FROM working.falls f
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON f.blue_line_key = s.blue_line_key
    AND f.downstream_route_measure >= s.downstream_route_measure
    AND f.downstream_route_measure < s.upstream_route_measure")

# Load habitat confirmations
link::lnk_load(conn,
  csv = file.path(bcfishpass_data, "user_habitat_classification.csv"),
  to = "working.user_habitat_classification",
  cols_id = "blue_line_key",
  cols_required = c("species_code", "upstream_route_measure", "habitat_ind"))

# Build overrides
params_fresh <- read.csv(
  system.file("extdata", "parameters_fresh.csv", package = "fresh"),
  stringsAsFactors = FALSE)
link::lnk_barrier_overrides(conn,
  barriers = "working.natural_barriers",
  observations = "bcfishobs.observations",
  habitat = "working.user_habitat_classification",
  params = params_fresh,
  to = "working.barrier_overrides")

# ===========================================================================
# Step 5: Run fresh with NGE defaults
# ===========================================================================
message("\n=== Step 5: Run fresh (NGE defaults) ===")

DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams CASCADE")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams_habitat CASCADE")

rules_path <- system.file("extdata", "parameters_habitat_rules.yaml", package = "link")

t0 <- proc.time()
result <- fresh::frs_habitat(conn,
  wsg = wsg,
  species = species,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(crossings_spec, falls_spec),
  rules = rules_path,
  barrier_overrides = "working.barrier_overrides",
  verbose = TRUE
)
elapsed <- (proc.time() - t0)["elapsed"]
message("frs_habitat completed in ", round(elapsed, 1), " seconds")
print(result)

# ===========================================================================
# Step 6: Summary
# ===========================================================================
message("\n=== Step 6: Habitat summary ===")

summary <- DBI::dbGetQuery(conn, sprintf("
  SELECT
    h.species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000.0, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000.0, 2) AS rearing_km,
    count(*) FILTER (WHERE h.spawning) AS n_spawning,
    count(*) FILTER (WHERE h.rearing) AS n_rearing
  FROM fresh.streams s
  JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  WHERE h.species_code IN (%s)
  GROUP BY h.species_code
  ORDER BY h.species_code",
  paste0("'", species, "'", collapse = ", ")
))

print(summary, row.names = FALSE)

DBI::dbDisconnect(conn)
message("\nDone.")
