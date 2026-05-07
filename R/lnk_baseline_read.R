#' Column shape for the run-tracking baseline ledger
#'
#' Source-of-truth named character vector (column name -> R type) for the
#' CSV produced by [lnk_baseline_append()] and consumed by
#' [lnk_baseline_read()]. Defined inside `R/lnk_baseline_read.R` and reused
#' from `R/lnk_baseline_append.R` so the two stay in lockstep.
#'
#' Matches the historical hand-maintained shape of
#' `data-raw/logs/bcfp_baselines.csv`.
#'
#' @keywords internal
#' @noRd
cols_baseline <- c(
  run_started_pdt     = "character",
  host                = "character",
  run_label           = "character",
  link_schema         = "character",
  bcfp_model_run_id   = "character",
  bcfp_model_version  = "character",
  bcfp_date_completed = "character",
  notes               = "character"
)


#' Read the run-tracking baseline ledger
#'
#' Loads the per-run baseline CSV (each row stamps which upstream build a
#' particular comparison or sync ran against) into a tibble and validates
#' the column shape matches `cols_baseline`.
#'
#' Companion: [lnk_baseline_append()] writes rows; this reads them.
#'
#' @param path Path to the ledger CSV. Defaults to
#'   `data-raw/logs/bcfp_baselines.csv` relative to the working directory.
#'
#' @return A tibble with one row per recorded run. Columns:
#'   `run_started_pdt`, `host`, `run_label`, `link_schema`,
#'   `bcfp_model_run_id`, `bcfp_model_version`, `bcfp_date_completed`,
#'   `notes`. All character. `bcfp_model_run_id` may be empty for
#'   workflow-generated rows that lacked DB-tunnel access (Path 2).
#'
#' @details
#' Fails loud if the file's column header doesn't match `cols_baseline`.
#' Schema migrations to the ledger should update `cols_baseline` in
#' `R/lnk_baseline_read.R` and migrate the CSV in lockstep.
#'
#' @examples
#' \dontrun{
#' baseline <- lnk_baseline_read()
#' tail(baseline)
#'
#' # Filter to csv-sync-generated rows.
#' subset(baseline, grepl("^csv-sync-", run_label))
#' }
#'
#' @family baseline
#' @seealso [lnk_baseline_append()]
#' @export
lnk_baseline_read <- function(path = "data-raw/logs/bcfp_baselines.csv") {
  stopifnot(is.character(path), length(path) == 1L, nzchar(path))
  if (!file.exists(path)) {
    stop(sprintf("lnk_baseline_read: file not found: %s", path))
  }

  df <- utils::read.csv(path,
                        colClasses = "character",
                        stringsAsFactors = FALSE,
                        na.strings = character(0))

  expected <- names(cols_baseline)
  if (!identical(names(df), expected)) {
    stop(sprintf(
      "lnk_baseline_read: column shape mismatch in %s\n  expected: %s\n  actual:   %s",
      path,
      paste(expected, collapse = ", "),
      paste(names(df), collapse = ", ")
    ))
  }

  tibble::as_tibble(df)
}
