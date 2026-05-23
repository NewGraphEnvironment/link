#' Column shape for the persistent province-wide tables.
#'
#' Single source of truth referenced by both `lnk_persist_init()` (DDL)
#' and `lnk_pipeline_persist()` (INSERT projection). Mirrors bcfp's
#' `bcfishpass.streams` + `bcfishpass.habitat_linear_<sp>` for query
#' familiarity, with link's `id_segment` joining `watershed_group_code`
#' as primary-key partner.
#'
#' Modify here to change shape — both DDL and INSERT pick up the change.
#' @noRd
cols_streams <- c(
  id_segment               = "integer NOT NULL",
  watershed_group_code     = "varchar(4) NOT NULL",
  linear_feature_id        = "bigint",
  edge_type                = "integer",
  blue_line_key            = "integer",
  watershed_key            = "integer",
  gnis_name                = "varchar(80)",
  stream_order             = "integer",
  stream_magnitude         = "integer",
  waterbody_key            = "integer",
  feature_code             = "varchar(10)",
  wscode_ltree             = "ltree",
  localcode_ltree          = "ltree",
  channel_width            = "double precision",
  channel_width_source     = "text",
  stream_order_parent      = "integer",
  gradient                 = "double precision",
  downstream_route_measure = "double precision",
  upstream_route_measure   = "double precision",
  length_metre             = "double precision",
  geom                     = "geometry(MultiLineStringZM, 3005)"
)

#' @noRd
cols_habitat <- c(
  id_segment           = "integer NOT NULL",
  watershed_group_code = "varchar(4) NOT NULL",
  accessible           = "boolean",
  spawning             = "boolean",
  rearing              = "boolean",
  lake_rearing         = "boolean",
  wetland_rearing      = "boolean"
)

#' Column shape for the per-segment per-species access table.
#'
#' Persist mirror of `lnk_pipeline_access()`'s scalar output projection.
#' Per-species columns generated dynamically at DDL/INSERT time from the
#' bundle's `species` arg — `has_barriers_<sp>_dnstr` (boolean) and
#' `access_<sp>` (integer code per `lnk_pipeline_access` doc:
#' -9=absent / 0=blocked / 1=modelled-accessible / 2=observed-upstream).
#' Array columns (`barriers_<sp>_dnstr`, `obsrvtn_species_codes_upstr`)
#' stay in-memory on the returned tibble; not persisted.
#'
#' See `R/lnk_pipeline_access.R` for the source projection. See link#187
#' for the persist-this-and-mapping_code design.
#' @noRd
cols_streams_access_base <- c(
  id_segment                = "integer NOT NULL",
  watershed_group_code      = "varchar(4) NOT NULL"
)
#' Per-source flag column generator for `streams_access` (link#196).
#'
#' Returns a named character vector keyed by column-name → DDL type for
#' the per-barrier-source downstream flags + the indicator columns.
#' These columns are consumed by `lnk_pipeline_mapping_code` for the
#' second-token classification (DAM / MODELLED / ASSESSED / REMEDIATED /
#' NONE). Without them persisted, `lnk_mapping_code` reads the persist
#' table and finds the flags absent → all second tokens default to
#' NONE (the v0.40.2 PARS BT bug).
#'
#' Hardcoded source classes (anthropogenic / pscis / dams /
#' remediations) match the keys `lnk_pipeline_run` passes as
#' `barrier_sources` to `lnk_pipeline_access`. Data-driving these per
#' bundle is link#197 territory.
#' @noRd
.lnk_cols_streams_access_source_flags <- function() {
  c(
    has_barriers_anthropogenic_dnstr = "boolean",
    has_barriers_pscis_dnstr         = "boolean",
    has_barriers_dams_dnstr          = "boolean",
    has_barriers_remediations_dnstr  = "boolean",
    dam_dnstr_ind                    = "boolean",
    remediated_dnstr_ind             = "boolean"
  )
}

# `has_observation_key_upstr` is observations-conditional; still
# omitted from the persist base shape until a consumer requires it.

#' Per-species column generator for `streams_access`.
#'
#' Returns a named character vector keyed by column-name → DDL type,
#' two columns per species (`has_barriers_<sp>_dnstr` boolean,
#' `access_<sp>` integer). Combined with `cols_streams_access_base` at
#' DDL/INSERT time.
#' @noRd
.lnk_cols_streams_access_per_sp <- function(species) {
  sp <- tolower(species)
  c(
    setNames(rep("boolean", length(sp)),
             paste0("has_barriers_", sp, "_dnstr")),
    setNames(rep("integer", length(sp)),
             paste0("access_", sp))
  )
}

