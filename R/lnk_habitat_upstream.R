#' Compute upstream habitat per crossing
#'
#' For each crossing, sum the upstream habitat accessible if the crossing
#' were remediated. This is the demand side of prioritization — severity
#' tells you how bad the barrier is, upstream habitat tells you what you'd
#' gain by fixing it.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified crossings table.
#' @param habitat Character. Schema-qualified habitat table (output of
#'   `frs_habitat_classify()` or similar).
#' @param col_id Character. Crossing identifier column (system-agnostic).
#' @param cols_sum Named character vector. Names = output column names,
#'   values = habitat columns to sum. Default sums spawning and rearing
#'   kilometres.
#' @param col_blk Character. Network key column name.
#' @param col_measure Character. Network measure column name.
#' @param col_length Character. Habitat segment length column for summing.
#' @param to Character. If `NULL`, adds columns to crossings table.
#'   Otherwise writes to new table.
#' @param verbose Logical. Report summary statistics.
#'
#' @return The table name (invisibly).
#'
#' @details
#' **The other half of prioritization:** severity alone doesn't tell you
#' where to invest. A high-severity barrier with 50m of upstream habitat is
#' lower priority than a moderate barrier with 15km of spawning habitat.
#'
#' **Flexible aggregation:** `cols_sum` lets you sum any habitat metric —
#' not just spawning/rearing. Lake rearing hectares, wetland area, total
#' accessible length — whatever the habitat classification produced.
#'
#' **Data flow:**
#' ```
#' link (score crossings) -> fresh (segment, classify) -> link (rollup)
#' ```
#' link scores crossings. fresh segments the network and classifies habitat.
#' link reads fresh's output to compute per-crossing rollups.
#'
#' @examples
#' # --- "Two barriers are both high severity.
#' #      One blocks 0.3km of rearing habitat.
#' #      The other blocks 12km of spawning habitat for chinook.
#' #      Which do you fix first?" ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Score crossings
#' lnk_score_severity(conn, "working.crossings")
#'
#' # Compute upstream habitat from fresh output
#' lnk_habitat_upstream(conn,
#'   crossings = "working.crossings",
#'   habitat = "fresh.streams_habitat")
#' # Added spawning_km, rearing_km to working.crossings
#' # Summary:
#' #   spawning_km: min=0.0, median=2.3, max=45.1
#' #   rearing_km:  min=0.0, median=5.7, max=89.2
#'
#' # Now you have severity + habitat — the full picture
#' # ORDER BY severity DESC, spawning_km DESC
#' # to find high-severity barriers blocking the most habitat.
#'
#' # --- Custom metrics ---
#' lnk_habitat_upstream(conn,
#'   crossings = "working.crossings",
#'   habitat = "fresh.streams_habitat",
#'   cols_sum = c(spawning_km = "spawning",
#'                rearing_km = "rearing",
#'                lake_ha = "lake_rearing"))
#' }
#'
#' @export
lnk_habitat_upstream <- function(conn,
                                 crossings,
                                 habitat,
                                 col_id = "modelled_crossing_id",
                                 cols_sum = c(spawning_km = "spawning",
                                              rearing_km = "rearing"),
                                 col_blk = "blue_line_key",
                                 col_measure = "downstream_route_measure",
                                 col_length = "length_metre",
                                 to = NULL,
                                 verbose = TRUE) {
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(habitat, "habitat table")
  .lnk_validate_identifier(col_id, "col_id")
  .lnk_validate_identifier(col_blk, "col_blk")
  .lnk_validate_identifier(col_measure, "col_measure")
  .lnk_validate_identifier(col_length, "col_length")

  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }
  if (!.lnk_table_exists(conn, habitat)) {
    stop("Habitat table not found: '", habitat, "'.", call. = FALSE)
  }

  if (!is.character(cols_sum) || is.null(names(cols_sum)) ||
        any(names(cols_sum) == "")) {
    stop("`cols_sum` must be a named character vector.", call. = FALSE)
  }

  for (nm in names(cols_sum)) {
    .lnk_validate_identifier(nm, "output column name")
    .lnk_validate_identifier(cols_sum[[nm]], "habitat column name")
  }

  # Determine target table
  target <- crossings
  if (!is.null(to)) {
    .lnk_validate_identifier(to, "output table")
    qt_cross <- .lnk_quote_table(conn, crossings)
    qt_to <- .lnk_quote_table(conn, to)
    .lnk_db_execute(conn, paste("DROP TABLE IF EXISTS", qt_to))
    .lnk_db_execute(conn, paste("CREATE TABLE", qt_to,
                                "AS SELECT * FROM", qt_cross))
    target <- to
  }

  qt_target <- .lnk_quote_table(conn, target)
  qt_habitat <- .lnk_quote_table(conn, habitat)
  q_id <- DBI::dbQuoteIdentifier(conn, col_id)
  q_blk <- DBI::dbQuoteIdentifier(conn, col_blk)
  q_meas <- DBI::dbQuoteIdentifier(conn, col_measure)
  q_len <- DBI::dbQuoteIdentifier(conn, col_length)

  # Add output columns if they don't exist
  target_cols <- .lnk_table_columns(conn, target)
  for (nm in names(cols_sum)) {
    if (!nm %in% target_cols) {
      q_nm <- DBI::dbQuoteIdentifier(conn, nm)
      .lnk_db_execute(conn, paste0(
        "ALTER TABLE ", qt_target, " ADD COLUMN ", q_nm, " numeric DEFAULT 0"
      ))
    }
  }

  # Build the SUM CASE expressions for each habitat metric
  sum_parts <- vapply(names(cols_sum), function(nm) {
    hab_col <- cols_sum[[nm]]
    q_nm <- DBI::dbQuoteIdentifier(conn, nm)
    q_hab <- DBI::dbQuoteIdentifier(conn, hab_col)
    paste0(
      q_nm, " = COALESCE(sub.", q_nm, ", 0)"
    )
  }, character(1))

  # Subquery: for each crossing, sum habitat on same blk upstream of measure
  sum_selects <- vapply(names(cols_sum), function(nm) {
    hab_col <- cols_sum[[nm]]
    q_nm <- DBI::dbQuoteIdentifier(conn, nm)
    q_hab <- DBI::dbQuoteIdentifier(conn, hab_col)
    paste0(
      "SUM(CASE WHEN h.", q_hab,
      " THEN h.", q_len, " / 1000.0 ELSE 0 END) AS ", q_nm
    )
  }, character(1))

  sub_sql <- paste0(
    "SELECT c.", q_id, ", ", paste(sum_selects, collapse = ", "),
    " FROM ", qt_target, " c",
    " JOIN ", qt_habitat, " h",
    " ON c.", q_blk, " = h.", q_blk,
    " AND h.", q_meas, " >= c.", q_meas,
    " GROUP BY c.", q_id
  )

  update_sql <- paste0(
    "UPDATE ", qt_target, " t SET ",
    paste(sum_parts, collapse = ", "),
    " FROM (", sub_sql, ") sub",
    " WHERE t.", q_id, " = sub.", q_id
  )

  .lnk_db_execute(conn, update_sql)

  if (verbose) {
    for (nm in names(cols_sum)) {
      q_nm <- DBI::dbQuoteIdentifier(conn, nm)
      stats <- DBI::dbGetQuery(conn, paste0(
        "SELECT min(", q_nm, ") AS mn, ",
        "percentile_cont(0.5) WITHIN GROUP (ORDER BY ", q_nm, ") AS med, ",
        "max(", q_nm, ") AS mx FROM ", qt_target
      ))
      message(
        "  ", nm, ": min=", round(stats$mn, 1),
        ", median=", round(stats$med, 1),
        ", max=", round(stats$mx, 1)
      )
    }
  }

  invisible(target)
}
