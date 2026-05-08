#' Union PSCIS + CABD + modelled crossings into a slim crossings table
#'
#' Internal helper for [lnk_pipeline_crossings()]. Mirrors bcfp's
#' source-precedence merge from `model/01_access/sql/load_crossings.sql`
#' but emits ONLY the columns `lnk_barriers_emit()` consumes — drops road
#' tenure / FTEN / OGC / rail / UTM metadata that bcfp carries for other
#' downstream uses.
#'
#' Source-precedence: PSCIS > CABD > modelled. Modelled crossings whose
#' `modelled_crossing_id` appears in `<schema>.pscis_modelledcrossings_streams_xref`
#' (loaded by [lnk_pipeline_load()]) are excluded from the modelled
#' branch — they're already represented by their PSCIS counterpart.
#'
#' @param conn A DBI connection.
#' @param schema Working schema. Receives `<schema>.crossings` and reads
#'   `<schema>.pscis_assessment_snapped` (output of [lnk_points_snap()])
#'   plus optional `<schema>.pscis_modelledcrossings_streams_xref` (from
#'   [lnk_pipeline_load()] — treated as empty when absent).
#' @param aoi Watershed group code.
#' @param modelled_table Fully-qualified `<schema>.<table>` of the
#'   modelled stream crossings primitive. Default
#'   `"fresh.modelled_stream_crossings"`.
#' @param dams_table Fully-qualified `<schema>.<table>` of the per-AOI
#'   dams table from [lnk_pipeline_prepare()]. Default `<schema>.dams`.
#'
#' @return `invisible(NULL)`. Side effect: drops + recreates
#'   `<schema>.crossings` with the lean column set.
#'
#' @details
#' Output columns (lean — what `lnk_barriers_emit()` needs):
#' - `aggregated_crossings_id` (text PK)
#' - `crossing_source` ('PSCIS' | 'CABD' | 'MODELLED_CROSSINGS')
#' - `crossing_feature_type` (text — 'DAM' for CABD; NULL otherwise)
#' - `barrier_status` (text)
#' - `pscis_status` (text — PSCIS rows only)
#' - `dam_name` (text — CABD rows only)
#' - `linear_feature_id`, `blue_line_key`, `watershed_key`,
#'   `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`,
#'   `watershed_group_code`, `geom`
#'
#' ID-space arithmetic per bcfp:
#' - PSCIS: `stream_crossing_id::text` direct.
#' - CABD: `dam_id::text` direct (real CABD ID range, no overlap with PSCIS).
#' - Modelled: `(modelled_crossing_id + 1000000000)::text`.
#'
#' Skipped relative to bcfp's `load_crossings.sql`:
#' - Road tenure attributes (DRA, FTEN, OGC, rail).
#' - UTM coordinates.
#' - PSCIS road/stream/comment/score metadata.
#' - The CASE-cascade that fully populates `crossing_feature_type`. We use
#'   only the DAM-vs-other distinction (sufficient for `barriers_dams` filter).
#'
#' @keywords internal
#' @noRd
.lnk_crossings_union <- function(conn, schema, aoi,
                                 modelled_table = "fresh.modelled_stream_crossings",
                                 dams_table = paste0(schema, ".dams")) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.character(modelled_table), length(modelled_table) == 1L,
    is.character(dams_table), length(dams_table) == 1L
  )

  s <- DBI::dbQuoteIdentifier(conn, schema)
  aoi_q <- DBI::dbQuoteString(conn, aoi)

  # Detect whether the optional xref table is present. If absent, empty
  # set — modelled crossings aren't pre-excluded for PSCIS overlap, which
  # is fine for AOIs where lnk_pipeline_load hasn't staged the override.
  has_xref <- DBI::dbGetQuery(conn, sprintf(
    "SELECT EXISTS (
       SELECT 1 FROM information_schema.tables
       WHERE table_schema = %s
         AND table_name = 'pscis_modelledcrossings_streams_xref'
     ) AS present;",
    DBI::dbQuoteString(conn, schema)
  ))$present

  xref_clause <- if (isTRUE(has_xref)) {
    sprintf(
      "AND m.modelled_crossing_id NOT IN (
         SELECT modelled_crossing_id
         FROM %s.pscis_modelledcrossings_streams_xref
       )",
      s
    )
  } else {
    ""
  }

  sql <- sprintf("
    DROP TABLE IF EXISTS %s.crossings;
    CREATE TABLE %s.crossings AS

    -- PSCIS branch (highest precedence)
    SELECT
      p.stream_crossing_id::text  AS aggregated_crossings_id,
      'PSCIS'::text               AS crossing_source,
      NULL::text                  AS crossing_feature_type,
      p.current_barrier_result_code AS barrier_status,
      p.current_pscis_status      AS pscis_status,
      NULL::text                  AS dam_name,
      p.linear_feature_id,
      p.snapped_blue_line_key     AS blue_line_key,
      NULL::bigint                AS watershed_key,
      p.downstream_route_measure,
      p.wscode_ltree,
      p.localcode_ltree,
      %s::text                    AS watershed_group_code,
      p.geom_snapped              AS geom
    FROM %s.pscis_assessment_snapped p

    UNION ALL

    -- CABD branch (dams from lnk_pipeline_prepare's existing snap+filter)
    SELECT
      d.dam_id::text              AS aggregated_crossings_id,
      'CABD'::text                AS crossing_source,
      'DAM'::text                 AS crossing_feature_type,
      d.passability_status        AS barrier_status,
      NULL::text                  AS pscis_status,
      d.dam_name,
      d.linear_feature_id,
      d.blue_line_key,
      NULL::bigint                AS watershed_key,
      d.downstream_route_measure,
      d.wscode_ltree,
      d.localcode_ltree,
      d.watershed_group_code,
      d.geom
    FROM %s d
    WHERE d.watershed_group_code = %s

    UNION ALL

    -- Modelled branch (those NOT covered by PSCIS via the xref table)
    SELECT
      (m.modelled_crossing_id + 1000000000)::text AS aggregated_crossings_id,
      'MODELLED_CROSSINGS'::text  AS crossing_source,
      NULL::text                  AS crossing_feature_type,
      'POTENTIAL'::text           AS barrier_status,
      NULL::text                  AS pscis_status,
      NULL::text                  AS dam_name,
      m.linear_feature_id,
      m.blue_line_key,
      NULL::bigint                AS watershed_key,
      m.downstream_route_measure,
      m.wscode_ltree,
      m.localcode_ltree,
      m.watershed_group_code,
      m.geom
    FROM %s m
    WHERE m.watershed_group_code = %s
      %s;
    ",
    s, s,
    aoi_q,                       # PSCIS branch wsg
    s,                           # PSCIS table
    dams_table, aoi_q,           # CABD table + AOI filter
    modelled_table, aoi_q,       # Modelled table + AOI
    xref_clause                  # xref exclusion
  )

  DBI::dbExecute(conn, sql)
  invisible(NULL)
}