#' Column shape for the per-segment per-species mapping_code table.
#'
#' Persist mirror of `lnk_pipeline_mapping_code()`'s output. Per-species
#' columns generated dynamically — `mapping_code_<sp>` text. QGIS bcfp-
#' shape symbology consumer (`data-raw/build_species_views.R --bcfp`).
#'
#' See `R/lnk_pipeline_mapping_code.R` for the source projection.
#' See link#187 for the persist-and-decouple design.
#' @noRd
cols_streams_mapping_code_base <- c(
  id_segment           = "integer NOT NULL",
  watershed_group_code = "varchar(4) NOT NULL"
)

#' Per-species column generator for `streams_mapping_code`.
#' @noRd
.lnk_cols_streams_mapping_code_per_sp <- function(species) {
  sp <- tolower(species)
  setNames(rep("text", length(sp)), paste0("mapping_code_", sp))
}

#' Column shape for the unified province-wide barriers table.
#'
#' `<persist_schema>.barriers` holds all access-time barriers across all
#' source families with a pre-computed `blocks_species text[]` predicate.
#' Cross-WSG dnstr lookups in [lnk_pipeline_access()] resolve correctly
#' regardless of which WSG a barrier physically lives in — fixes the
#' PARS BT 60% defect (PARS drains through dams in PCEA / UPCE WSGs)
#' and unblocks any regional run that crosses WSG boundaries.
#'
#' See link#152.
#' @noRd
cols_barriers <- c(
  id_barrier               = "text NOT NULL",
  watershed_group_code     = "varchar(4) NOT NULL",
  barrier_source           = "varchar(20) NOT NULL",
  barrier_subtype          = "varchar(50)",
  passability              = "varchar(20)",
  blocks_species           = "text[]",
  linear_feature_id        = "bigint",
  blue_line_key            = "integer",
  watershed_key            = "integer",
  downstream_route_measure = "double precision",
  wscode_ltree             = "ltree",
  localcode_ltree          = "ltree",
  geom                     = "geometry(Point, 3005)"
)

#' Column shape for the province-wide barrier-overrides table.
#'
#' `<persist_schema>.barrier_overrides` holds the per-(segment x species)
#' observation/habitat barrier-skip list (`lnk_barrier_overrides` output)
#' accumulated across all WSGs. Persisted province-wide so the per-species
#' access view (`barriers_<sp>_access`, [lnk_barriers_views()]) can
#' anti-join it for natural barriers in ANY WSG a downstream walk crosses —
#' the cross-WSG twin of the link#152 barriers fix. One named vector drives
#' both the DDL ([lnk_persist_init()]) and the INSERT projection
#' ([lnk_pipeline_persist()]). link#200.
#' @noRd
cols_barrier_overrides <- c(
  blue_line_key            = "integer NOT NULL",
  downstream_route_measure = "double precision NOT NULL",
  species_code             = "text NOT NULL",
  watershed_group_code     = "varchar(4) NOT NULL"
)

