#' Validate and apply overrides to a table
#'
#' Check referential integrity (orphans, duplicates) then update matching
#' rows. Combines validation and application in one call.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified table to update.
#' @param overrides Character. Schema-qualified override table (output of
#'   [lnk_load()]).
#' @param col_id Character. Join column shared by both tables.
#' @param cols_update Character vector. Columns to copy from overrides to
#'   crossings. `NULL` (default) auto-detects: all columns in both tables
#'   excluding `col_id` and `cols_provenance`.
#' @param cols_provenance Character vector. Columns to exclude from
#'   auto-detection (provenance tracking, not data).
#' @param validate Logical. Run referential integrity check before
#'   applying. Reports orphans and duplicates. Default `TRUE`.
#' @param verbose Logical. Report validation results and update counts.
#'
#' @return A list with `n_updated`, `cols_updated`, and if `validate =
#'   TRUE`, `orphans`, `duplicates`, `valid_count`, `total_count`.
#'   Returned invisibly.
#'
#' @examples
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Load corrections
#' lnk_load(conn,
#'   csv = "data/overrides/modelled_xings_fixes.csv",
#'   to  = "working.fixes",
#'   cols_id = "modelled_crossing_id")
#'
#' # Validate and apply in one step
#' lnk_override(conn,
#'   crossings = "working.crossings",
#'   overrides = "working.fixes")
#' # Override validation: working.fixes vs working.crossings
#' #   Total overrides:  947
#' #   Valid (matched):  940
#' #   Orphans:            7
#' #   Duplicates:         0
#' # Updated 940 of 3597 crossings (barrier_status)
#' }
#'
#' @export
lnk_override <- function(conn,
                          crossings,
                          overrides,
                          col_id = "modelled_crossing_id",
                          cols_update = NULL,
                          cols_provenance = c("reviewer", "review_date",
                                             "reviewer_name", "source"),
                          validate = TRUE,
                          verbose = TRUE) {
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(overrides, "overrides table")
  .lnk_validate_identifier(col_id, "join column")

  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }
  if (!.lnk_table_exists(conn, overrides)) {
    stop("Overrides table not found: '", overrides, "'.", call. = FALSE)
  }

  result <- list()

  # --- Validate ---
  if (validate) {
    qt_over <- .lnk_quote_table(conn, overrides)
    qt_cross <- .lnk_quote_table(conn, crossings)
    qid <- DBI::dbQuoteIdentifier(conn, col_id)

    total_count <- DBI::dbGetQuery(
      conn, paste("SELECT count(*) AS n FROM", qt_over)
    )$n

    orphan_sql <- paste0(
      "SELECT o.", qid,
      " FROM ", qt_over, " o",
      " LEFT JOIN ", qt_cross, " c ON o.", qid, "::text = c.", qid, "::text",
      " WHERE c.", qid, " IS NULL"
    )
    orphan_ids <- DBI::dbGetQuery(conn, orphan_sql)[[1]]

    dup_sql <- paste0(
      "SELECT ", qid, " FROM ", qt_over,
      " GROUP BY ", qid, " HAVING count(*) > 1"
    )
    dup_ids <- DBI::dbGetQuery(conn, dup_sql)[[1]]

    valid_count <- total_count - length(orphan_ids)

    if (verbose) {
      message("Override validation: ", overrides, " vs ", crossings)
      message("  Total overrides:  ", format(total_count, big.mark = ","))
      message("  Valid (matched):  ", format(valid_count, big.mark = ","))
      message("  Orphans:          ",
              format(length(orphan_ids), big.mark = ","),
              if (length(orphan_ids) > 0) "  <-- not found in crossings"
              else "")
      message("  Duplicates:       ",
              format(length(dup_ids), big.mark = ","),
              if (length(dup_ids) > 0) "  <-- same ID overridden multiple times"
              else "")
    }

    result$orphans <- orphan_ids
    result$duplicates <- dup_ids
    result$valid_count <- valid_count
    result$total_count <- total_count
  }

  # --- Apply ---
  cross_cols <- .lnk_table_columns(conn, crossings)
  over_cols <- .lnk_table_columns(conn, overrides)

  if (!col_id %in% cross_cols) {
    stop("Join column '", col_id, "' not found in crossings table.",
         call. = FALSE)
  }
  if (!col_id %in% over_cols) {
    stop("Join column '", col_id, "' not found in overrides table.",
         call. = FALSE)
  }

  if (is.null(cols_update)) {
    exclude <- unique(c(col_id, cols_provenance))
    cols_update <- intersect(over_cols, cross_cols)
    cols_update <- setdiff(cols_update, exclude)
  }

  if (length(cols_update) == 0) {
    if (verbose) {
      message("No overlapping columns to update between '",
              overrides, "' and '", crossings, "'.")
    }
    result$n_updated <- 0L
    result$cols_updated <- character(0)
    return(invisible(result))
  }

  qt_cross <- .lnk_quote_table(conn, crossings)
  qt_over <- .lnk_quote_table(conn, overrides)
  qid <- DBI::dbQuoteIdentifier(conn, col_id)
  set_clauses <- vapply(cols_update, function(col) {
    qcol <- DBI::dbQuoteIdentifier(conn, col)
    paste0(qcol, " = o.", qcol)
  }, character(1))

  sql <- paste0(
    "UPDATE ", qt_cross, " c SET ",
    paste(set_clauses, collapse = ", "),
    " FROM ", qt_over, " o",
    " WHERE c.", qid, "::text = o.", qid, "::text"
  )

  n_updated <- .lnk_db_execute(conn, sql)

  if (verbose) {
    count_sql <- paste("SELECT count(*) FROM", qt_cross)
    n_total <- DBI::dbGetQuery(conn, count_sql)[[1]]
    message(
      "Updated ", n_updated, " of ", n_total, " rows (",
      paste(cols_update, collapse = ", "), ")"
    )
  }

  result$n_updated <- n_updated
  result$cols_updated <- cols_update
  invisible(result)
}
