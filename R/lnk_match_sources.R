#' Match crossing records across multiple data systems
#'
#' Link crossing records from different sources using network position
#' (blue_line_key + downstream_route_measure) within a distance tolerance.
#' This is the generic matcher — [lnk_match_pscis()] and [lnk_match_moti()]
#' are convenience wrappers with BC defaults.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param sources List of source specs. Each spec is a named list with:
#'   \describe{
#'     \item{table}{(required) Schema-qualified table name.}
#'     \item{col_id}{(required) The ID column for this source.}
#'     \item{where}{(optional) Raw SQL filter predicate. Developer API
#'       only — must not contain user input. Applied within a subquery
#'       so column names are unambiguous.}
#'     \item{col_blk}{(optional) Override the network key column for
#'       this source.}
#'     \item{col_measure}{(optional) Override the measure column for
#'       this source.}
#'   }
#' @param col_blk Character. Default network key column name across
#'   sources. Default `"blue_line_key"`.
#' @param col_measure Character. Default measure column name across
#'   sources. Default `"downstream_route_measure"`.
#' @param distance Numeric. Maximum network distance (metres) for a
#'   match. Records further apart are not matched.
#' @param to Character. Output table name for matched pairs.
#' @param overwrite Logical. Overwrite output table if it exists.
#' @param verbose Logical. Report match counts per source pair.
#'
#' @return The output table name (invisibly). The table contains columns:
#'   `source_a`, `id_a`, `source_b`, `id_b`, `distance_m`.
#'
#' @details
#' **N-way matching:** not limited to two sources. Three sources produce
#' three pairwise comparisons. Each pair is matched independently.
#'
#' **Network-first:** matches on linear referencing position
#' (blue_line_key + downstream_route_measure). Records on the same stream
#' (same blue_line_key) within `distance` metres are matched.
#'
#' **System-agnostic:** each source declares its own ID column and
#' optionally its own network position column names. Works for any
#' jurisdiction's crossing data.
#'
#' @examples
#' # --- What matching solves ---
#' # PSCIS assessments have field measurements (outlet drop, culvert slope).
#' # Modelled crossings have network position (blue_line_key, measure).
#' # Matching links the measurements to the network so you can score.
#'
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Two-source match: PSCIS assessments to modelled crossings
#' lnk_match_sources(conn,
#'   sources = list(
#'     list(table = "whse_fish.pscis_assessment_svw",
#'          col_id = "stream_crossing_id"),
#'     list(table = "bcfishpass.modelled_stream_crossings",
#'          col_id = "modelled_crossing_id")),
#'   to = "working.matched_crossings")
#' # Matched 4,231 pairs within 100m on the same stream.
#' # Source A: whse_fish.pscis_assessment_svw (stream_crossing_id)
#' # Source B: bcfishpass.modelled_stream_crossings (modelled_crossing_id)
#'
#' # Three-way match including MOTI
#' lnk_match_sources(conn,
#'   sources = list(
#'     list(table = "whse_fish.pscis_assessment_svw",
#'          col_id = "stream_crossing_id"),
#'     list(table = "bcfishpass.modelled_stream_crossings",
#'          col_id = "modelled_crossing_id"),
#'     list(table = "working.moti_culverts",
#'          col_id = "chris_culvert_id")),
#'   distance = 150,
#'   to = "working.matched_all")
#' # Three pairwise comparisons, wider tolerance for MOTI GPS.
#'
#' # Filtered match — only assessed crossings in a watershed
#' lnk_match_sources(conn,
#'   sources = list(
#'     list(table = "whse_fish.pscis_assessment_svw",
#'          col_id = "stream_crossing_id",
#'          where = "watershed_group_code = 'BULK'"),
#'     list(table = "bcfishpass.modelled_stream_crossings",
#'          col_id = "modelled_crossing_id",
#'          where = "watershed_group_code = 'BULK'")),
#'   to = "working.matched_bulk")
#' }
#'
#' @export
lnk_match_sources <- function(conn,
                              sources,
                              col_blk = "blue_line_key",
                              col_measure = "downstream_route_measure",
                              distance = 100,
                              to = "working.matched_crossings",
                              overwrite = TRUE,
                              verbose = TRUE) {
  if (!is.list(sources) || length(sources) < 2) {
    stop("`sources` must be a list of at least 2 source specs.", call. = FALSE)
  }

  # Validate each source spec
  for (i in seq_along(sources)) {
    src <- sources[[i]]
    if (is.null(src$table)) {
      stop("Source ", i, " is missing required element `table`.", call. = FALSE)
    }
    if (is.null(src$col_id)) {
      stop("Source ", i, " is missing required element `col_id`.", call. = FALSE)
    }
    .lnk_validate_identifier(src$table, paste("source", i, "table"))
    .lnk_validate_identifier(src$col_id, paste("source", i, "col_id"))
    if (!.lnk_table_exists(conn, src$table)) {
      stop("Source table not found: '", src$table, "'.", call. = FALSE)
    }
  }

  .lnk_validate_identifier(to, "output table")
  .lnk_validate_identifier(col_blk, "col_blk")
  .lnk_validate_identifier(col_measure, "col_measure")

  if (!is.numeric(distance) || length(distance) != 1 ||
        is.nan(distance) || is.infinite(distance) || distance <= 0) {
    stop("`distance` must be a positive finite number.", call. = FALSE)
  }

  # Create output table
  qt_to <- .lnk_quote_table(conn, to)
  if (overwrite) {
    .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", qt_to))
  }
  .lnk_db_execute(conn, paste0(
    "CREATE TABLE ", qt_to, " (",
    "source_a text, id_a text, ",
    "source_b text, id_b text, ",
    "distance_m numeric)"
  ))

  # Pairwise matching
  pairs <- utils::combn(length(sources), 2, simplify = FALSE)

  for (pair in pairs) {
    src_a <- sources[[pair[1]]]
    src_b <- sources[[pair[2]]]

    qt_a <- .lnk_quote_table(conn, src_a$table)
    qt_b <- .lnk_quote_table(conn, src_b$table)

    blk_a <- DBI::dbQuoteIdentifier(conn, src_a$col_blk %||% col_blk)
    blk_b <- DBI::dbQuoteIdentifier(conn, src_b$col_blk %||% col_blk)
    meas_a <- DBI::dbQuoteIdentifier(conn, src_a$col_measure %||% col_measure)
    meas_b <- DBI::dbQuoteIdentifier(conn, src_b$col_measure %||% col_measure)
    id_a <- DBI::dbQuoteIdentifier(conn, src_a$col_id)
    id_b <- DBI::dbQuoteIdentifier(conn, src_b$col_id)

    label_a <- src_a$table
    label_b <- src_b$table

    # Build source subqueries with WHERE filters isolated to each source.
    # This prevents column name ambiguity and ensures filters apply to the
    # correct table. where clauses are raw SQL — developer API only.
    from_a <- qt_a
    if (!is.null(src_a$where)) {
      from_a <- paste0("(SELECT * FROM ", qt_a,
                       " WHERE ", src_a$where, ") ")
    }
    from_b <- qt_b
    if (!is.null(src_b$where)) {
      from_b <- paste0("(SELECT * FROM ", qt_b,
                       " WHERE ", src_b$where, ") ")
    }

    # Two-pass dedup: closest match per A, then closest per B.
    # Ensures 1:1 matching — no record appears more than once on either side.
    qdist <- DBI::dbQuoteLiteral(conn, distance)
    all_matches <- paste0(
      "SELECT ",
      DBI::dbQuoteLiteral(conn, label_a), " AS source_a, ",
      "a.", id_a, "::text AS id_a, ",
      DBI::dbQuoteLiteral(conn, label_b), " AS source_b, ",
      "b.", id_b, "::text AS id_b, ",
      "abs(a.", meas_a, " - b.", meas_b, ") AS distance_m",
      " FROM ", from_a, " a",
      " JOIN ", from_b, " b",
      " ON a.", blk_a, " = b.", blk_b,
      " AND abs(a.", meas_a, " - b.", meas_b, ") <= ", qdist
    )

    sql <- paste0(
      "INSERT INTO ", qt_to,
      " SELECT DISTINCT ON (id_b) * FROM (",
      " SELECT DISTINCT ON (id_a) * FROM (",
      all_matches,
      " ) raw ORDER BY id_a, distance_m",
      " ) best_a ORDER BY id_b, distance_m"
    )

    n_matched <- .lnk_db_execute(conn, sql)

    if (verbose) {
      message(
        "Matched ", n_matched, " pairs: ",
        label_a, " (", src_a$col_id, ") <-> ",
        label_b, " (", src_b$col_id, ")",
        " within ", distance, "m"
      )
    }
  }

  if (verbose) {
    n_total <- DBI::dbGetQuery(conn, paste("SELECT count(*) FROM", qt_to))[[1]]
    message("Total matched pairs: ", n_total)
  }

  invisible(to)
}