#' Validate that an existing target table doesn't carry stale DDL
#' (unexpected `GENERATED ALWAYS` columns).
#'
#' `lnk_persist_init` uses `CREATE TABLE IF NOT EXISTS` — idempotent
#' but oblivious to DDL drift. When a host's fwapg volume carries a
#' table whose schema differs from what we expect (e.g. cypher snapshots
#' baked when `fresh::frs_col_generate()` had been run on `fresh.streams`,
#' leaving `gradient` as `GENERATED ALWAYS`), the CREATE is a no-op,
#' the stale DDL survives, and `lnk_pipeline_persist`'s INSERT fails
#' downstream with `cannot insert a non-DEFAULT value into column ...`.
#'
#' This helper detects that case at init time:
#' - Table doesn't exist: no-op (CREATE IF NOT EXISTS will handle it).
#' - Table exists with no unexpected GENERATED columns: no-op.
#' - Table exists with unexpected GENERATED columns + `force_recreate = FALSE`:
#'   stop with a clear error pointing at the offending columns + how to fix.
#' - Table exists with unexpected GENERATED columns + `force_recreate = TRUE`:
#'   DROP CASCADE so the subsequent CREATE re-runs with the correct DDL.
#'
#' @noRd
.lnk_validate_persist_table <- function(conn, schema, table, force_recreate) {
  # Does the table exist?
  exists_row <- DBI::dbGetQuery(conn, sprintf(
    "SELECT 1 FROM information_schema.tables
     WHERE table_schema = '%s' AND table_name = '%s'",
    schema, table))
  if (nrow(exists_row) == 0L) return(invisible())

  # Any GENERATED columns? lnk_persist_init's target tables don't use
  # GENERATED — any present is a drift signal worth surfacing.
  gen_rows <- DBI::dbGetQuery(conn, sprintf(
    "SELECT column_name
     FROM information_schema.columns
     WHERE table_schema = '%s' AND table_name = '%s'
       AND is_generated = 'ALWAYS'",
    schema, table))
  if (nrow(gen_rows) == 0L) return(invisible())

  unexpected <- gen_rows$column_name
  if (isTRUE(force_recreate)) {
    message(sprintf(
      "[lnk_persist_init] %s.%s has unexpected GENERATED columns (%s); DROPping per force_recreate=TRUE",
      schema, table, paste(unexpected, collapse = ",")))
    .lnk_db_execute(conn, sprintf(
      "DROP TABLE %s.%s CASCADE", schema, table))
    return(invisible())
  }

  stop(sprintf(
    "DDL drift in %s.%s: %d GENERATED ALWAYS column(s) found (%s) that lnk_persist_init does not expect.\n",
    schema, table, length(unexpected), paste(unexpected, collapse = ", ")),
    "Subsequent lnk_pipeline_persist INSERTs would fail with ",
    "'cannot insert a non-DEFAULT value into column ...'.\n",
    "This commonly affects droplets spun from snapshots whose ",
    "`fresh.streams` was baked after `fresh::frs_col_generate()` ran on ",
    "it. Fix one of two ways:\n",
    "  - lnk_persist_init(conn, cfg, species, force_recreate = TRUE) ",
    "to DROP+recreate the offending table(s) with correct DDL\n",
    "  - or manually: DROP TABLE ", schema, ".", table, " CASCADE",
    call. = FALSE)
}


#' Build a CREATE TABLE column-list clause from a `cols_*` vector.
#'
#' Returns the inner body — caller wraps with `CREATE TABLE … (…)`.
#' @noRd
.lnk_cols_clause <- function(cols, pk) {
  defs <- paste(names(cols), unname(cols), sep = " ")
  body <- paste(defs, collapse = ",\n  ")
  paste0(body, ",\n  PRIMARY KEY (", paste(pk, collapse = ", "), ")")
}


