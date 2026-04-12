# data-raw/compare_adms.R
#
# Compare link + fresh vs bcfishpass v0.5.0 habitat classification.
#
# Sub-basin iteration for fast development (5s per run).
# Feeds bcfishpass-matching params so the only differences should be from
# segmentation resolution (different break points → different segment
# gradient averages near thresholds).
#
# Requirements:
#   - Local Docker fwapg DB on port 5432 (writable)
#   - SSH tunnel to bcfishpass DB on port 63333 (read-only reference)
#   - Packages: link (>= 0.0.0.9000), fresh (>= 0.12.0), DBI, RPostgres
#
# Usage:
#   source("data-raw/compare_adms.R")

wsg <- "ADMS"
# Set to a wscode prefix for fast sub-basin iteration, or NULL for full ADMS
# sub_basin <- "100.190442.999098.995997.058910.432966"
sub_basin <- NULL
bcfishpass_data <- "~/Projects/repo/bcfishpass/data"

# bcfishpass v0.5.0 classifies these species for ADMS (verified from
# habitat_linear_* tables on tunnel DB):
#   BT (2416 rows), CH (1211), CO (1417), SK (672)
species_compare <- c("BT", "CH", "CO", "SK")

# ===========================================================================
# Step 1: Connect
# ===========================================================================

message("=== Step 1: Connect ===")
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost", port = 5432,
  dbname = "fwapg", user = "postgres", password = "postgres"
)
conn_ref <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost", port = 63333,
  dbname = "bcfishpass", user = "newgraph"
)
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS fresh")
message("  Local Docker: OK")
message("  Tunnel: OK")

# ===========================================================================
# Step 2: Load crossings for sub-basin
# ===========================================================================

message("\n=== Step 2: Load crossings (sub-basin) ===")
crossings_csv <- system.file("extdata", "crossings.csv", package = "fresh")
crossings_all <- read.csv(crossings_csv, stringsAsFactors = FALSE)
adms_crossings <- crossings_all[crossings_all$watershed_group_code == wsg, ]

# Write all ADMS crossings to DB first (need ltree to filter sub-basin)
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "adms_crossings_all"),
                  adms_crossings, overwrite = TRUE)

