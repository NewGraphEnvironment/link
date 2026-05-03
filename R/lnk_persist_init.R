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
  segmented_stream_id      = "text",
  linear_feature_id        = "bigint",
  edge_type                = "integer",
  blue_line_key            = "integer",
  watershed_key            = "integer",
  downstream_route_measure = "double precision",
  length_metre             = "double precision",
  waterbody_key            = "integer",
  wscode_ltree             = "ltree",
  localcode_ltree          = "ltree",
  gnis_name                = "varchar(80)",
  stream_order             = "integer",
  stream_magnitude         = "integer",
  gradient                 = "double precision",
  feature_code             = "varchar(10)",
  upstream_route_measure   = "double precision",
  upstream_area_ha         = "double precision",
  stream_order_parent      = "integer",
  stream_order_max         = "integer",
  channel_width            = "double precision",
  channel_width_source     = "varchar(40)",
  mad_m3s                  = "double precision",
  geom                     = "geometry(MultiLineString, 3005)"
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
#'
#' @return `conn` invisibly.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("bcfishpass")
#' loaded <- lnk_load_overrides(cfg)
#' species <- unique(loaded$parameters_fresh$species_code)
#' lnk_persist_init(conn, cfg, species)
#' }
#' @export
lnk_persist_init <- function(conn, cfg, species) {
  if (!inherits(cfg, "lnk_config")) {
    stop("cfg must be an lnk_config object", call. = FALSE)
  }
  if (!is.character(species) || length(species) == 0L) {
    stop("species must be a non-empty character vector", call. = FALSE)
  }
  if (any(!nzchar(species))) {
    stop("species must not contain empty strings", call. = FALSE)
  }

  tn <- .lnk_table_names(cfg)
  schema <- tn$schema
  pk <- c("id_segment", "watershed_group_code")

  .lnk_db_execute(conn, sprintf(
    "CREATE SCHEMA IF NOT EXISTS %s", schema))

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

  invisible(conn)
}
