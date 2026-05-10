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

  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s.crossings;", s))

  sql <- sprintf("
    CREATE TABLE %s.crossings AS

    -- PSCIS branch (highest precedence). Joins fwa_stream_networks_sp
    -- on linear_feature_id to recover watershed_key + watershed_group_code
    -- (PSCIS BCDC tables don't carry watershed_group_code natively; derived
    -- post-snap via the FWA join). Filtering to AOI is also done here.
    SELECT
      p.stream_crossing_id::text  AS aggregated_crossings_id,
      'PSCIS'::text               AS crossing_source,
      NULL::text                  AS crossing_feature_type,
      p.current_barrier_result_code AS barrier_status,
      p.current_pscis_status      AS pscis_status,
      NULL::text                  AS dam_name,
      p.linear_feature_id,
      p.snapped_blue_line_key     AS blue_line_key,
      fwa_p.watershed_key         AS watershed_key,
      p.downstream_route_measure,
      p.wscode_ltree,
      p.localcode_ltree,
      fwa_p.watershed_group_code  AS watershed_group_code,
      p.geom_snapped              AS geom
    FROM %s.pscis_assessment_snapped p
    INNER JOIN whse_basemapping.fwa_stream_networks_sp fwa_p
      ON p.linear_feature_id = fwa_p.linear_feature_id
    WHERE fwa_p.watershed_group_code = %s

    UNION ALL

    -- CABD branch (dams from lnk_pipeline_prepare's existing snap+filter).
    -- CASE on passability_status_code mirrors bcfp's load_crossings.sql:
    -- normalises CABD's integer code into the bcfp barrier_status text vocab
    -- ('BARRIER' / 'POTENTIAL' / 'PASSABLE' / 'UNKNOWN'), shared across all
    -- crossing sources. The union is the convergence point for heterogeneous
    -- source vocabularies; cabd.dams stays raw upstream (and <schema>.dams
    -- carries only the integer code, matching bcfp's <schema>.dams shape).
    SELECT
      d.dam_id::text              AS aggregated_crossings_id,
      'CABD'::text                AS crossing_source,
      'DAM'::text                 AS crossing_feature_type,
      CASE
        WHEN d.passability_status_code = 1 THEN 'BARRIER'
        WHEN d.passability_status_code = 2 THEN 'POTENTIAL'
        WHEN d.passability_status_code = 3 THEN 'PASSABLE'
        WHEN d.passability_status_code = 4 THEN 'UNKNOWN'
        WHEN d.passability_status_code = 5 THEN 'PASSABLE'
        WHEN d.passability_status_code = 6 THEN 'PASSABLE'
      END                         AS barrier_status,
      NULL::text                  AS pscis_status,
      d.dam_name_en               AS dam_name,
      d.linear_feature_id,
      d.blue_line_key,
      fwa_d.watershed_key         AS watershed_key,
      d.downstream_route_measure,
      d.wscode_ltree,
      d.localcode_ltree,
      d.watershed_group_code,
      d.geom
    -- INNER JOIN to FWA: a LEFT JOIN here would NULL watershed_key on
    -- missing linear_feature_id, then barriers_emit silently drops the
    -- row downstream via `blue_line_key = watershed_key`. INNER JOIN
    -- drops at the union step instead, so the row-count discrepancy is
    -- observable here and not buried in barriers output.
    FROM %s d
    INNER JOIN whse_basemapping.fwa_stream_networks_sp fwa_d
      ON d.linear_feature_id = fwa_d.linear_feature_id
    WHERE d.watershed_group_code = %s

    UNION ALL

    -- Modelled branch (those NOT covered by PSCIS via the xref table).
    -- Cast wscode_ltree / localcode_ltree to ltree -- bchamp gpkg
    -- imports them as varchar but the canonical FWA type is ltree.
    -- modelled_crossing_id is int4 in bchamp; cast to bigint before
    -- adding 1e9 so 1.15B+ values can't overflow.
    --
    -- barrier_status from modelled_crossing_type (mirrors bcfp's
    -- load_crossings.sql): CBS = closed-bottom (culvert) -> POTENTIAL;
    -- OBS = open-bottom (bridge) -> PASSABLE. User-fix flips
    -- (structure IN ('NONE','OBS')) layer on top via
    -- .lnk_crossings_apply_overrides.
    SELECT
      (m.modelled_crossing_id::bigint + 1000000000)::text AS aggregated_crossings_id,
      'MODELLED_CROSSINGS'::text  AS crossing_source,
      NULL::text                  AS crossing_feature_type,
      CASE
        WHEN m.modelled_crossing_type = 'OBS' THEN 'PASSABLE'
        ELSE 'POTENTIAL'
      END                         AS barrier_status,
      NULL::text                  AS pscis_status,
      NULL::text                  AS dam_name,
      m.linear_feature_id,
      m.blue_line_key,
      fwa_m.watershed_key         AS watershed_key,
      m.downstream_route_measure,
      m.wscode_ltree::ltree       AS wscode_ltree,
      m.localcode_ltree::ltree    AS localcode_ltree,
      m.watershed_group_code,
      m.geom
    -- INNER JOIN to FWA: same rationale as the CABD branch.
    FROM %s m
    INNER JOIN whse_basemapping.fwa_stream_networks_sp fwa_m
      ON m.linear_feature_id = fwa_m.linear_feature_id
    WHERE m.watershed_group_code = %s
      %s;
    ",
    s,                           # CREATE TABLE %s.crossings AS
    s, aoi_q,                    # PSCIS FROM <schema>.pscis_..._snapped + AOI WHERE
    dams_table, aoi_q,           # CABD FROM + AOI WHERE
    modelled_table, aoi_q,       # Modelled FROM + AOI WHERE
    xref_clause                  # xref exclusion clause
  )

  DBI::dbExecute(conn, sql)
  invisible(NULL)
}
