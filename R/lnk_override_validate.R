#' Validate override referential integrity
#'
#' Check that override records reference real crossings and flag orphans,
#' duplicates, and conflicts. Optional step between [lnk_override_load()]
#' and [lnk_override_apply()] — recommended for production workflows where
#' overrides accumulate across field seasons.
#'
#' @param conn A [DBI::DBIConnection-class] object.
#' @param overrides Character. Schema-qualified override table.
#' @param crossings Character. Schema-qualified crossings table to validate
#'   against.
#' @param col_id Character. Join column (system-agnostic).
#' @param verbose Logical. Print a summary of findings.
#'
#' @return A list with:
#'   \describe{
#'     \item{orphans}{Override IDs not found in crossings (GPS error? wrong
#'       watershed? crossing removed from model?)}
#'     \item{duplicates}{Crossing IDs that appear more than once in overrides
#'       (conflicting corrections — which one wins?)}
#'     \item{valid_count}{Number of overrides that will apply cleanly.}
#'     \item{total_count}{Total override records.}
#'   }
#'
#' @details
#' **Non-blocking:** returns findings but does not error. The user decides
#' whether orphans are acceptable (they often are — crossings get removed
#' from models between versions).
#'
#' **Why validate?** Override CSVs accumulate over years. Crossings get
#' renumbered, GPS coordinates get corrected, models get rebuilt. Without
#' validation, stale overrides silently fail to match and corrections are
#' lost.
#'
#' @examples
#' # --- Why validation matters ---
#' # You loaded 3 years of field reviews (1,200 overrides).
#' # The modelled crossings layer was rebuilt last month.
#' # How many overrides still point at valid crossings?
#' \dontrun{
#' conn <- lnk_db_conn()
#'
#' lnk_override_load(conn,
#'   csv = c("data/overrides/2023_field.csv",
#'           "data/overrides/2024_field.csv",
#'           "data/overrides/2025_field.csv"),
#'   to  = "working.overrides_all")
#'
#' result <- lnk_override_validate(conn,
#'   overrides = "working.overrides_all",
#'   crossings = "working.crossings")
#' # Override validation: working.overrides_all vs working.crossings
#' #   Total overrides:  1,200
#' #   Valid (matched):  1,147
#' #   Orphans:             48  <-- crossings removed from model
#' #   Duplicates:           5  <-- same crossing corrected twice
#' #
#' # The 48 orphans are expected — the model was rebuilt.
#' # The 5 duplicates need manual review: which correction wins?
#'
#' # Inspect the orphans
#' result$orphans
#' # [1] 5042 5108 5203 ...
#'
#' # Inspect the duplicates
#' result$duplicates
#' # [1] 1004 1007 ...
#'
#' # If satisfied, apply
#' lnk_override_apply(conn, "working.crossings",
#'   "working.overrides_all")
#' }
#'
#' @export
lnk_override_validate <- function(conn,
                                  overrides,
                                  crossings,
                                  col_id = "modelled_crossing_id",
                                  verbose = TRUE) {
  .lnk_validate_identifier(overrides, "overrides table")
  .lnk_validate_identifier(crossings, "crossings table")
  .lnk_validate_identifier(col_id, "join column")

  if (!.lnk_table_exists(conn, overrides)) {
    stop("Overrides table not found: '", overrides, "'.", call. = FALSE)
  }
  if (!.lnk_table_exists(conn, crossings)) {
    stop("Crossings table not found: '", crossings, "'.", call. = FALSE)
  }

  qt_over <- .lnk_quote_table(conn, overrides)
  qt_cross <- .lnk_quote_table(conn, crossings)
  qid <- DBI::dbQuoteIdentifier(conn, col_id)

  # Total count
  total_count <- DBI::dbGetQuery(
    conn,
    paste("SELECT count(*) AS n FROM", qt_over)
  )$n

  # Orphans: override IDs not in crossings
  orphan_sql <- paste0(
    "SELECT o.", qid,
    " FROM ", qt_over, " o",
    " LEFT JOIN ", qt_cross, " c ON o.", qid, " = c.", qid,
    " WHERE c.", qid, " IS NULL"
  )
  orphan_ids <- DBI::dbGetQuery(conn, orphan_sql)[[1]]

  # Duplicates: IDs appearing more than once in overrides
  dup_sql <- paste0(
    "SELECT ", qid,
    " FROM ", qt_over,
    " GROUP BY ", qid,
    " HAVING count(*) > 1"
  )
  dup_ids <- DBI::dbGetQuery(conn, dup_sql)[[1]]

  valid_count <- total_count - length(orphan_ids)

  if (verbose) {
    message("Override validation: ", overrides, " vs ", crossings)
    message("  Total overrides:  ", format(total_count, big.mark = ","))
    message("  Valid (matched):  ", format(valid_count, big.mark = ","))
    message("  Orphans:          ",
            format(length(orphan_ids), big.mark = ","),
            if (length(orphan_ids) > 0) "  <-- not found in crossings" else "")
    message("  Duplicates:       ",
            format(length(dup_ids), big.mark = ","),
            if (length(dup_ids) > 0) "  <-- same ID overridden multiple times"
            else "")
  }

  invisible(list(
    orphans = orphan_ids,
    duplicates = dup_ids,
    valid_count = valid_count,
    total_count = total_count
  ))
}
