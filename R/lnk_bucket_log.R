#' Read the build-identifier `log.json` from a bucket prefix
#'
#' Sugar over [lnk_bucket_get()] for the most common read: parse the
#' `log.json` file at the top of a versioned S3 prefix into a named list.
#'
#' For NGE's bcfp dump (default prefix), `log.json` carries the SHA the
#' tunnel was rebuilt from, the model_version string, and the rebuild
#' completion timestamp. Downstream consumers (csv-sync, parity drivers)
#' use these to stamp run inputs and tie comparison rollups to a specific
#' upstream build.
#'
#' @param prefix Bucket prefix as an HTTPS URL. Defaults to NGE's bcfp dump
#'   prefix.
#'
#' @return A named list with at minimum `model_version`, `date_completed`,
#'   `head_sha`. Function fails loud if any of these required keys are
#'   missing — the contract with the upstream dump workflow.
#'
#' @examples
#' \dontrun{
#' log <- lnk_bucket_log()
#' log$model_version    # e.g. "v0.7.14-125-g6e9cf1c"
#' log$date_completed   # e.g. "2026-05-06T04:15:41Z"
#' substr(log$head_sha, 1, 7)
#'
#' # Pass to lnk_baseline_append() to stamp a run.
#' lnk_baseline_append(log, run_label = "csv-sync-20260507",
#'                     path = tempfile(fileext = ".csv"))
#' }
#'
#' @family bucket
#' @seealso [lnk_bucket_get()], [lnk_baseline_append()]
#' @export
lnk_bucket_log <- function(prefix = "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass") {
  bytes <- lnk_bucket_get("log.json", prefix = prefix) # nolint: object_usage_linter
  parsed <- jsonlite::fromJSON(rawToChar(bytes), simplifyVector = TRUE)

  required <- c("model_version", "date_completed", "head_sha")
  missing <- setdiff(required, names(parsed))
  if (length(missing) > 0L) {
    stop(sprintf(
      "lnk_bucket_log: log.json at %s missing required keys: %s",
      prefix, paste(missing, collapse = ", ")
    ))
  }
  parsed
}
