#' Habitat upstream of each crossing, per species
#'
#' For each crossing, sums the habitat of each species found anywhere
#' upstream of it on the stream network: the crossing's own stream above
#' it and every tributary, in every watershed group the persist schema
#' holds. This is the demand side of prioritization: severity says how bad
#' a barrier is, upstream habitat says what fixing it would open.
#'
#' The walk is [fresh::frs_aggregate()], refined by the measure-aware
#' `fwa_upstream(..., include_equivalents = TRUE, tolerance = 1)` that
#' bcfishpass's `crossings_upstream_habitat` uses, so a segment counts when
#' it starts at or above the crossing (within 1 m) on the crossing's own
#' stream, or lies on a stream that joins above it. The main stem below
#' the crossing never counts.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified table of crossings, with
#'   `col_id`, `blue_line_key` and `downstream_route_measure`. Typically a
#'   working schema's `crossings`.
#' @param schema Character. The persist schema holding `streams` and
#'   `streams_habitat_<sp>` (for example `"fresh_default"`). Every group it
#'   holds is read: upstream habitat crosses watershed groups, so groups
#'   upstream of the crossings must be persisted for their habitat to count.
#' @param to Character. `<schema>.<table>` to write (dropped and recreated),
#'   outside `schema` and different from `crossings` and `barriers`. One row
#'   per crossing and species.
#' @param config Character. The config whose build `schema` holds, written
#'   to the `config` column (for example `cfg$name`).
#' @param species Character vector of species codes, or `NULL` (default)
#'   for every `streams_habitat_<sp>` table in `schema`.
#' @param col_id Character. Crossing identifier column. Default
#'   `"aggregated_crossings_id"`.
#' @param barriers Character or `NULL`. Schema-qualified table of human-made
#'   barriers (for example a working schema's `barriers_anthropogenic`, from
#'   [lnk_barriers_emit()]), with `barriers_col_id`, `blue_line_key`,
#'   `downstream_route_measure`. When given, each metric also gets a
#'   `_belowupstrbarriers_km` total: the habitat upstream of the crossing
#'   but below the next barriers upstream, as bcfishpass's
#'   `*_belowupstrbarriers_km`.
#' @param barriers_col_id Character. Identifier column of `barriers`.
#'   Default `"barriers_anthropogenic_id"`. Ids shared with `crossings`
#'   name the same feature.
#' @param verbose Logical. Report each species' summary.
#'
#' @return `invisible(to)`. Side effect: creates `to`.
#'
#' @details
#' Columns of `to`: the crossing id (named as `col_id`), `config`,
#' `species_code`, then in km:
#'
#' - `spawning_km`: segments the species spawns on;
#' - `rearing_km`: segments it rears on, lake connection lines left out,
#'   as [lnk_rollup_wsg()]'s `rearing_km`;
#' - `rearing_stream_km`, `rearing_lake_km`, `rearing_wetland_km`: that
#'   rearing split by the polygon each line sits in;
#' - `rearing_lake_connection_km`: rearing on lake connection lines
#'   (FWA edge 1450 in a lake), which bcfishpass counts in rearing.
#'
#' Each sum is exact (`numeric`), so it does not depend on row order. A
#' crossing with no habitat upstream gets zeros. A crossing whose measure
#' is exactly the top of its stream has no segment holding it, so nothing
#' is found above it and it gets zeros.
#'
#' The barrier totals subtract, from a crossing's total, the totals of the
#' barriers upstream of it that have no other barrier between it and them
#' (a barrier at the crossing's own id is not its own upstream barrier). Of
#' two barriers within 1 m on one stream, the one with the higher measure is
#' upstream of the other, so the habitat above the pair is subtracted once.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#' # a working schema left by lnk_pipeline_run(cleanup_working = FALSE)
#' lnk_aggregate(conn,
#'   crossings = "working_adms.crossings",
#'   schema = "fresh_default",
#'   to = "working_adms.crossings_upstream_habitat",
#'   config = "default",
#'   barriers = "working_adms.barriers_anthropogenic")
#'
#' # which barriers block the most chinook spawning below the next barrier?
#' DBI::dbGetQuery(conn, "
#'   SELECT aggregated_crossings_id, spawning_belowupstrbarriers_km
#'   FROM working_adms.crossings_upstream_habitat
#'   WHERE species_code = 'CH'
#'   ORDER BY 2 DESC LIMIT 5")
#' }
#'
#' @export
# nolint start: indentation_linter
lnk_aggregate <- function(conn,
                          crossings,
                          schema,
                          to,
                          config,
                          species = NULL,
                          col_id = "aggregated_crossings_id",
                          barriers = NULL,
                          barriers_col_id = "barriers_anthropogenic_id",
                          verbose = TRUE) {
  stopifnot(inherits(conn, "DBIConnection"))
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(to, "output table")
  .lnk_validate_identifier(col_id, "col_id")
  if (!is.character(schema) || length(schema) != 1L ||
        !grepl("^[a-z_][a-z0-9_]*$", schema)) {
    stop("`schema` must be one lower-case schema name.", call. = FALSE)
  }
  if (!is.character(config) || length(config) != 1L || is.na(config) ||
        !nzchar(config)) {
    stop("`config` must be one non-empty string.", call. = FALSE)
  }
  if (!is.null(barriers)) {
    .lnk_validate_identifier(barriers, "barriers table")
    .lnk_validate_identifier(barriers_col_id, "barriers_col_id")
  }
  for (tb in c(crossings, barriers, paste0(schema, ".streams"))) {
    if (!.lnk_table_exists(conn, tb)) {
      stop("Table not found: '", tb, "'.", call. = FALSE)
    }
  }
  # `to` is dropped and recreated, so it may not be the crossings or barriers
  # table (compared as Postgres resolves the names) nor lie in the persist
  # schema, where `streams` and `streams_habitat_<sp>` live. The FWA tables
  # the walk also reads are not checked.
  to_parts <- strsplit(to, ".", fixed = TRUE)[[1]]
  if (length(to_parts) != 2L) {
    stop("`to` must be '<schema>.<table>'; got '", to, "'.", call. = FALSE)
  }
  same_table <- isTRUE(DBI::dbGetQuery(conn, sprintf(
    "SELECT to_regclass(%s) = ANY (ARRAY[%s]) AS same",
    DBI::dbQuoteString(conn, to),
    paste(sprintf("to_regclass(%s)", DBI::dbQuoteString(conn, c(crossings, barriers))),
          collapse = ", ")))$same)
  if (same_table || tolower(to) %in% tolower(c(crossings, barriers)) ||
        tolower(to_parts[1]) == schema) {
    stop("`to` must differ from the crossings and barriers tables and lie ",
         "outside the persist schema '", schema, "'.", call. = FALSE)
  }

  if (is.null(species)) {
    species <- toupper(sub("^streams_habitat_", "", DBI::dbGetQuery(conn, sprintf(
      "SELECT table_name FROM information_schema.tables
        WHERE table_schema = %s AND table_name ~ '^streams_habitat_[a-z]+$'
        ORDER BY table_name", DBI::dbQuoteString(conn, schema)))$table_name))
  }
  if (!is.character(species) || length(species) == 0L ||
        !all(grepl("^[A-Za-z]+$", species))) {
    stop("`species` must name at least one species code (letters only).",
         call. = FALSE)
  }
  species <- toupper(species)
  for (sp in species) {
    tb <- sprintf("%s.streams_habitat_%s", schema, tolower(sp))
    if (!.lnk_table_exists(conn, tb)) {
      stop("Table not found: '", tb, "'.", call. = FALSE)
    }
  }

  q_id <- DBI::dbQuoteIdentifier(conn, col_id)
  metrics <- .lnk_aggregate_metrics()
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_res")

  # The points: every crossing, and every barrier (whose own totals the
  # barrier subtraction reads), on one key.
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_pts")
  pts_sql <- sprintf(
    "SELECT %1$s::text AS pt_id, blue_line_key::integer AS blue_line_key,
            downstream_route_measure::double precision AS downstream_route_measure,
            false AS is_barrier
       FROM %2$s",
    q_id, crossings)
  if (!is.null(barriers)) {
    pts_sql <- sprintf(
      "SELECT pt_id, min(blue_line_key) AS blue_line_key,
              min(downstream_route_measure) AS downstream_route_measure,
              bool_or(is_barrier) AS is_barrier
         FROM (%s
               UNION ALL
               SELECT %s::text, blue_line_key::integer,
                      downstream_route_measure::double precision, true
                 FROM %s) u
        GROUP BY pt_id",
      pts_sql, DBI::dbQuoteIdentifier(conn, barriers_col_id), barriers)
  }
  # Each point's segment, resolved once: the one holding its measure
  # ([downstream, upstream)) with the highest start, then the lowest id. FWA
  # segments can overlap (the next starts before the last ends), and a point
  # there would match two, doubling everything upstream of it in
  # frs_aggregate()'s join; the walk is held to this segment through `where`.
  .lnk_db_execute(conn, sprintf(
    "CREATE TEMP TABLE lnk_agg_pts AS
     SELECT u.*, r.linear_feature_id AS ref_lfid,
            r.wscode_ltree AS ref_wscode, r.localcode_ltree AS ref_localcode
       FROM (%s) u
       LEFT JOIN LATERAL (
         SELECT s.linear_feature_id, s.wscode_ltree, s.localcode_ltree
           FROM whse_basemapping.fwa_stream_networks_sp s
          WHERE s.blue_line_key = u.blue_line_key
            AND u.downstream_route_measure >= s.downstream_route_measure
            AND u.downstream_route_measure < s.upstream_route_measure
          ORDER BY s.downstream_route_measure DESC, s.linear_feature_id
          LIMIT 1) r ON true", pts_sql))
  n_dup <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*) - count(DISTINCT %s) AS n FROM %s", q_id, crossings))$n
  if (as.numeric(n_dup) > 0) {
    stop("`", col_id, "` is not unique in ", crossings, ".", call. = FALSE)
  }

  # Exact upstream test, bcfishpass's: the point's resolved segment (one of
  # the `ref` rows frs_aggregate() joins) gives its codes.
  upstream_where <- paste(
    "ref.linear_feature_id = p.ref_lfid AND",
    "whse_basemapping.fwa_upstream(p.blue_line_key, p.downstream_route_measure,",
    "ref.wscode_ltree, ref.localcode_ltree, f.blue_line_key,",
    "f.downstream_route_measure, f.wscode_ltree, f.localcode_ltree, true, 1)")

  if (!is.null(barriers)) .lnk_aggregate_barrier_pairs(conn)

  out <- list()
  for (sp in species) {
    .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_f")
    .lnk_db_execute(conn, sprintf(
      "CREATE TEMP TABLE lnk_agg_f AS
       SELECT s.blue_line_key, s.downstream_route_measure, s.wscode_ltree,
              s.localcode_ltree, s.length_metre,
              COALESCE(h.spawning, false) AS spawning,
              COALESCE(h.rearing, false) AS rearing,
              %s AS waterbody, %s AS connection
         FROM %s.streams s
         JOIN %s.streams_habitat_%s h
           ON s.id_segment = h.id_segment
          AND s.watershed_group_code = h.watershed_group_code
         %s
        WHERE h.spawning OR h.rearing",
      .lnk_sql_waterbody_class(), .lnk_sql_lake_connection(),
      schema, schema, tolower(sp), .lnk_sql_waterbody_join()))
    .lnk_db_execute(conn, "CREATE INDEX ON pg_temp.lnk_agg_f USING gist (wscode_ltree)")
    .lnk_db_execute(conn, "CREATE INDEX ON pg_temp.lnk_agg_f USING btree (wscode_ltree)")
    .lnk_db_execute(conn, "ANALYZE pg_temp.lnk_agg_f")

    fresh::frs_aggregate(
      conn,
      points = "pg_temp.lnk_agg_pts",
      features = "pg_temp.lnk_agg_f",
      metrics = metrics,
      id_col = "pt_id",
      direction = "upstream",
      where = upstream_where,
      to = "pg_temp.lnk_agg_sum"
    )
    out[[sp]] <- .lnk_aggregate_species(conn, sp, names(metrics), barriers)
  }

  # One table, crossings only, zeros where nothing was found
  cols_km <- names(metrics)
  if (!is.null(barriers)) {
    cols_km <- c(cols_km, sub("_km$", "_belowupstrbarriers_km", names(metrics)))
  }
  .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", to))
  .lnk_db_execute(conn, sprintf(
    "CREATE TABLE %s AS
     SELECT c.%s, %s::text AS config, r.species_code, %s
       FROM %s c
       JOIN pg_temp.lnk_agg_res r ON r.pt_id = c.%s::text
      ORDER BY r.species_code, c.%s",
    to, q_id, DBI::dbQuoteString(conn, config),
    paste0("r.", cols_km, collapse = ", "),
    crossings, q_id, q_id))
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_res")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_pts")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_f")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_sum")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_imm")

  if (verbose) {
    s <- DBI::dbGetQuery(conn, sprintf(
      "SELECT species_code, count(*)::int AS n,
              count(*) FILTER (WHERE spawning_km > 0 OR rearing_km > 0)::int AS n_habitat,
              round(max(spawning_km), 1) AS spawning_max,
              round(max(rearing_km), 1) AS rearing_max
         FROM %s GROUP BY 1 ORDER BY 1", to))
    for (i in seq_len(nrow(s))) {
      message(sprintf(
        "  %s: %d crossings, %d with habitat upstream; max spawning %s km, rearing %s km",
        s$species_code[i], s$n[i], s$n_habitat[i], s$spawning_max[i],
        s$rearing_max[i]))
    }
  }
  invisible(to)
}

#' The per-species metrics, as frs_aggregate() expressions over `f`
#'
#' Sums of `length_metre` cast to numeric once, so a sum is exact whatever
#' the row order (#356). km, unrounded.
#' @noRd
.lnk_aggregate_metrics <- function() {
  km <- function(filter) {
    sprintf("sum(f.length_metre::numeric) FILTER (WHERE %s) / 1000", filter)
  }
  c(
    spawning_km = km("f.spawning"),
    rearing_km = km("f.rearing AND NOT f.connection"),
    rearing_stream_km = km("f.rearing AND f.waterbody = 'stream'"),
    rearing_lake_km = km("f.rearing AND f.waterbody = 'lake' AND NOT f.connection"),
    rearing_wetland_km = km("f.rearing AND f.waterbody = 'wetland'"),
    rearing_lake_connection_km = km("f.rearing AND f.connection")
  )
}

#' One species' totals (and below-barrier totals) into pg_temp.lnk_agg_res
#'
#' Reads pg_temp.lnk_agg_sum (frs_aggregate()'s output) and lnk_agg_pts.
#' @noRd
.lnk_aggregate_species <- function(conn, sp, cols, barriers) {
  zero <- function(x) sprintf("COALESCE(%s, 0)", x)
  tot <- sprintf("CREATE TEMP TABLE lnk_agg_tot AS
    SELECT p.pt_id, p.is_barrier, p.blue_line_key, p.downstream_route_measure,
           %s
      FROM pg_temp.lnk_agg_pts p
      LEFT JOIN pg_temp.lnk_agg_sum s ON s.pt_id = p.pt_id",
    paste(sprintf("%s AS %s", zero(paste0("s.", cols)), cols), collapse = ",\n           "))
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_tot")
  .lnk_db_execute(conn, tot)

  below_sel <- ""
  below_join <- ""
  if (!is.null(barriers)) {
    below_join <- sprintf("
      LEFT JOIN (SELECT i.pt_id, %s
                   FROM pg_temp.lnk_agg_imm i
                   JOIN pg_temp.lnk_agg_tot b ON b.pt_id = i.bar_id
                  GROUP BY i.pt_id) ab ON ab.pt_id = t.pt_id",
      paste(sprintf("sum(b.%s) AS %s", cols, cols), collapse = ", "))
    below_sel <- paste0(",\n           ", paste(sprintf(
      "t.%s - %s AS %s", cols, zero(paste0("ab.", cols)),
      sub("_km$", "_belowupstrbarriers_km", cols)), collapse = ",\n           "))
  }

  res <- sprintf("
    SELECT t.pt_id, %s::text AS species_code,
           %s%s
      FROM pg_temp.lnk_agg_tot t%s",
    DBI::dbQuoteString(conn, sp),
    paste0("t.", cols, collapse = ", "), below_sel, below_join)
  exists <- DBI::dbGetQuery(conn,
    "SELECT to_regclass('pg_temp.lnk_agg_res') IS NOT NULL AS e")$e
  if (isTRUE(exists)) {
    .lnk_db_execute(conn, paste("INSERT INTO pg_temp.lnk_agg_res", res))
  } else {
    .lnk_db_execute(conn, paste("CREATE TEMP TABLE lnk_agg_res AS", res))
  }
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_tot")
  invisible(NULL)
}

#' Each point's immediate barriers upstream, into pg_temp.lnk_agg_imm
#'
#' Species-independent, so built once. `lnk_agg_up` holds each point's
#' barriers upstream, measured as bcfishpass measures upstream (the 10-argument
#' `fwa_upstream`, equivalents in, 1 m); a barrier is immediate when no other
#' barrier upstream of the point lies below it. Two barriers within 1 m on one
#' stream are each upstream of the other under that test, so the higher
#' measure (then the higher id) is taken as the upstream one: the habitat above
#' the pair is subtracted once. bcfishpass counts neither as upstream of the
#' other. The set difference is one hash
#' join, where a NOT EXISTS over the pair table ran for minutes on BULK.
#' @noRd
.lnk_aggregate_barrier_pairs <- function(conn) {
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_up")
  .lnk_db_execute(conn, "
    CREATE TEMP TABLE lnk_agg_up AS
    SELECT a.pt_id, b.pt_id AS bar_id
      FROM pg_temp.lnk_agg_pts a
      JOIN pg_temp.lnk_agg_pts b ON b.is_barrier AND b.pt_id <> a.pt_id
     WHERE a.ref_lfid IS NOT NULL AND b.ref_lfid IS NOT NULL
       AND b.ref_wscode <@ a.ref_wscode
       AND whse_basemapping.fwa_upstream(
             a.blue_line_key, a.downstream_route_measure,
             a.ref_wscode, a.ref_localcode,
             b.blue_line_key, b.downstream_route_measure,
             b.ref_wscode, b.ref_localcode, true, 1)
       -- the 1 m tolerance makes two barriers within 1 m of each other on one
       -- stream each upstream of the other; order them, higher measure (then
       -- higher id) upstream, or the EXCEPT drops both
       AND NOT (b.blue_line_key = a.blue_line_key
                AND abs(b.downstream_route_measure - a.downstream_route_measure) <= 1
                AND (b.downstream_route_measure, b.pt_id) < (a.downstream_route_measure, a.pt_id))")
  .lnk_db_execute(conn, "ANALYZE pg_temp.lnk_agg_up")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_imm")
  .lnk_db_execute(conn, "
    CREATE TEMP TABLE lnk_agg_imm AS
    SELECT pt_id, bar_id FROM pg_temp.lnk_agg_up
    EXCEPT
    SELECT mid.pt_id, beyond.bar_id
      FROM pg_temp.lnk_agg_up mid
      JOIN pg_temp.lnk_agg_up beyond ON beyond.pt_id = mid.bar_id")
  .lnk_db_execute(conn, "DROP TABLE IF EXISTS pg_temp.lnk_agg_up")
  invisible(NULL)
}
# nolint end: indentation_linter
