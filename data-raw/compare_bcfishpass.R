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
t_start <- proc.time()
devtools::load_all()
wsg <- if (length(commandArgs(TRUE)) > 0) commandArgs(TRUE)[1] else "ADMS"
# Sub-basin AOI for fast iteration (NULL = full WSG)
aoi <- NULL
# aoi <- "wscode_ltree <@ '400.431358'::ltree"  # ~300 segments, fast
bcfishpass_data <- system.file("extdata", "bcfishpass", package = "link")
rules_path <- system.file("extdata", "parameters_habitat_rules_bcfishpass.yaml", package = "link")
params_fresh_path <- system.file("extdata", "parameters_fresh_bcfishpass.csv", package = "link")

# Species from wsg_species_presence — same source bcfishpass uses
wsg_spp <- read.csv(system.file("extdata", "wsg_species_presence.csv", package = "fresh"),
  stringsAsFactors = FALSE)
wsg_row <- wsg_spp[wsg_spp$watershed_group_code == wsg, ]
spp_cols <- c("bt","ch","cm","co","ct","dv","pk","rb","sk","st","wct")
species_compare <- toupper(spp_cols[vapply(spp_cols, function(x)
  identical(wsg_row[[x]], "t"), logical(1))])
# Species to model: from habitat dimensions CSV (defines which species this config covers)
# Intersect with WSG species presence to get species for this specific watershed
dims <- read.csv(system.file("extdata", "parameters_habitat_dimensions_bcfishpass.csv",
  package = "link"), stringsAsFactors = FALSE)
species_compare <- intersect(unique(dims$species), species_compare)
params_fresh_df <- read.csv(params_fresh_path, stringsAsFactors = FALSE)
message("Species for ", wsg, ": ", paste(species_compare, collapse = ", "))

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

# Misc crossings (weirs, unassessed culverts, flood control)
misc_all <- read.csv(file.path(bcfishpass_data, "user_crossings_misc.csv"),
  stringsAsFactors = FALSE)
misc <- misc_all[misc_all$watershed_group_code == wsg, ]
if (nrow(misc) > 0) {
  misc$aggregated_crossings_id <- as.character(misc$user_crossing_misc_id + 1200000000L)
  # Align columns with crossings table, fill missing with NA
  for (col in setdiff(names(crossings), names(misc))) misc[[col]] <- NA
  DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "crossings"),
    misc[, names(crossings)], append = TRUE)
}
message("  Misc crossings: ", nrow(misc))

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

# User-identified definite barriers (always block, all species)
definite_all <- read.csv(file.path(bcfishpass_data, "user_barriers_definite.csv"),
  stringsAsFactors = FALSE)
definite <- definite_all[definite_all$watershed_group_code == wsg, ]
if (nrow(definite) > 0) {
  DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "barriers_definite"),
    definite, overwrite = TRUE)
} else {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.barriers_definite")
  DBI::dbExecute(conn, "CREATE TABLE working.barriers_definite (
    blue_line_key integer, downstream_route_measure double precision)")
}
message("  User definite barriers: ", nrow(definite))

# ===========================================================================
# Step 5: Pre-compute barriers + overrides
# ===========================================================================
message("\n=== Step 5: Barrier overrides ===")

# Load barrier definite control — used in two places:
# 1. Remove passable barriers (barrier_ind=false) from gradient detection
# 2. Prevent overrides on controlled barriers (any control row blocks override)
definite_ctrl <- read.csv(file.path(bcfishpass_data, "user_barriers_definite_control.csv"),
  stringsAsFactors = FALSE)
definite_ctrl_wsg <- definite_ctrl[definite_ctrl$watershed_group_code == wsg, ]
if (nrow(definite_ctrl_wsg) > 0) {
  ctrl_csv <- tempfile(fileext = ".csv")
  write.csv(definite_ctrl_wsg, ctrl_csv, row.names = FALSE)
  lnk_load(conn, csv = ctrl_csv, to = "working.barriers_definite_control",
    cols_id = "blue_line_key", cols_required = c("downstream_route_measure", "barrier_ind"))
  unlink(ctrl_csv)
  ctrl_table <- "working.barriers_definite_control"
} else {
  ctrl_table <- NULL
}
message("  Barrier definite controls: ", nrow(definite_ctrl_wsg))

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

