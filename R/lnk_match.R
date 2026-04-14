#' Match crossing records across data systems
#'
#' Link crossing records from different sources using network position
#' (blue_line_key + downstream_route_measure) within a distance tolerance.
#' Bidirectional 1:1 dedup ensures each record matches at most once on
#' each side.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param sources List of source specs. Each spec is a named list with:
#'   \describe{
#'     \item{table}{(required) Schema-qualified table name.}
#'     \item{col_id}{(required) The ID column for this source.}
#'     \item{where}{(optional) Raw SQL filter. Developer API only —
#'       applied within a subquery.}
#'     \item{col_blk}{(optional) Override network key column.}
#'     \item{col_measure}{(optional) Override measure column.}
#'   }
#' @param xref_csv Character. Optional path to a CSV of known matches.
#'   Must have two columns matching the `col_id` of the first two sources.
#'   Applied first — matched IDs are excluded from spatial matching.
#' @param col_blk Character. Default network key column.
#' @param col_measure Character. Default measure column.
#' @param distance Numeric. Maximum network distance (metres) for a match.
#' @param to Character. Output table name.
#' @param overwrite Logical. Overwrite output table if it exists.
#' @param verbose Logical. Report match counts.
#'
#' @return The output table name (invisibly). The table contains columns:
#'   `source_a`, `id_a`, `source_b`, `id_b`, `distance_m`.
#'
#' @details
#' **N-way matching:** two or more sources produce pairwise comparisons.
#'
#' **1:1 dedup:** two-pass DISTINCT ON keeps only the closest match per
#' record on both sides. No many-to-many inflation.
#'
#' **xref priority:** when `xref_csv` is provided, those known matches
#' are applied first (distance = 0). Already-matched IDs are excluded
#' from spatial matching.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Two-source match
#' lnk_match(conn,
#'   sources = list(
#'     list(table = "whse_fish.pscis_assessment_svw",
#'          col_id = "stream_crossing_id"),
#'     list(table = "bcfishpass.modelled_stream_crossings",
#'          col_id = "modelled_crossing_id")),
#'   to = "working.matched_crossings")
#'
#' # With hand-curated xref corrections
#' lnk_match(conn,
#'   sources = list(
#'     list(table = "working.pscis", col_id = "stream_crossing_id"),
#'     list(table = "working.crossings", col_id = "modelled_crossing_id")),
#'   xref_csv = "data/overrides/pscis_modelled_xref.csv",
#'   to = "working.matched")
#' }
#'
#' @export
lnk_match <- function(conn,
                       sources,
                       xref_csv = NULL,
                       col_blk = "blue_line_key",
                       col_measure = "downstream_route_measure",
                       distance = 100,
                       to = "working.matched_crossings",
                       overwrite = TRUE,
                       verbose = TRUE) {
  if (!is.list(sources) || length(sources) < 2) {
    stop("`sources` must be a list of at least 2 source specs.", call. = FALSE)
  }

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

  qt_to <- .lnk_quote_table(conn, to)

  # --- Handle xref CSV if provided ---
  if (!is.null(xref_csv)) {
    if (!file.exists(xref_csv)) {
      stop("xref CSV not found: '", xref_csv, "'.", call. = FALSE)
    }

    xref <- utils::read.csv(xref_csv, stringsAsFactors = FALSE)
    id_a_col <- sources[[1]]$col_id
    id_b_col <- sources[[2]]$col_id

    required <- c(id_a_col, id_b_col)
    missing <- setdiff(required, names(xref))
    if (length(missing) > 0) {
      stop(
        "xref CSV missing required columns: ",
        paste(missing, collapse = ", "),
        call. = FALSE
      )
    }

    parts <- .lnk_parse_table(to)
    tbl_id <- DBI::Id(schema = parts$schema, table = parts$table)

    xref_out <- data.frame(
      source_a = sources[[1]]$table,
      id_a = as.character(xref[[id_a_col]]),
      source_b = sources[[2]]$table,
      id_b = as.character(xref[[id_b_col]]),
      distance_m = 0,
      stringsAsFactors = FALSE
    )
    DBI::dbWriteTable(conn, tbl_id, xref_out, overwrite = TRUE)

    if (verbose) {
      message("Applied ", nrow(xref), " known matches from xref CSV")
    }

    # Exclude already-matched IDs from spatial matching
    id_a_q <- DBI::dbQuoteIdentifier(conn, id_a_col)
    id_b_q <- DBI::dbQuoteIdentifier(conn, id_b_col)
    src_a_exclude <- paste0(
      id_a_col, "::text NOT IN (SELECT id_a FROM ", qt_to, ")"
    )
    src_b_exclude <- paste0(
      id_b_col, "::text NOT IN (SELECT id_b FROM ", qt_to, ")"
    )

    # Add where clauses to first two sources
    sources[[1]]$where <- if (is.null(sources[[1]]$where)) {
      src_a_exclude
    } else {
      paste0("(", sources[[1]]$where, ") AND ", src_a_exclude)
    }
    sources[[2]]$where <- if (is.null(sources[[2]]$where)) {
      src_b_exclude
    } else {
      paste0("(", sources[[2]]$where, ") AND ", src_b_exclude)
    }

    # Spatial match appends to existing xref table
    overwrite <- FALSE
  }

  # --- Create output table ---
  if (overwrite) {
    .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", qt_to))
    .lnk_db_execute(conn, paste0(
      "CREATE TABLE ", qt_to, " (",
      "source_a text, id_a text, ",
      "source_b text, id_b text, ",
      "distance_m numeric)"
    ))
  } else if (!.lnk_table_exists(conn, to)) {
    .lnk_db_execute(conn, paste0(
      "CREATE TABLE ", qt_to, " (",
      "source_a text, id_a text, ",
      "source_b text, id_b text, ",
      "distance_m numeric)"
    ))
  }

  # --- Pairwise matching ---
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
    n_total <- DBI::dbGetQuery(conn,
      paste("SELECT count(*) FROM", qt_to))[[1]]
    message("Total matched pairs: ", n_total)
  }

  invisible(to)
}
