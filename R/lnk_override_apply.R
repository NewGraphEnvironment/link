#' Apply overrides to a crossings table
#'
#' Join loaded overrides onto a crossings table and update matching columns.
#' Step two (or three) of the override pipeline:
#' [lnk_override_load()] -> [lnk_override_validate()] -> **apply**.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param crossings Character. Schema-qualified crossings table to update
#'   (e.g., `"working.crossings"`).
#' @param overrides Character. Schema-qualified override table (output of
#'   [lnk_override_load()]).
#' @param col_id Character. Join column — the crossing identifier shared by
#'   both tables. System-agnostic.
#' @param cols_update Character vector. Columns to copy from overrides to
#'   crossings. `NULL` (default) auto-detects: all columns in overrides that
#'   also exist in crossings, excluding `col_id` and provenance columns.
#' @param cols_provenance Character vector. Columns to exclude from
#'   auto-detection (they track who reviewed, not crossing attributes).
#' @param verbose Logical. Report how many rows were updated.
#'
#' @return A list with `n_updated` (rows changed) and `cols_updated`
#'   (columns that were updated), invisibly.
#'
#' @details
#' **Auto-detect mode:** when `cols_update = NULL`, the function finds
#' columns that exist in both the overrides and crossings tables (excluding
#' the join column and provenance columns) and updates those. This means
#' if your override CSV has `barrier_result_code` and your crossings table
#' has `barrier_result_code`, it just works — no configuration needed.
#'
#' **Explicit mode:** set `cols_update = c("barrier_result_code")` when you
#' want precision about exactly which columns change.
#'
#' **Idempotent:** running twice produces the same result.
#'
#' @examples
#' # --- The override pipeline: load, then apply ---
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' # Step 1: Load overrides
#' lnk_override_load(conn,
#'   csv = "data/overrides/modelled_xings_fixes.csv",
#'   to  = "working.overrides_modelled")
#'
#' # Step 2: Apply — auto-detects which columns to update
#' result <- lnk_override_apply(conn,
#'   crossings = "working.crossings",
#'   overrides = "working.overrides_modelled")
#' # Updated 342 of 15,230 crossings (barrier_result_code)
#' #
#' # The verbose output tells you the magnitude of changes —
#' # essential for QA. 342 corrections from 3 years of field work.
#'
#' # Step 3: Score the corrected crossings
#' lnk_score_severity(conn, "working.crossings")
#' # Severity scores now reflect field-verified barrier status,
#' # not just the raw modelled data.
#'
#' # --- Explicit column selection ---
#' lnk_override_apply(conn,
#'   crossings   = "working.crossings",
#'   overrides   = "working.overrides_modelled",
#'   cols_update = c("barrier_result_code"))
#' # Only updates barrier_result_code, even if the override table
#' # has other columns that match.
#' }
#'
#' @export
lnk_override_apply <- function(conn,
                               crossings,
                               overrides,
                               col_id = "modelled_crossing_id",
                               cols_update = NULL,
                               cols_provenance = c("reviewer",
                                                   "review_date",
                                                   "source"),
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

  cross_cols <- .lnk_table_columns(conn, crossings)
  over_cols <- .lnk_table_columns(conn, overrides)

  if (!col_id %in% cross_cols) {
    stop("Join column '", col_id, "' not found in crossings table.", call. = FALSE)
  }
  if (!col_id %in% over_cols) {
    stop("Join column '", col_id, "' not found in overrides table.", call. = FALSE)
  }

  # Determine which columns to update
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
    return(invisible(list(n_updated = 0L, cols_updated = character(0))))
  }

  # Validate update columns exist in both tables
  missing_cross <- setdiff(cols_update, cross_cols)
  if (length(missing_cross) > 0) {
    stop(
      "Update columns not found in crossings table: ",
      paste(missing_cross, collapse = ", "),
      call. = FALSE
    )
  }
  missing_over <- setdiff(cols_update, over_cols)
  if (length(missing_over) > 0) {
    stop(
      "Update columns not found in overrides table: ",
      paste(missing_over, collapse = ", "),
      call. = FALSE
    )
  }

  # Build UPDATE ... SET ... FROM ... WHERE SQL
  qt_cross <- .lnk_quote_table(conn, crossings)
  qt_over <- .lnk_quote_table(conn, overrides)
  qid <- DBI::dbQuoteIdentifier(conn, col_id)
  set_clauses <- vapply(cols_update, function(col) {
    qcol <- DBI::dbQuoteIdentifier(conn, col)
    paste0("c.", qcol, " = o.", qcol)
  }, character(1))

  sql <- paste0(
    "UPDATE ", qt_cross, " c SET ",
    paste(set_clauses, collapse = ", "),
    " FROM ", qt_over, " o",
    " WHERE c.", qid, " = o.", qid
  )

  n_updated <- .lnk_db_execute(conn, sql)

  if (verbose) {
    count_sql <- paste("SELECT count(*) FROM", qt_cross)
    n_total <- DBI::dbGetQuery(conn, count_sql)[[1]]
    message(
      "Updated ", n_updated, " of ", n_total, " crossings (",
      paste(cols_update, collapse = ", "), ")"
    )
  }

  invisible(list(n_updated = n_updated, cols_updated = cols_update))
}
