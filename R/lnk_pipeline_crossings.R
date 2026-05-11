#' Build crossings + barriers_* tables from primitives
#'
#' Composes the lean primitives-build for one AOI:
#'
#' 1. [lnk_inputs_verify()] — required source tables present (PSCIS, dams,
#'    modelled_stream_crossings already loaded by `data-raw/snapshot_bcfp.sh`).
#' 2. [lnk_points_snap()] — snap PSCIS assessments to FWA via lateral KNN.
#' 3. `.lnk_crossings_union()` — UNION ALL of PSCIS + CABD + modelled
#'    sources into `<schema>.crossings` (lean column set).
#' 4. `.lnk_crossings_apply_overrides()` — apply user_pscis_barrier_status
#'    + user_modelled_crossing_fixes from staging tables loaded by
#'    [lnk_pipeline_load()].
#' 5. [lnk_barriers_emit()] — emit `<schema>.crossings_lookup` + four
#'    `<schema>.barriers_*` tables (filtered SELECTs).
#'
#' Outputs feed `lnk_pipeline_access(barrier_sources = list(...))`.
#'
#' @param conn A DBI connection.
#' @param aoi Watershed group code, e.g. `"ADMS"`.
#' @param cfg An `lnk_config` object. Currently unused; reserved for
#'   future config-driven knobs (snap tolerance, edge-type exclusions).
#' @param loaded Named list from [lnk_load_overrides()]. Currently unused
#'   directly (overrides already staged by [lnk_pipeline_load()]); kept
#'   in the signature for pipeline consistency.
#' @param schema Working schema name (e.g. `"working_adms"`). Must be
#'   pre-created via [lnk_pipeline_setup()].
#' @param snap_tolerance Maximum PSCIS snap distance in metres. Default
#'   `100` (matches bcfp).
#' @param pscis_table Source table for PSCIS assessments. Default
#'   `"whse_fish.pscis_assessment_svw"` — the canonical BCDC view.
#' @param modelled_table Source table for modelled stream crossings.
#'   Default `"fresh.modelled_stream_crossings"` — populated by
#'   `data-raw/snapshot_bcfp.sh` (link#137). Province-wide; the AOI
#'   filter is applied during the union.
#' @param dams_table Source table for CABD dams. Default
#'   `paste0(schema, ".dams")` — produced per-AOI by
#'   [lnk_pipeline_prepare()].
#'
#' @return `invisible(conn)` for piping.
#'
#' @details
#' Required pre-loaded tables (verified by [lnk_inputs_verify()] up-front):
#' - `whse_fish.pscis_assessment_svw` — BCDC PSCIS via Python `bcdata bc2pg`.
#' - `<schema>.modelled_stream_crossings` — bchamp gpkg via curl + ogr2ogr.
#' - `<schema>.dams` — produced by [lnk_pipeline_prepare()] from CABD.
#'
#' All three are loaded by `data-raw/snapshot_bcfp.sh` (link#137) +
#' `lnk_pipeline_prepare()` for the `dams` step.
#'
#' Output tables:
#' - `<schema>.crossings` — lean union (id + source + statuses + network position + geom).
#' - `<schema>.crossings_lookup` — slim id + statuses projection.
#' - `<schema>.barriers_anthropogenic`, `<schema>.barriers_pscis`,
#'   `<schema>.barriers_dams`, `<schema>.barriers_remediations` — filtered
#'   SELECTs ready for `lnk_pipeline_access(barrier_sources = list(...))`.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' cfg <- lnk_config("default")
#' loaded <- lnk_load_overrides(cfg)
#'
#' lnk_pipeline_setup(conn, schema = "working_adms")
#' lnk_pipeline_load(conn, "ADMS", cfg, loaded, "working_adms")
#' lnk_pipeline_prepare(conn, "ADMS", cfg, loaded, "working_adms",
#'                      conn_tunnel = conn)  # cabd.dams loaded locally per #137
#' lnk_pipeline_crossings(conn, "ADMS", cfg, loaded, "working_adms")
#'
#' # Inspect.
#' DBI::dbReadTable(conn, c("working_adms", "crossings_lookup"))
#' DBI::dbReadTable(conn, c("working_adms", "barriers_anthropogenic"))
#' }
#'
#' @family pipeline
#' @seealso [lnk_inputs_verify()], [lnk_points_snap()], [lnk_barriers_emit()],
#'   [lnk_pipeline_access()]
#' @export
lnk_pipeline_crossings <- function(conn, aoi, cfg, loaded, schema,
                                   snap_tolerance = 100,
                                   pscis_table = "whse_fish.pscis_assessment_svw",
                                   modelled_table = "fresh.modelled_stream_crossings",
                                   dams_table = paste0(schema, ".dams")) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    is.numeric(snap_tolerance), length(snap_tolerance) == 1L,
    snap_tolerance > 0,
    is.character(pscis_table), length(pscis_table) == 1L, nzchar(pscis_table),
    is.character(modelled_table), length(modelled_table) == 1L, nzchar(modelled_table),
    is.character(dams_table), length(dams_table) == 1L, nzchar(dams_table)
  )

  # 1. Verify required source tables are present.
  lnk_inputs_verify(conn, c(pscis_table, modelled_table, dams_table)) # nolint: object_usage_linter

  # 2. Build <schema>.pscis via bcfp-shape snap + score + pick + xref chain.
  #    Mirrors bcfp's 02_pscis_streams_150m.sql + 04_pscis.sql at
  #    smnorris/bcfishpass@v0.7.14-125-g6e9cf1c. Output table provides
  #    every column the PSCIS branch of .lnk_crossings_union needs,
  #    plus modelled_crossing_id (which drives the modelled-branch
  #    xref exclusion downstream).
  .lnk_pipeline_pscis_build(  # nolint: object_usage_linter
    conn, aoi = aoi, schema = schema, loaded = loaded,
    pscis_table = pscis_table,
    modelled_table = modelled_table,
    snap_tolerance = max(snap_tolerance, 150)  # bcfp uses 150m
  )

  # 3. Union into <schema>.crossings (lean column set).
  .lnk_crossings_union(conn, schema, aoi,                # nolint: object_usage_linter
                       modelled_table = modelled_table,
                       dams_table = dams_table)

  # 4. Apply user_pscis_barrier_status + user_modelled_crossing_fixes
  #    from staging tables created by lnk_pipeline_load().
  .lnk_crossings_apply_overrides(conn, schema) # nolint: object_usage_linter

  # 5. Emit slim crossings_lookup + four barriers_* tables.
  lnk_barriers_emit(conn, schema) # nolint: object_usage_linter

  invisible(conn)
}