# Remove gradient barriers where control says barrier_ind = false (passable)
# bcfishpass does this in barriers_gradient.sql: WHERE (p.barrier_ind IS NULL or p.barrier_ind is true)
if (nrow(definite_ctrl_wsg) > 0) {
  n_pre <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.gradient_barriers_raw")[[1]]
  DBI::dbExecute(conn, "
    DELETE FROM working.gradient_barriers_raw g
    USING working.barriers_definite_control c
    WHERE g.blue_line_key = c.blue_line_key
      AND abs(g.downstream_route_measure - c.downstream_route_measure) < 1
      AND c.barrier_ind::boolean = false")
  n_post <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.gradient_barriers_raw")[[1]]
  message("  Control passable removals: ", n_pre - n_post)
}

# Enrich with ltree for fwa_upstream joins (needed for both overrides and minimal filter)
DBI::dbExecute(conn, "ALTER TABLE working.gradient_barriers_raw ADD COLUMN IF NOT EXISTS wscode_ltree ltree")
DBI::dbExecute(conn, "ALTER TABLE working.gradient_barriers_raw ADD COLUMN IF NOT EXISTS localcode_ltree ltree")
DBI::dbExecute(conn, "
  UPDATE working.gradient_barriers_raw g
  SET wscode_ltree = s.wscode_ltree, localcode_ltree = s.localcode_ltree
  FROM whse_basemapping.fwa_stream_networks_sp s
  WHERE g.blue_line_key = s.blue_line_key
    AND g.downstream_route_measure >= s.downstream_route_measure
    AND g.downstream_route_measure < s.upstream_route_measure")

# Build natural_barriers (FULL set) for barrier overrides BEFORE removing non-minimal
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
# User definite barriers — always block (like falls)
DBI::dbExecute(conn, "
  INSERT INTO working.natural_barriers
  SELECT d.blue_line_key, round(d.downstream_route_measure), 'blocked',
    s.wscode_ltree, s.localcode_ltree
  FROM working.barriers_definite d
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON d.blue_line_key = s.blue_line_key
    AND d.downstream_route_measure >= s.downstream_route_measure
    AND d.downstream_route_measure < s.upstream_route_measure")
n_barriers <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.natural_barriers")[[1]]
message("  Natural barriers: ", n_barriers)

# Load habitat confirmations
link::lnk_load(conn,
  csv = file.path(bcfishpass_data, "user_habitat_classification.csv"),
  to = "working.user_habitat_classification",
  cols_id = "blue_line_key",
  cols_required = c("species_code", "upstream_route_measure", "habitat_ind"))

# Compute overrides
lnk_barrier_overrides(conn,
  barriers = "working.natural_barriers",
  observations = "bcfishobs.observations",
  habitat = "working.user_habitat_classification",
  # control = ctrl_table,  # deferred to lnk_habitat — bcfishpass applies at per-model barrier build, not override
  params = params_fresh_df,
  to = "working.barrier_overrides")

# ===========================================================================
# Step 5b: Per-model non-minimal barrier removal
# ===========================================================================
# bcfishpass builds separate barrier tables per species group, each with
# different gradient classes. Non-minimal removal runs within each model.
# The union of all per-model minimal sets becomes the segmentation breaks.
message("\n=== Step 5b: Per-model non-minimal barriers ===")

# Index the enriched barriers for fwa_upstream
DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS gbr_blk_idx ON working.gradient_barriers_raw (blue_line_key)")
DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS gbr_ws_gidx ON working.gradient_barriers_raw USING gist (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS gbr_ws_bidx ON working.gradient_barriers_raw USING btree (wscode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS gbr_lc_gidx ON working.gradient_barriers_raw USING gist (localcode_ltree)")
DBI::dbExecute(conn, "CREATE INDEX IF NOT EXISTS gbr_lc_bidx ON working.gradient_barriers_raw USING btree (localcode_ltree)")

# Per-model gradient classes (matching bcfishpass model_access_*.sql)
models <- list(
  bt              = c(2500, 3000),
  ch_cm_co_pk_sk  = c(1500, 2000, 2500, 3000),
  st              = c(2000, 2500, 3000),
  wct             = c(2000, 2500, 3000)
)

# Build per-model barrier tables, remove non-minimal within each, collect minimal positions
all_minimal <- character(0)
for (model_name in names(models)) {
  classes <- models[[model_name]]
  class_filter <- paste(classes, collapse = ", ")
  model_tbl <- paste0("working.barriers_", model_name)

  # Create model table: gradient barriers + falls + definite barriers
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", model_tbl))
  DBI::dbExecute(conn, sprintf("
    CREATE TABLE %s AS
    SELECT blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree
    FROM working.gradient_barriers_raw
    WHERE gradient_class IN (%s)
    UNION ALL
    SELECT f.blue_line_key, f.downstream_route_measure,
      s.wscode_ltree, s.localcode_ltree
    FROM working.falls f
    JOIN whse_basemapping.fwa_stream_networks_sp s
      ON f.blue_line_key = s.blue_line_key
      AND f.downstream_route_measure >= s.downstream_route_measure
      AND f.downstream_route_measure < s.upstream_route_measure
    WHERE s.watershed_group_code = '%s'", model_tbl, class_filter, wsg))

  # Index for non-minimal removal
  DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s (blue_line_key)", model_tbl))
  DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s USING gist (wscode_ltree)", model_tbl))
  DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s USING btree (wscode_ltree)", model_tbl))
  DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s USING gist (localcode_ltree)", model_tbl))
  DBI::dbExecute(conn, sprintf("CREATE INDEX ON %s USING btree (localcode_ltree)", model_tbl))

  n_pre <- DBI::dbGetQuery(conn, sprintf("SELECT count(*) FROM %s", model_tbl))[[1]]
  DBI::dbExecute(conn, sprintf("
    DELETE FROM %s a
    WHERE EXISTS (
      SELECT 1 FROM %s b
      WHERE b.ctid != a.ctid
        AND fwa_upstream(
          b.blue_line_key, b.downstream_route_measure,
          b.wscode_ltree, b.localcode_ltree,
          a.blue_line_key, a.downstream_route_measure,
          a.wscode_ltree, a.localcode_ltree,
          false, 1)
    )", model_tbl, model_tbl))
  n_post <- DBI::dbGetQuery(conn, sprintf("SELECT count(*) FROM %s", model_tbl))[[1]]
  message(sprintf("  %-20s: %s -> %s minimal", model_name, n_pre, n_post))
  all_minimal <- c(all_minimal, model_tbl)
}

# Union all per-model minimal positions into one table for segmentation
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.gradient_barriers_minimal")
union_sql <- paste(sprintf(
  "SELECT DISTINCT blue_line_key, downstream_route_measure FROM %s", all_minimal),
  collapse = " UNION ")
DBI::dbExecute(conn, sprintf(
  "CREATE TABLE working.gradient_barriers_minimal AS %s", union_sql))
n_union <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.gradient_barriers_minimal")[[1]]
message("  Union of minimal positions: ", n_union)

# ===========================================================================
# Step 6: Load base segments + sequential breaking
# ===========================================================================
message("\n=== Step 6: Sequential breaking ===")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams CASCADE")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams_habitat CASCADE")

# Load base segments with bcfishpass filters + optional AOI
aoi_filter <- if (!is.null(aoi)) paste0("\n    AND ", aoi) else ""
DBI::dbExecute(conn, sprintf("
  CREATE TABLE fresh.streams AS
  SELECT *
  FROM whse_basemapping.fwa_stream_networks_sp
  WHERE watershed_group_code = '%s'
    AND localcode_ltree IS NOT NULL
    AND edge_type != 6010
    AND wscode_ltree <@ '999'::ltree IS FALSE%s
", wsg, aoi_filter))
# Note: bcfishpass excludes LFIDs 832498864, 832474945 (bad data removed from FWA post-20240830)

# Channel width (same as frs_network_segment)
fresh::frs_col_join(conn, "fresh.streams",
  from = "fwa_stream_networks_channel_width",
  cols = c("channel_width", "channel_width_source"),
  by = "linear_feature_id")

# Stream order parent (for rearing channel width bypass)
fresh::frs_col_join(conn, "fresh.streams",
  from = "fwa_stream_networks_order_parent",
  cols = "stream_order_parent",
  by = "blue_line_key")

# GENERATED columns for gradient/measures/length
fresh::frs_col_generate(conn, "fresh.streams")

# Unique id_segment
DBI::dbExecute(conn, "ALTER TABLE fresh.streams ADD COLUMN id_segment integer")
DBI::dbExecute(conn, "
  WITH numbered AS (
    SELECT ctid, row_number() OVER (ORDER BY blue_line_key, downstream_route_measure) AS rn
    FROM fresh.streams
  )
  UPDATE fresh.streams s SET id_segment = numbered.rn
  FROM numbered WHERE s.ctid = numbered.ctid")
DBI::dbExecute(conn, "CREATE UNIQUE INDEX ON fresh.streams (id_segment)")

n_base <- DBI::dbGetQuery(conn, "SELECT count(*) FROM fresh.streams")[[1]]
message("  Base segments: ", n_base)

# Add gradient_NNNN label for access gating
DBI::dbExecute(conn, "ALTER TABLE working.gradient_barriers_raw ADD COLUMN IF NOT EXISTS label_access text")
DBI::dbExecute(conn, "UPDATE working.gradient_barriers_raw SET label_access = 'gradient_' || lpad(gradient_class::text, 4, '0')")

# Observation break positions — filter to species present in WSG + exclude data errors
obs_species <- toupper(spp_cols[vapply(spp_cols, function(x)
  identical(wsg_row[[x]], "t"), logical(1))])
if ("CT" %in% obs_species) obs_species <- c(obs_species, "CCT", "ACT", "CT/RB")
obs_species_sql <- paste0("'", obs_species, "'", collapse = ", ")

# Load observation exclusions (data errors + release excludes)
obs_excl <- read.csv(file.path(bcfishpass_data, "observation_exclusions.csv"),
  stringsAsFactors = FALSE)
obs_excl_keys <- obs_excl$fish_observation_point_id[
  obs_excl$data_error %in% c(TRUE, "t") | obs_excl$release_exclude %in% c(TRUE, "t")]
if (length(obs_excl_keys) > 0) {
  DBI::dbWriteTable(conn, DBI::Id(schema = "working", table = "obs_exclusions"),
    data.frame(fish_observation_point_id = obs_excl_keys), overwrite = TRUE)
  excl_filter <- "AND o.fish_observation_point_id NOT IN (SELECT fish_observation_point_id FROM working.obs_exclusions)"
} else {
  excl_filter <- ""
}

DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.observations_breaks")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.observations_breaks AS
  SELECT DISTINCT o.blue_line_key, round(o.downstream_route_measure) AS downstream_route_measure
  FROM bcfishobs.observations o
  WHERE o.watershed_group_code = '%s'
    AND o.species_code IN (%s) %s", wsg, obs_species_sql, excl_filter))
n_obs <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.observations_breaks")[[1]]
message("  Observation breaks: ", n_obs)

# Habitat classification endpoints — bcfishpass breaks at BOTH downstream AND
# upstream measures per record (user_habitat_classification_endpoints.sql)
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.habitat_endpoints")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE working.habitat_endpoints AS
  SELECT DISTINCT blue_line_key, round(downstream_route_measure) AS downstream_route_measure
  FROM working.user_habitat_classification
  WHERE watershed_group_code = '%s'
  UNION
  SELECT DISTINCT blue_line_key, round(upstream_route_measure) AS downstream_route_measure
  FROM working.user_habitat_classification
  WHERE watershed_group_code = '%s'", wsg, wsg))
n_hab <- DBI::dbGetQuery(conn, "SELECT count(*) FROM working.habitat_endpoints")[[1]]
message("  Habitat endpoints: ", n_hab)

# Crossings break positions
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.crossings_breaks")
DBI::dbExecute(conn, "
  CREATE TABLE working.crossings_breaks AS
  SELECT blue_line_key, round(downstream_route_measure) AS downstream_route_measure
  FROM working.crossings")

# Helper: reassign unique id_segment after each break round
reassign_id <- function(conn) {
  DBI::dbExecute(conn, "DROP INDEX IF EXISTS fresh.streams_id_segment_idx")
  DBI::dbExecute(conn, "
    WITH numbered AS (
      SELECT ctid, row_number() OVER (ORDER BY blue_line_key, downstream_route_measure) AS rn
      FROM fresh.streams
    )
    UPDATE fresh.streams s SET id_segment = numbered.rn
    FROM numbered WHERE s.ctid = numbered.ctid")
  DBI::dbExecute(conn, "CREATE UNIQUE INDEX streams_id_segment_idx ON fresh.streams (id_segment)")
}

# Sequential breaking — bcfishpass order
break_sources <- list(
  list(name = "observations",            table = "working.observations_breaks"),
  list(name = "gradient_barriers",       table = "working.gradient_barriers_minimal"),
  list(name = "barriers_definite",       table = "working.barriers_definite"),
  list(name = "habitat_endpoints",       table = "working.habitat_endpoints"),
  list(name = "crossings",              table = "working.crossings_breaks")
)

for (src in break_sources) {
  n_before <- DBI::dbGetQuery(conn, "SELECT count(*) FROM fresh.streams")[[1]]
  fresh::frs_break_apply(conn,
    table = "fresh.streams",
    breaks = src$table,
    segment_id = "id_segment",
    measure_precision = 0L)
  n_after <- DBI::dbGetQuery(conn, "SELECT count(*) FROM fresh.streams")[[1]]
  message(sprintf("  After %-25s: %s segments (+%s)", src$name, n_after, n_after - n_before))
  reassign_id(conn)
}

# Index streams table (frs_habitat_classify now auto-indexes in 0.13.4 but
# we also need indexes for the sequential breaking step)
fresh:::.frs_index_working(conn, "fresh.streams")

# Build breaks table for access gating (frs_habitat_classify needs this)
# Access gating needs ALL gradient barriers (not just minimal).
# Minimal is for segmentation only — every gradient still blocks access.
# Re-detect full set since gradient_barriers_raw was modified in-place.
fresh::frs_break_find(conn, "working.streams_blk",
  attribute = "gradient",
  classes = c("1500" = 0.15, "2000" = 0.20, "2500" = 0.25, "3000" = 0.30),
  to = "working.gradient_barriers_access")

# Filter breaks to WSG — access gating is O(segments × breaks), must be tight
DBI::dbExecute(conn, "DROP TABLE IF EXISTS fresh.streams_breaks")
DBI::dbExecute(conn, sprintf("
  CREATE TABLE fresh.streams_breaks AS
  SELECT g.blue_line_key, round(g.downstream_route_measure) AS downstream_route_measure,
    'gradient_' || lpad(g.gradient_class::text, 4, '0') AS label,
    s.wscode_ltree, s.localcode_ltree
  FROM working.gradient_barriers_access g
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON g.blue_line_key = s.blue_line_key
    AND g.downstream_route_measure >= s.downstream_route_measure
    AND g.downstream_route_measure < s.upstream_route_measure
  WHERE s.watershed_group_code = '%s'
  UNION ALL
  SELECT f.blue_line_key, round(f.downstream_route_measure), 'blocked',
    s.wscode_ltree, s.localcode_ltree
  FROM working.falls f
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON f.blue_line_key = s.blue_line_key
    AND f.downstream_route_measure >= s.downstream_route_measure
    AND f.downstream_route_measure < s.upstream_route_measure
  WHERE s.watershed_group_code = '%s'
  UNION ALL
  SELECT d.blue_line_key, round(d.downstream_route_measure), 'blocked',
    s.wscode_ltree, s.localcode_ltree
  FROM working.barriers_definite d
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON d.blue_line_key = s.blue_line_key
    AND d.downstream_route_measure >= s.downstream_route_measure
    AND d.downstream_route_measure < s.upstream_route_measure
  WHERE s.watershed_group_code = '%s'
  UNION ALL
  SELECT c.blue_line_key, round(c.downstream_route_measure),
    CASE c.barrier_status
      WHEN 'BARRIER' THEN 'barrier'
      WHEN 'POTENTIAL' THEN 'potential'
      WHEN 'PASSABLE' THEN 'passable'
      ELSE 'unknown'
    END,
    s.wscode_ltree, s.localcode_ltree
  FROM working.crossings c
  JOIN whse_basemapping.fwa_stream_networks_sp s
    ON c.blue_line_key = s.blue_line_key
    AND c.downstream_route_measure >= s.downstream_route_measure
    AND c.downstream_route_measure < s.upstream_route_measure
  WHERE s.watershed_group_code = '%s'", wsg, wsg, wsg, wsg))
# breaks table indexed automatically by frs_habitat_classify (fresh 0.13.4+)

# ===========================================================================
# Step 7: Classify habitat
# ===========================================================================
message("\n=== Step 7: Classify habitat ===")
t0 <- proc.time()
fresh::frs_habitat_classify(conn,
  table = "fresh.streams",
  to = "fresh.streams_habitat",
  species = species_compare,
  params = fresh::frs_params(
    csv = system.file("extdata", "parameters_habitat_thresholds.csv", package = "fresh"),
    rules_yaml = rules_path),
  params_fresh = params_fresh_df,
  gate = TRUE,
  label_block = "blocked",  # crossings need anthropogenic barrier overrides before they can block
  barrier_overrides = "working.barrier_overrides",
  verbose = TRUE)
elapsed <- (proc.time() - t0)["elapsed"]
message("  Classification completed in ", round(elapsed, 1), " seconds")

# Rearing-spawning connectivity (frs_cluster) — same as frs_habitat runs internally
params_obj <- fresh::frs_params(
  csv = system.file("extdata", "parameters_habitat_thresholds.csv", package = "fresh"),
  rules_yaml = rules_path)
fresh:::`.frs_run_connectivity`(conn,
  table = "fresh.streams",
  habitat = "fresh.streams_habitat",
  species = species_compare,
  params = params_obj,
  params_fresh = params_fresh_df,
  verbose = TRUE)

# ===========================================================================
# Step 8: Compare
# ===========================================================================
message("\n=== Step 8: Compare ===")

ours <- DBI::dbGetQuery(conn, sprintf("
  SELECT h.species_code,
    round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS spawning_km,
    round(SUM(CASE WHEN h.rearing THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS rearing_km
  FROM fresh.streams s JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  WHERE h.species_code IN (%s)
  GROUP BY h.species_code ORDER BY h.species_code",
  paste0("'", species_compare, "'", collapse = ", ")))

ref_aoi <- if (!is.null(aoi)) paste0(" AND ", gsub("wscode_ltree", "s.wscode_ltree", aoi)) else ""
ref_list <- lapply(species_compare, function(sp) {
  # Check if rearing column exists for this species (CM/PK have spawning only)
  ref_cols <- DBI::dbGetQuery(conn_ref, sprintf(
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'bcfishpass' AND table_name = 'habitat_linear_%s'", tolower(sp)))
  has_rearing <- "rearing" %in% ref_cols$column_name
  rear_expr <- if (has_rearing) "CASE WHEN h.rearing THEN s.length_metre ELSE 0 END" else "0"
  DBI::dbGetQuery(conn_ref, sprintf("
    SELECT '%s' AS species_code,
      round(SUM(CASE WHEN h.spawning THEN s.length_metre ELSE 0 END)::numeric / 1000, 2) AS spawning_km,
      round(SUM(%s)::numeric / 1000, 2) AS rearing_km
    FROM bcfishpass.streams s
    JOIN bcfishpass.habitat_linear_%s h ON s.segmented_stream_id = h.segmented_stream_id
    WHERE s.watershed_group_code = '%s'%s", sp, rear_expr, tolower(sp), wsg, ref_aoi))
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
elapsed_total <- round((proc.time() - t_start)["elapsed"], 1)
message("\nDone. Total: ", elapsed_total, " seconds")
