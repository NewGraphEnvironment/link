#' Build per-AOI `<schema>.pscis` via bcfp-shape snap + score + pick + xref
#'
#' Internal helper for [lnk_pipeline_crossings()]. Reproduces bcfp's
#' `02_pscis_streams_150m.sql` + `04_pscis.sql` (at
#' `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`) via a 5-step composition:
#'
#' 1. Multi-stream snap — [lnk_points_snap()] with `num_features > 1`
#'    produces all candidate FWA streams within `snap_tolerance` per
#'    PSCIS point.
#' 2. Enrich + score — JOIN with PSCIS attrs (stream_name, channel_width,
#'    crossing_type_code) + FWA attrs (gnis_name, stream_order,
#'    waterbody_key) + LEFT JOIN to `fresh.modelled_stream_crossings` on
#'    same blue_line_key + ABS(drm) < 100. Compute `name_score`,
#'    `width_order_score` (verbatim from bcfp), `modelled_xing_dist`
#'    (planar Euclidean), `modelled_xing_dist_instream`.
#' 3. B-side dedup — UPDATE non-winning rows' `modelled_crossing_id` to
#'    NULL when multiple PSCIS candidates map to the same modelled
#'    (mirrors bcfp's WITH dups/to_retain/to_update UPDATE). Set
#'    `multiple_match_ind = TRUE` for losers; reset to NULL when
#'    `distance_to_stream < 50` (bcfp's "close enough" override).
#' 4. Per-PSCIS pick — [fresh::frs_candidates_pick()] with bcfp's exact
#'    filter (`name_score != -100 AND width_order_score != -100 AND
#'    multiple_match_ind IS NULL`) and ORDER BY (`name_score DESC,
#'    weighted_distance ASC`).
#' 5. Apply xref overrides — UPDATE `modelled_crossing_id` /
#'    `linear_feature_id` from `<schema>.pscis_modelledcrossings_streams_xref`
#'    where the xref CSV defines manual matches. INSERT xref-only PSCIS
#'    rows that the snap missed entirely (xref `modelled_crossing_id IS
#'    NULL` rows force-add the PSCIS to the output even when snap rejected
#'    them).
#'
#' Output table `<schema>.pscis` mirrors `bcfishpass.pscis` columns:
#' `stream_crossing_id, modelled_crossing_id, current_barrier_result_code,
#' current_pscis_status, linear_feature_id, snapped_blue_line_key,
#' downstream_route_measure, wscode_ltree, localcode_ltree,
#' watershed_group_code, geom_snapped`. Consumed downstream by
#' `.lnk_crossings_union` (PSCIS branch + modelled-branch xref exclusion).
#'
#' @param conn A DBI connection.
#' @param aoi Watershed group code (e.g. `"ADMS"`).
#' @param schema Working schema name (must exist + have
#'   `<schema>.pscis_modelledcrossings_streams_xref` staged by
#'   `lnk_pipeline_load()` for Step 5).
#' @param pscis_table Source PSCIS table. Default
#'   `"whse_fish.pscis_assessment_svw"`.
#' @param modelled_table Source modelled crossings table. Default
#'   `"fresh.modelled_stream_crossings"`.
#' @param snap_tolerance Maximum snap distance (m). Default `150` to
#'   match bcfp's `pscis_streams_150m` 150m tolerance.
#' @param snap_num_features Number of candidate streams per PSCIS point.
#'   Default `5L`. Higher catches more candidates at the cost of
#'   slightly bigger intermediate table.
#'
#' @return `invisible(conn)`. Side effect: creates `<schema>.pscis`,
#'   leaves `<schema>.pscis_stream_candidates` and
#'   `<schema>.pscis_streams_150m` as intermediate artifacts (dropped
#'   when working schema is cleaned up).
#'
#' @family pipeline
#' @noRd
.lnk_pipeline_pscis_build <- function(conn, aoi, schema, loaded = NULL,
                                      pscis_table = "whse_fish.pscis_assessment_svw",
                                      modelled_table = "fresh.modelled_stream_crossings",
                                      snap_tolerance = 150,
                                      snap_num_features = 5L) {
  stopifnot(
    inherits(conn, "DBIConnection"),
    is.character(aoi), length(aoi) == 1L, nzchar(aoi),
    is.character(schema), length(schema) == 1L, nzchar(schema),
    is.null(loaded) || is.list(loaded),
    is.numeric(snap_tolerance), length(snap_tolerance) == 1L,
    snap_tolerance > 0,
    is.numeric(snap_num_features), length(snap_num_features) == 1L,
    snap_num_features >= 1
  )

  # Stage pscis_modelledcrossings_streams_xref from `loaded` into the
  # working schema if available. lnk_pipeline_load doesn't currently
  # stage this CSV (only pscis_fixes, crossing_fixes, etc.); we own
  # the staging here so Step 5 has the table to UPDATE from.
  if (!is.null(loaded) && !is.null(loaded$pscis_modelledcrossings_streams_xref)) {
    xref_df <- loaded$pscis_modelledcrossings_streams_xref
    .lnk_db_execute(conn, sprintf(
      "DROP TABLE IF EXISTS %s.pscis_modelledcrossings_streams_xref;",
      schema
    ))
    DBI::dbWriteTable(
      conn,
      DBI::Id(schema = schema, table = "pscis_modelledcrossings_streams_xref"),
      xref_df,
      overwrite = TRUE
    )
  }

  s <- schema  # short alias for sprintf

  # =====================================================================
  # Step 1: multi-stream snap
  # =====================================================================
  # lnk_points_snap with num_features > 1 returns one row per (PSCIS,
  # candidate-stream) pair. Output columns: pts.* + linear_feature_id,
  # snapped_blue_line_key, downstream_route_measure, wscode_ltree,
  # localcode_ltree, distance_to_stream, geom_snapped.
  lnk_points_snap(  # nolint: object_usage_linter
    conn,
    table_in       = pscis_table,
    table_out      = paste0(s, ".pscis_stream_candidates"),
    snap_tolerance = snap_tolerance,
    num_features   = as.integer(snap_num_features)
  )

  # =====================================================================
  # Step 2: build pscis_streams_150m (enrich + score)
  # =====================================================================
  # Mirrors bcfp's 02_pscis_streams_150m.sql lines 60-160 — JOINs to
  # PSCIS attrs, FWA attrs, rivers polygon (for waterbody_key NOT NULL
  # check in width_order_score), and LEFT JOIN to modelled crossings
  # for the inline modelled-distance computation. Filters to AOI here.
  #
  # name_score CASE quoted verbatim from bcfp 02_pscis_streams_150m.sql
  # lines 101-105 — includes CR. -> CREEK abbreviation normalization +
  # TRIB-exclusion. width_order_score CASE quoted verbatim from lines
  # 115-142.
  .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s.pscis_streams_150m;", s))
  sql_streams_150m <- sprintf("
    CREATE TABLE %1$s.pscis_streams_150m AS
    SELECT
      c.stream_crossing_id,
      c.linear_feature_id,
      c.snapped_blue_line_key AS blue_line_key,
      c.downstream_route_measure,
      c.distance_to_stream,
      c.wscode_ltree,
      c.localcode_ltree,
      c.geom_snapped,
      a.stream_name,
      a.downstream_channel_width,
      a.current_crossing_type_code AS crossing_type_code,
      a.current_barrier_result_code,
      a.current_pscis_status,
      str.gnis_name,
      str.stream_order,
      str.waterbody_key,
      str.watershed_group_code,
      m.modelled_crossing_id,
      m.modelled_crossing_type,
      COALESCE(ST_Distance(c.geom_snapped, m.geom), 0) AS modelled_xing_dist,
      ABS(c.downstream_route_measure - m.downstream_route_measure)
        AS modelled_xing_dist_instream,
      -- name_score: stream-name match scoring per bcfp 02_pscis_streams_150m.sql L101-105.
      -- Note: bcfp's TRIB-exclusion clause uses `e.name_trimmed` (derived from gnis_name
      -- with suffix stripping). We use UPPER(gnis_name) directly — the TRIB clause is
      -- only triggered when PSCIS stream_name contains 'TRIB', not symmetric, so the
      -- effect is identical for the common case.
      CASE
        WHEN replace(UPPER(a.stream_name), ' CR.', ' CREEK') = UPPER(str.gnis_name)
          THEN 100
        WHEN UPPER(a.stream_name) LIKE '%%TRIB%%'
          AND UPPER(a.stream_name) LIKE '%%' || UPPER(str.gnis_name) || '%%'
          AND UPPER(a.stream_name) != UPPER(str.gnis_name)
          AND c.distance_to_stream > 15
          THEN -100
        ELSE 0
      END AS name_score,
      -- width_order_score: channel-width / stream-order compatibility per bcfp L115-142.
      CASE
        WHEN c.distance_to_stream > 25 AND str.stream_order = 1 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width >= 5 AND a.downstream_channel_width < 10 THEN -25
        WHEN c.distance_to_stream > 25 AND str.stream_order = 1 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width >= 10 THEN -100
        WHEN c.distance_to_stream > 25 AND str.stream_order = 2 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width > 7 AND a.downstream_channel_width < 15 THEN -25
        WHEN c.distance_to_stream > 25 AND str.stream_order = 2 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width >= 15 THEN -100
        WHEN c.distance_to_stream > 25 AND str.stream_order = 3 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width >= 20 THEN -25
        WHEN c.distance_to_stream > 25 AND str.stream_order = 4 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width < 1 THEN -100
        WHEN str.stream_order = 4 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width >= 1 AND a.downstream_channel_width < 2 THEN -25
        WHEN c.distance_to_stream > 25 AND str.stream_order = 5 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width < 2 THEN -100
        WHEN c.distance_to_stream > 25 AND str.stream_order = 5 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width >= 2 AND a.downstream_channel_width < 5 THEN -25
        WHEN c.distance_to_stream > 25 AND str.stream_order >= 6 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width < 2 THEN -100
        WHEN c.distance_to_stream > 25 AND str.stream_order >= 6 AND a.downstream_channel_width != 0
          AND a.downstream_channel_width < 10 THEN -25
        WHEN c.distance_to_stream > 25 AND r.waterbody_key IS NOT NULL
          AND a.downstream_channel_width != 0 AND a.downstream_channel_width < 4 THEN -100
        ELSE 0
      END AS width_order_score,
      NULL::boolean AS multiple_match_ind
    FROM %1$s.pscis_stream_candidates c
    INNER JOIN %2$s a ON c.stream_crossing_id = a.stream_crossing_id
    INNER JOIN whse_basemapping.fwa_stream_networks_sp str
      ON c.linear_feature_id = str.linear_feature_id
    LEFT JOIN whse_basemapping.fwa_rivers_poly r
      ON str.waterbody_key = r.waterbody_key
    LEFT JOIN %3$s m
      ON c.snapped_blue_line_key = m.blue_line_key
     AND ABS(c.downstream_route_measure - m.downstream_route_measure) < 100;", s, pscis_table, modelled_table) # nolint: indentation_linter, line_length_linter
  # NOTE: no `WHERE watershed_group_code = aoi` in Step 2 — mirrors bcfp's
  # province-wide pscis_streams_150m. Per-WSG filtering happens AFTER
  # frs_candidates_pick (Step 4) below. PSCIS that legitimately snap
  # across a WSG boundary stay in the candidate pool until per-PSCIS
  # pick + AOI filter resolves.
  .lnk_db_execute(conn, sql_streams_150m)

  # =====================================================================
  # Step 3: b-side dedup — NULL out modelled_crossing_id losers
  # =====================================================================
  # Mirrors bcfp 02_pscis_streams_150m.sql lines 172-218. For each
  # modelled_crossing_id with >1 PSCIS candidates pointing at it, the
  # PSCIS with the smallest modelled_xing_dist (planar Euclidean) wins;
  # losers get modelled_crossing_id = NULL + multiple_match_ind = TRUE.
  # Then multiple_match_ind resets to NULL when distance_to_stream < 50
  # (close-enough override).
  sql_bside_dedup <- sprintf("
    WITH dups AS (
      SELECT modelled_crossing_id
      FROM %1$s.pscis_streams_150m
      WHERE modelled_crossing_id IS NOT NULL
      GROUP BY modelled_crossing_id
      HAVING count(*) > 1
    ),
    to_retain AS (
      SELECT DISTINCT ON (modelled_crossing_id)
        stream_crossing_id, modelled_crossing_id
      FROM %1$s.pscis_streams_150m
      WHERE modelled_crossing_id IN (SELECT modelled_crossing_id FROM dups)
      ORDER BY modelled_crossing_id, modelled_xing_dist ASC, stream_crossing_id ASC
    ),
    to_update AS (
      SELECT p.stream_crossing_id, p.modelled_crossing_id
      FROM %1$s.pscis_streams_150m p
      INNER JOIN dups USING (modelled_crossing_id)
      LEFT JOIN to_retain r USING (stream_crossing_id, modelled_crossing_id)
      WHERE r.stream_crossing_id IS NULL
    )
    UPDATE %1$s.pscis_streams_150m
    SET modelled_crossing_id = NULL,
        modelled_xing_dist_instream = NULL,
        modelled_crossing_type = NULL,
        multiple_match_ind = TRUE
    WHERE stream_crossing_id IN (SELECT stream_crossing_id FROM to_update);", s) # nolint: indentation_linter, line_length_linter
  .lnk_db_execute(conn, sql_bside_dedup)

  sql_close_enough_reset <- sprintf("
    UPDATE %1$s.pscis_streams_150m
    SET multiple_match_ind = NULL
    WHERE multiple_match_ind IS TRUE AND distance_to_stream < 50;", s) # nolint: indentation_linter, line_length_linter
  .lnk_db_execute(conn, sql_close_enough_reset)

  # =====================================================================
  # Step 4: per-PSCIS pick via fresh::frs_candidates_pick
  # =====================================================================
  # Mirrors bcfp 04_pscis.sql per-PSCIS dedup with:
  #   - filter: name_score != -100 AND width_order_score != -100
  #             AND multiple_match_ind IS NULL
  #   - order_by: name_score DESC, weighted_distance ASC
  #     (weighted_distance: 90% of distance_to_stream when a modelled match
  #      was found within 100m; full distance otherwise)
  fresh::frs_candidates_pick(
    conn,
    table_in   = paste0(s, ".pscis_streams_150m"),
    table_to   = paste0(s, ".pscis_picked"),
    col_key    = "stream_crossing_id",
    exp_filter = "name_score != -100 AND width_order_score != -100 AND multiple_match_ind IS NULL",
    order_by = c(
      "name_score DESC",
      paste0(
        "CASE WHEN modelled_xing_dist_instream IS NOT NULL ",
        "THEN distance_to_stream - (distance_to_stream * 0.1) ",
        "ELSE distance_to_stream END ASC"
      ),
      "linear_feature_id ASC"  # deterministic tiebreak when scores + distance tie
    )
  )

  # Step 4b: filter the picked PSCIS to AOI. After per-PSCIS dedup, each
  # PSCIS has been bound to ONE FWA stream — the watershed_group_code of
  # that stream is the canonical PSCIS WSG. Drop rows not in our AOI.
  # RPostgres requires one statement per dbExecute call.
  .lnk_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s.pscis;", s))
  sql_aoi_filter <- sprintf("
    CREATE TABLE %1$s.pscis AS
    SELECT * FROM %1$s.pscis_picked
    WHERE watershed_group_code = %2$s;", s, .lnk_quote_literal(aoi)) # nolint: indentation_linter, line_length_linter
  .lnk_db_execute(conn, sql_aoi_filter)

  # =====================================================================
  # Step 4c: DBSCAN 5m spatial cluster dedup
  # =====================================================================
  # Mirrors bcfp 04_pscis.sql `clusters AS ... ST_ClusterDBSCAN(geom, 5, 1)
  # ... de_duped AS SELECT DISTINCT ON (cid) ORDER BY cid, distance_to_stream
  # asc, assessment_date desc, modelled_crossing_id`. Within-cluster
  # priority: closest to stream wins, then newest assessment, then lowest
  # modelled_crossing_id. Drops PSCIS that bcfp folds into a neighbor.
  # Without this, BULK leaks ~97 extras (most of the 104 PSCIS that
  # bcfp drops via this step).
  sql_dbscan_dedup <- sprintf("
    WITH clusters AS (
      SELECT
        stream_crossing_id,
        ST_ClusterDBSCAN(geom_snapped, 5, 1) OVER () AS cid
      FROM %1$s.pscis
    ),
    de_duped AS (
      SELECT DISTINCT ON (cid) c.stream_crossing_id
      FROM clusters c
      INNER JOIN %1$s.pscis p ON c.stream_crossing_id = p.stream_crossing_id
      LEFT JOIN %2$s a ON c.stream_crossing_id = a.stream_crossing_id
      ORDER BY cid, p.distance_to_stream ASC,
               a.assessment_date DESC NULLS LAST,
               p.modelled_crossing_id ASC NULLS LAST
    )
    DELETE FROM %1$s.pscis
    WHERE stream_crossing_id NOT IN (SELECT stream_crossing_id FROM de_duped);
    ", s, pscis_table) # nolint: indentation_linter, line_length_linter
  .lnk_db_execute(conn, sql_dbscan_dedup)

  # =====================================================================
  # Step 4d: UNIQUE(blue_line_key, downstream_route_measure) dedup
  # =====================================================================
  # Mirrors bcfp's table-level `UNIQUE (blue_line_key,
  # downstream_route_measure)` constraint enforced via `ON CONFLICT DO
  # NOTHING` on both INSERTs. When two PSCIS resolve to the same
  # (blue_line_key, downstream_route_measure) after CEIL/FLOOR rounding
  # in lnk_points_snap, only the closest-to-stream wins. Accounts for
  # the remaining ~7 BULK extras not caught by DBSCAN.
  sql_blkdrm_dedup <- sprintf("
    WITH winners AS (
      SELECT DISTINCT ON (blue_line_key, downstream_route_measure)
        stream_crossing_id
      FROM %1$s.pscis
      ORDER BY blue_line_key, downstream_route_measure,
               distance_to_stream ASC, stream_crossing_id ASC
    )
    DELETE FROM %1$s.pscis
    WHERE stream_crossing_id NOT IN (SELECT stream_crossing_id FROM winners);
    ", s) # nolint: indentation_linter
  .lnk_db_execute(conn, sql_blkdrm_dedup)

  # =====================================================================
  # Step 5: apply xref CSV overrides (manual PSCIS->modelled matches)
  # =====================================================================
  # Check whether the xref staging table exists (lnk_pipeline_load may
  # skip if the bundle doesn't ship it). If present, apply on top.
  has_xref <- DBI::dbGetQuery(conn, sprintf(
    "SELECT EXISTS (
       SELECT 1 FROM information_schema.tables
       WHERE table_schema = %s
         AND table_name = 'pscis_modelledcrossings_streams_xref'
     ) AS present;",
    DBI::dbQuoteString(conn, s)
  ))$present

  if (isTRUE(has_xref)) {
    # Mirror bcfp's two-INSERT order from 04_pscis.sql:
    #
    # 1. xref rows take precedence — for each xref stream_crossing_id,
    #    use the xref-supplied modelled_crossing_id or linear_feature_id
    #    to compute the on-stream location. snap-derived location is
    #    discarded for xref-mapped IDs.
    # 2. The snap-derived path silently drops any stream_crossing_id
    #    that appears in xref (bcfp `pts AS ... WHERE stream_crossing_id
    #    NOT IN (xref)`).
    #
    # Net: xref-mapped IDs land via xref; everything else via snap.
    # Without this, BULK leaks ~88 xref-mapped PSCIS that bcfp drops
    # (xref maps them to a now-missing modelled_crossing_id; bcfp's
    # INNER JOIN to modelled_stream_crossings filters them out).

    # Drop xref-mapped IDs from the snap path output. Re-inserted next
    # via xref-driven paths.
    sql_drop_xref_snap <- sprintf("
      DELETE FROM %1$s.pscis
      WHERE stream_crossing_id IN (
        SELECT stream_crossing_id
        FROM %1$s.pscis_modelledcrossings_streams_xref
      );", s) # nolint: indentation_linter
    .lnk_db_execute(conn, sql_drop_xref_snap)

    # Insert xref rows. Two-branch UNION ALL mirrors bcfp's
    # referenced_modelled_xing + referenced_streams CTEs:
    #
    # Branch A (referenced_modelled_xing): xref.modelled_crossing_id is
    # set → look up modelled_stream_crossings → INNER JOIN to FWA via
    # m.linear_feature_id. modelled_crossing_id missing from the local
    # table silently drops the row (bcfp parity).
    #
    # Branch B (referenced_streams): xref.linear_feature_id is set →
    # look up FWA directly. xref entries with neither set produce no
    # row (effectively excluded from pscis).
    sql_xref_insert <- sprintf("
      INSERT INTO %1$s.pscis (
        stream_crossing_id, modelled_crossing_id, linear_feature_id,
        blue_line_key, downstream_route_measure, wscode_ltree,
        localcode_ltree, watershed_group_code, distance_to_stream,
        current_barrier_result_code, current_pscis_status,
        geom_snapped
      )
      -- Branch A: xref via modelled_crossing_id
      SELECT
        x.stream_crossing_id,
        x.modelled_crossing_id,
        m.linear_feature_id,
        m.blue_line_key,
        CEIL(GREATEST(s.downstream_route_measure, FLOOR(LEAST(s.upstream_route_measure,
          (ST_LineLocatePoint(s.geom, ST_ClosestPoint(s.geom, ST_GeometryN(p.geom, 1)))
            * s.length_metre) + s.downstream_route_measure
        )))) AS downstream_route_measure,
        m.wscode_ltree::ltree,
        m.localcode_ltree::ltree,
        m.watershed_group_code,
        ST_Distance(p.geom, ST_ClosestPoint(s.geom, ST_GeometryN(p.geom, 1)))
          AS distance_to_stream,
        a.current_barrier_result_code,
        a.current_pscis_status,
        ST_ClosestPoint(s.geom, ST_GeometryN(p.geom, 1)) AS geom_snapped
      FROM %1$s.pscis_modelledcrossings_streams_xref x
      INNER JOIN %4$s m ON x.modelled_crossing_id = m.modelled_crossing_id
      INNER JOIN whse_basemapping.fwa_stream_networks_sp s
        ON m.linear_feature_id = s.linear_feature_id
      INNER JOIN %2$s p ON x.stream_crossing_id = p.stream_crossing_id
      LEFT JOIN %2$s a ON x.stream_crossing_id = a.stream_crossing_id
      WHERE x.modelled_crossing_id IS NOT NULL
        AND m.watershed_group_code = %3$s

      UNION ALL

      -- Branch B: xref via linear_feature_id directly
      SELECT
        x.stream_crossing_id,
        x.modelled_crossing_id,
        x.linear_feature_id,
        s.blue_line_key,
        CEIL(GREATEST(s.downstream_route_measure, FLOOR(LEAST(s.upstream_route_measure,
          (ST_LineLocatePoint(s.geom, ST_ClosestPoint(s.geom, ST_GeometryN(p.geom, 1)))
            * s.length_metre) + s.downstream_route_measure
        )))) AS downstream_route_measure,
        s.wscode_ltree,
        s.localcode_ltree,
        s.watershed_group_code,
        ST_Distance(p.geom, ST_ClosestPoint(s.geom, ST_GeometryN(p.geom, 1)))
          AS distance_to_stream,
        a.current_barrier_result_code,
        a.current_pscis_status,
        ST_ClosestPoint(s.geom, ST_GeometryN(p.geom, 1)) AS geom_snapped
      FROM %1$s.pscis_modelledcrossings_streams_xref x
      INNER JOIN whse_basemapping.fwa_stream_networks_sp s
        ON x.linear_feature_id = s.linear_feature_id
      INNER JOIN %2$s p ON x.stream_crossing_id = p.stream_crossing_id
      LEFT JOIN %2$s a ON x.stream_crossing_id = a.stream_crossing_id
      WHERE x.linear_feature_id IS NOT NULL
        AND s.watershed_group_code = %3$s;
      ", s, pscis_table, .lnk_quote_literal(aoi), modelled_table) # nolint: indentation_linter, line_length_linter
    .lnk_db_execute(conn, sql_xref_insert)

    # Final UNIQUE(blue_line_key, downstream_route_measure) dedup after
    # xref INSERT — xref rows may collide with snap rows at the same
    # location. bcfp's xref INSERT runs FIRST (xref always wins);
    # ours runs last, so winners are determined by smallest
    # distance_to_stream after both INSERTs. Same UNIQUE-collision
    # semantics, deterministic with a stream_crossing_id tiebreak.
    .lnk_db_execute(conn, sql_blkdrm_dedup)
  }

  invisible(conn)
}