#' Initialize persistent province-wide habitat tables
#'
#' Creates `<schema>.streams` and `<schema>.streams_habitat_<sp>` (one
#' per species) with `IF NOT EXISTS`. Idempotent — safe to call before
#' every per-WSG run, and safe under concurrent first-time provisioning
#' (multiple workers can race; only one CREATE wins).
#'
#' Per-WSG data accumulates into these tables via [lnk_pipeline_persist()]
#' after each run. Queryable cross-WSG for cartography, intrinsic
#' potential maps, and per-crossing upstream rollups.
#'
#' Column shape mirrors bcfp's `bcfishpass.streams` +
#' `bcfishpass.habitat_linear_<sp>` for familiarity. Driven by the
#' `cols_streams` / `cols_habitat` vectors at the top of this file —
#' single source of truth shared with [lnk_pipeline_persist()].
#'
#' @param conn DBI connection.
#' @param cfg An `lnk_config` object with `cfg$pipeline$schema` set.
#' @param species Character vector of species codes (uppercased) to
#'   create `streams_habitat_<sp>` tables for. Typically derived via
#'   [lnk_pipeline_species()] or `unique(loaded$parameters_fresh$species_code)`.
#' @param force_recreate Logical. When `TRUE`, drop any existing target
#'   tables whose DDL doesn't match the expected shape — specifically,
#'   tables that have unexpected `GENERATED ALWAYS` columns. Default
#'   `FALSE` errors loud instead so the operator can audit before the
#'   destructive recreate. Use when spinning a new host from a snapshot
#'   whose fwapg volume carries stale `fresh.streams` DDL (e.g. cypher
#'   snapshots baked when `frs_col_generate()` had been run on the
#'   persist schema). See link#162 Phase 7 hardening.
#'
#' @return `conn` invisibly.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' species <- unique(loaded$parameters_fresh$species_code)
#'
#' # First-time setup or healthy state: idempotent CREATE IF NOT EXISTS.
#' lnk_persist_init(conn, cfg, species)
#'
#' # If a snapshot-baked DB has stale GENERATED columns on fresh.streams:
#' lnk_persist_init(conn, cfg, species, force_recreate = TRUE)
#' }
#' @export
lnk_persist_init <- function(conn, cfg, species, force_recreate = FALSE) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object", call. = FALSE)
  }
  if (!is.character(species) || length(species) == 0L) {
    stop("species must be a non-empty character vector", call. = FALSE)
  }
  if (any(!nzchar(species))) {
    stop("species must not contain empty strings", call. = FALSE)
  }
  if (!is.logical(force_recreate) || length(force_recreate) != 1L) {
    stop("force_recreate must be a single logical", call. = FALSE)
  }

  tn <- .lnk_table_names(cfg)
  schema <- tn$schema
  pk <- c("id_segment", "watershed_group_code")

  .lnk_db_execute(conn, sprintf(
    "CREATE SCHEMA IF NOT EXISTS %s", schema))

  # DDL drift check BEFORE CREATE IF NOT EXISTS. `CREATE TABLE IF NOT
  # EXISTS` is a no-op when the table exists — even if the existing
  # DDL is wrong. That hides snapshot drift (e.g. cypher's `fresh.streams`
  # baked with `gradient` as GENERATED ALWAYS) until INSERT fails 80 min
  # later. Validate explicitly:
  .lnk_validate_persist_table(conn, schema = schema, table = "streams",
                              force_recreate = force_recreate)
  for (sp in species) {
    .lnk_validate_persist_table(conn, schema = schema,
                                table = paste0("streams_habitat_", tolower(sp)),
                                force_recreate = force_recreate)
  }
  .lnk_validate_persist_table(conn, schema = schema, table = "barriers",
                              force_recreate = force_recreate)
  .lnk_validate_persist_table(conn, schema = schema, table = "barrier_overrides",
                              force_recreate = force_recreate)
  .lnk_validate_persist_table(conn, schema = schema, table = "streams_access",
                              force_recreate = force_recreate)
  .lnk_validate_persist_table(conn, schema = schema,
                              table = "streams_mapping_code",
                              force_recreate = force_recreate)

  # Persistent streams.
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s.streams (\n  %s\n)",
    schema, .lnk_cols_clause(cols_streams, pk)))

  # Indexes for the dominant access patterns: WSG-scan filtering,
  # blue_line_key joins, spatial queries, lake/wetland joins.
  idx_specs <- list(
    streams_wsg_idx  = "(watershed_group_code)",
    streams_blk_idx  = "(blue_line_key)",
    streams_geom_idx = "USING GIST (geom)",
    streams_wbk_idx  = "(waterbody_key)"
  )
  for (idx_name in names(idx_specs)) {
    .lnk_db_execute(conn, sprintf(
      "CREATE INDEX IF NOT EXISTS %s ON %s.streams %s",
      idx_name, schema, idx_specs[[idx_name]]))
  }

  # Per-species habitat tables (wide-per-species, bcfp pattern).
  for (sp in species) {
    sp_table <- tn$habitat_for(sp)
    .lnk_db_execute(conn, sprintf(
      "CREATE TABLE IF NOT EXISTS %s (\n  %s\n)",
      sp_table, .lnk_cols_clause(cols_habitat, pk)))
    .lnk_db_execute(conn, sprintf(
      "CREATE INDEX IF NOT EXISTS streams_habitat_%s_wsg_idx ON %s (watershed_group_code)",
      tolower(sp), sp_table))
  }

  # Unified province-wide barriers table (link#152). Primary key on
  # (id_barrier, watershed_group_code) — `id_barrier` is namespaced per
  # source-family inside lnk_barriers_unify so it stays unique across
  # rows in a WSG.
  barriers_pk <- c("id_barrier", "watershed_group_code")
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s.barriers (\n  %s\n)",
    schema, .lnk_cols_clause(cols_barriers, barriers_pk)))

  # Indexes for the dominant access patterns:
  # - WSG-scan filtering (per-WSG runs DELETE then INSERT here).
  # - blocks_species @> ARRAY['BT'] (per-species access queries).
  # - barrier_source filtering (anthropogenic / dams / remediations
  #   source-typed dnstr arrays in lnk_pipeline_access).
  # - blue_line_key + downstream_route_measure (FWA topology walks
  #   inside fresh::frs_network_features).
  # - geom (spatial visualization).
  barriers_idx_specs <- list(
    barriers_wsg_idx        = "(watershed_group_code)",
    barriers_blocks_idx     = "USING GIN (blocks_species)",
    barriers_source_idx     = "(barrier_source)",
    barriers_blk_drm_idx    = "(blue_line_key, downstream_route_measure)",
    barriers_geom_idx       = "USING GIST (geom)"
  )
  for (idx_name in names(barriers_idx_specs)) {
    .lnk_db_execute(conn, sprintf(
      "CREATE INDEX IF NOT EXISTS %s ON %s.barriers %s",
      idx_name, schema, barriers_idx_specs[[idx_name]]))
  }

  # Province-wide barrier-overrides table (link#200). The per-(segment x
  # species) observation/habitat barrier-skip list, accumulated per-WSG so
  # the per-species access view can anti-join it cross-WSG. PK includes
  # watershed_group_code (mirrors cols_barriers' (id_barrier, wsg) PK):
  # the SAME override position can be computed by two adjacent WSG runs
  # (boundary streams whose blue_line_key spans WSGs), so (blk, drm,
  # species) is NOT unique across WSGs. Per-WSG DELETE-WHERE-WSG + INSERT
  # stays clean; the access anti-join is WSG-agnostic so duplicates are
  # harmless.
  barrier_overrides_pk <- c("blue_line_key", "downstream_route_measure",
                            "species_code", "watershed_group_code")
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s.barrier_overrides (\n  %s\n)",
    schema, .lnk_cols_clause(cols_barrier_overrides, barrier_overrides_pk)))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS barrier_overrides_wsg_idx ON %s.barrier_overrides (watershed_group_code)",
    schema))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS barrier_overrides_blk_drm_idx ON %s.barrier_overrides (blue_line_key, downstream_route_measure)",
    schema))

  # Per-segment per-species access table (link#187). Wide shape (one
  # row per segment, all species columns inline) — matches the QGIS-
  # consumer expectation + bcfp's `bcfishpass.streams_access` shape.
  # Generated DDL: base cols + dynamic per-species (has_barriers + access).
  cols_streams_access <- c(cols_streams_access_base,
                           .lnk_cols_streams_access_source_flags(),
                           .lnk_cols_streams_access_per_sp(species))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s.streams_access (\n  %s\n)",
    schema, .lnk_cols_clause(cols_streams_access, pk)))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS streams_access_wsg_idx ON %s.streams_access (watershed_group_code)",
    schema))

  # Per-segment per-species mapping_code table (link#187). Same wide
  # shape. Consumed by `data-raw/build_species_views.R --bcfp` to build
  # `streams_<sp>_bcfp_vw` views for QGIS symbology.
  cols_streams_mapping_code <- c(cols_streams_mapping_code_base,
                                 .lnk_cols_streams_mapping_code_per_sp(species))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE IF NOT EXISTS %s.streams_mapping_code (\n  %s\n)",
    schema, .lnk_cols_clause(cols_streams_mapping_code, pk)))
  .lnk_db_execute(conn, sprintf(
    "CREATE INDEX IF NOT EXISTS streams_mapping_code_wsg_idx ON %s.streams_mapping_code (watershed_group_code)",
    schema))

  # Long-form habitat view (link#187). UNION ALL across per-species
  # `streams_habitat_<sp>` tables — emits (id_segment, watershed_group_code,
  # species_code, spawning, rearing) for any consumer that prefers long
  # form (e.g. `lnk_mapping_code()` queries this shape). VIEW not table:
  # the data already lives in the per-species split; materializing would
  # 100% duplicate.
  view_unions <- vapply(species, function(sp) sprintf(
    "SELECT id_segment, watershed_group_code, '%s'::text AS species_code, spawning, rearing FROM %s.streams_habitat_%s",
    tolower(sp), schema, tolower(sp)),
    character(1))
  .lnk_db_execute(conn, sprintf(
    "CREATE OR REPLACE VIEW %s.streams_habitat_long_vw AS\n%s",
    schema, paste(view_unions, collapse = "\nUNION ALL\n")))

  invisible(conn)
}