# Enrich with ltree from FWA
DBI::dbExecute(conn, "
  ALTER TABLE working.adms_crossings_all
    ADD COLUMN IF NOT EXISTS wscode_ltree ltree,
    ADD COLUMN IF NOT EXISTS localcode_ltree ltree
")
n_enriched <- DBI::dbExecute(conn, "
  UPDATE working.adms_crossings_all c
  SET wscode_ltree = s.wscode_ltree,
      localcode_ltree = s.localcode_ltree
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE c.blue_line_key = s.blue_line_key
    AND c.downstream_route_measure >= s.downstream_route_measure
    AND c.downstream_route_measure < s.upstream_route_measure
")
message("  Enriched ", n_enriched, " of ", nrow(adms_crossings), " crossings with ltree")

# Fallback for boundary cases
DBI::dbExecute(conn, "
  UPDATE working.adms_crossings_all c
  SET wscode_ltree = sub.wscode_ltree,
      localcode_ltree = sub.localcode_ltree
  FROM (
    SELECT DISTINCT ON (c2.aggregated_crossings_id)
      c2.aggregated_crossings_id,
      s.wscode_ltree, s.localcode_ltree
    FROM working.adms_crossings_all c2
    JOIN whse_basemapping.fwa_stream_networks_sp s
      ON c2.blue_line_key = s.blue_line_key
    WHERE c2.localcode_ltree IS NULL
    ORDER BY c2.aggregated_crossings_id,
             abs(c2.downstream_route_measure - s.downstream_route_measure)
  ) sub
  WHERE c.aggregated_crossings_id = sub.aggregated_crossings_id
    AND c.localcode_ltree IS NULL
")

# Filter to sub-basin (or use all ADMS)
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.adms_crossings")
if (!is.null(sub_basin)) {
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE working.adms_crossings AS
    SELECT * FROM working.adms_crossings_all
    WHERE wscode_ltree <@ '%s'::ltree
  ", sub_basin))
} else {
  DBI::dbExecute(conn, "
    CREATE TABLE working.adms_crossings AS
    SELECT * FROM working.adms_crossings_all
  ")
}

n_sub <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.adms_crossings")[[1]]
message("  Crossings: ", n_sub)

# ===========================================================================
# Step 3: Apply bcfishpass overrides
# ===========================================================================

message("\n=== Step 3: Apply overrides ===")

# Modelled crossing fixes
fixes_all <- read.csv(
  file.path(bcfishpass_data, "user_modelled_crossing_fixes.csv"),
  stringsAsFactors = FALSE
)
adms_fixes <- fixes_all[fixes_all$watershed_group_code == wsg, ]
names(adms_fixes)[names(adms_fixes) == "modelled_crossing_id"] <-
  "aggregated_crossings_id"

if (nrow(adms_fixes) > 0) {
  fixes_csv <- tempfile(fileext = ".csv")
  write.csv(adms_fixes, fixes_csv, row.names = FALSE)
  link::lnk_load(conn, csv = fixes_csv, to = "working.adms_fixes",
    cols_id = "aggregated_crossings_id", cols_required = "structure")
  n_none <- DBI::dbExecute(conn, "
    UPDATE working.adms_crossings c SET barrier_status = 'PASSABLE'
    FROM working.adms_fixes f
    WHERE c.aggregated_crossings_id::text = f.aggregated_crossings_id::text
      AND f.structure = 'NONE'")
  n_obs <- DBI::dbExecute(conn, "
    UPDATE working.adms_crossings c SET barrier_status = 'PASSABLE'
    FROM working.adms_fixes f
    WHERE c.aggregated_crossings_id::text = f.aggregated_crossings_id::text
      AND f.structure = 'OBS'")
  message("  Fixes: NONE->PASSABLE=", n_none, ", OBS->PASSABLE=", n_obs)
  unlink(fixes_csv)
}

# PSCIS barrier status overrides
pscis_status_all <- read.csv(
  file.path(bcfishpass_data, "user_pscis_barrier_status.csv"),
  stringsAsFactors = FALSE
)
adms_pscis_status <- pscis_status_all[
  pscis_status_all$watershed_group_code == wsg, ]
names(adms_pscis_status)[names(adms_pscis_status) == "stream_crossing_id"] <-
  "aggregated_crossings_id"
names(adms_pscis_status)[names(adms_pscis_status) == "user_barrier_status"] <-
  "barrier_status"

if (nrow(adms_pscis_status) > 0) {
  pscis_csv <- tempfile(fileext = ".csv")
  write.csv(adms_pscis_status, pscis_csv, row.names = FALSE)
  link::lnk_load(conn, csv = pscis_csv, to = "working.adms_pscis_fixes",
    cols_id = "aggregated_crossings_id", cols_required = "barrier_status")
  link::lnk_override(conn, crossings = "working.adms_crossings",
    overrides = "working.adms_pscis_fixes",
    col_id = "aggregated_crossings_id", cols_update = "barrier_status")
  unlink(pscis_csv)
}

message("\nPost-override barrier status:")
print(DBI::dbGetQuery(conn,
  "SELECT barrier_status, count(*) as n FROM working.adms_crossings
   GROUP BY barrier_status ORDER BY n DESC"), row.names = FALSE)

# ===========================================================================
# Step 4: Run fresh (bcfishpass-matching params)
# ===========================================================================

message("\n=== Step 4: Run fresh (sub-basin, bcfishpass v0.5.0 params) ===")

# Crossings break geometry. Labels for access classification:
# bcfishpass natural access = gradient barriers + falls only.
# Crossing barrier_status doesn't block natural access.
crossings_spec <- list(
  table = "working.adms_crossings",
  label_col = "barrier_status",
  label_map = c(
    # bcfishpass natural access = gradient barriers + falls ONLY.
    # Crossing barrier_status does NOT block natural access — crossings only
    # break geometry. All labels here are non-blocking.
    "BARRIER" = "barrier",
    "POTENTIAL" = "potential",
    "PASSABLE" = "passable",
    "UNKNOWN" = "unknown"
  )
)

# Falls as blocked break source
falls_csv <- system.file("extdata", "falls.csv", package = "fresh")
falls_all <- read.csv(falls_csv, stringsAsFactors = FALSE)
adms_falls <- falls_all[falls_all$watershed_group_code == wsg &
                         falls_all$barrier_ind == TRUE, ]
DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "adms_falls"),
                  adms_falls, overwrite = TRUE)
message("Falls (barrier): ", nrow(adms_falls))

falls_spec <- list(
  table = "working.adms_falls",
  label = "blocked"
)

# bcfishpass-matching params
rules_path <- "inst/extdata/parameters_habitat_rules_bcfishpass.yaml"
params_fresh_path <- "inst/extdata/parameters_fresh_bcfishpass.csv"
params_fresh_df <- read.csv(params_fresh_path, stringsAsFactors = FALSE)

aoi_where <- if (!is.null(sub_basin)) {
  sprintf("wscode_ltree <@ '%s'::ltree", sub_basin)
} else {
  NULL  # full WSG
}

# Drop stale tables
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams CASCADE")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams_habitat CASCADE")

# Step 4a: Pass 1 — run fresh WITHOUT overrides to build breaks table
message("\n--- Pass 1: frs_habitat (builds breaks + segments) ---")
t0 <- proc.time()
fresh::frs_habitat(conn,
  wsg = wsg,
  aoi = aoi_where,
  species = species_compare,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(crossings_spec, falls_spec),
  breaks_gradient = c(0.15, 0.20, 0.25, 0.30),
  rules = rules_path,
  params_fresh = params_fresh_df,
  verbose = TRUE
)
message("Pass 1: ", round((proc.time() - t0)["elapsed"], 1), " seconds")

# Step 4b: Build barrier overrides from breaks table
message("\n--- Building barrier overrides ---")
link::lnk_load(conn,
  csv = "~/Projects/repo/bcfishpass/data/user_habitat_classification.csv",
  to = "working.user_habitat_classification",
  cols_id = "blue_line_key",
  cols_required = c("species_code", "upstream_route_measure", "habitat_ind"))
devtools::load_all()
lnk_barrier_overrides(conn,
  barriers = "fresh.streams_breaks",
  observations = "bcfishobs.observations",
  habitat = "working.user_habitat_classification",
  params = params_fresh_df,
  to = "working.barrier_overrides")

# Step 4c: Pass 2 — re-run with overrides
message("\n--- Pass 2: frs_habitat (with barrier overrides) ---")
t0 <- proc.time()
result <- fresh::frs_habitat(conn,
  wsg = wsg,
  aoi = aoi_where,
  species = species_compare,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(crossings_spec, falls_spec),
  breaks_gradient = c(0.15, 0.20, 0.25, 0.30),
  rules = rules_path,
  params_fresh = params_fresh_df,
  barrier_overrides = "working.barrier_overrides",
  verbose = TRUE
)
elapsed <- (proc.time() - t0)["elapsed"]
message("frs_habitat completed in ", round(elapsed, 1), " seconds")
print(result)

# frs_habitat (>= 0.12.3) runs frs_cluster internally via .frs_connectivity_checks()
# No need to call frs_cluster separately — would double-remove rearing segments.

# ===========================================================================
# Step 5: Compare
# ===========================================================================

message("\n=== Step 5: Compare classified habitat ===")

# Our totals — all species fresh classified
ours <- DBI::dbGetQuery(conn, sprintf("
  SELECT
    h.species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000.0, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000.0, 2) AS rearing_km,
    count(*) AS n_segments,
    count(*) FILTER (WHERE h.spawning) AS n_spawning,
    count(*) FILTER (WHERE h.rearing) AS n_rearing
  FROM fresh.streams s
  JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  WHERE h.species_code IN (%s)
  GROUP BY h.species_code
  ORDER BY h.species_code",
  paste0("'", species_compare, "'", collapse = ", ")
))
message("\nOurs (fresh 0.12.0):")
print(ours, row.names = FALSE)

# bcfishpass reference — per-species habitat_linear_* tables
sub_filter <- if (!is.null(sub_basin)) {
  sprintf("AND s.wscode_ltree <@ '%s'::ltree", sub_basin)
} else {
  ""
}
ref_query <- "
  SELECT '%s' AS species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000.0, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000.0, 2) AS rearing_km,
    count(*) AS n_segments
  FROM bcfishpass.streams s
  JOIN bcfishpass.habitat_linear_%s h ON s.segmented_stream_id = h.segmented_stream_id
  WHERE s.watershed_group_code = 'ADMS'
    %s"

ref_list <- lapply(species_compare, function(sp) {
  DBI::dbGetQuery(conn_ref, sprintf(ref_query, sp, tolower(sp), sub_filter))
})
ref <- do.call(rbind, ref_list)
message("\nbcfishpass v0.5.0 reference:")
print(ref, row.names = FALSE)

# Build comparison
comparison <- data.frame(
  species = rep(species_compare, each = 2),
  habitat = rep(c("spawning", "rearing"), length(species_compare)),
  ours = NA_real_,
  ref = NA_real_,
  stringsAsFactors = FALSE
)
for (i in seq_len(nrow(comparison))) {
  sp <- comparison$species[i]
  hab <- comparison$habitat[i]
  ours_row <- ours[ours$species_code == sp, ]
  ref_row <- ref[ref$species_code == sp, ]
  comparison$ours[i] <- if (nrow(ours_row) > 0) ours_row[[paste0(hab, "_km")]] else 0
  comparison$ref[i] <- if (nrow(ref_row) > 0) ref_row[[paste0(hab, "_km")]] else 0
}
comparison$diff_km <- round(comparison$ours - comparison$ref, 2)
comparison$diff_pct <- ifelse(
  is.na(comparison$ref) | comparison$ref == 0,
  NA_real_,
  round(100 * comparison$diff_km / comparison$ref, 1)
)

message("\n--- Comparison ---")
print(comparison, row.names = FALSE)

# All species share the same segmented streams table — count is the same per species
n_seg_ours <- DBI::dbGetQuery(conn, "SELECT count(*) FROM fresh.streams")[[1]]
n_seg_ref <- DBI::dbGetQuery(conn_ref, sprintf("
  SELECT count(*) FROM bcfishpass.streams
  WHERE watershed_group_code = 'ADMS' %s
", sub_filter))[[1]]
message("\nSegments: ours=", n_seg_ours, " ref=", n_seg_ref)

within_5pct <- all(abs(comparison$diff_pct[!is.na(comparison$diff_pct)]) < 5)
message("All within 5%: ", within_5pct)

# Save
saveRDS(comparison, "data-raw/adms_comparison.rds")
message("\nSaved to data-raw/adms_comparison.rds")

DBI::dbDisconnect(conn_ref)
DBI::dbDisconnect(conn)
message("Done.")
