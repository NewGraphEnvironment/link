#' Download a single artifact from a public S3 bucket prefix
#'
#' Fetch one file from a versioned S3 bucket (e.g., the bcfp build artifacts
#' under `s3://fresh-bc/bcfishpass/`). Returns raw bytes by default so
#' callers can decode based on file format (CSV via `read.csv`, JSON via
#' `jsonlite::fromJSON`, parquet via `arrow::read_parquet`, etc.) — the
#' helper is deliberately format-agnostic.
#'
#' Companion function: [lnk_bucket_log()] is sugar for the most common
#' read (`<prefix>/log.json`, the bcfp build identifier).
#'
#' @param name File path relative to `prefix`, e.g. `"log.json"` or
#'   `"csvs/wsg_species_presence.csv"`.
#' @param prefix Bucket prefix as an HTTPS URL. Defaults to NGE's bcfp dump
#'   prefix.
#' @param to Optional file path. When supplied, bytes are written there
#'   (binary) and the path is returned invisibly. When `NULL` (default),
#'   raw bytes are returned in memory.
#'
#' @return Either a `raw` vector (default) or, when `to` is supplied, the
#'   path it was written to (invisibly).
#'
#' @details
#' Uses `httr::GET()`. Fails loud (`stop()`) on any non-2xx response with
#' the URL + status code in the message. No retry/back-off — re-running
#' the workflow is the recovery path.
#'
#' Public bucket — no AWS auth needed for read. Writes happen via the
#' upstream `dump-bcfishpass-csvs.yml` workflow (separate; not this
#' function).
#'
#' @examples
#' \dontrun{
#' # Read the build identifier directly via the sugar helper.
#' log <- lnk_bucket_log()
#' log$model_version
#'
#' # Or fetch the same file as raw bytes and decode yourself.
#' bytes <- lnk_bucket_get("log.json")
#' jsonlite::fromJSON(rawToChar(bytes))
#'
#' # Pull a CSV and parse with read.csv (no temp file needed).
#' bytes <- lnk_bucket_get("csvs/wsg_species_presence.csv")
#' df <- read.csv(text = rawToChar(bytes))
#' head(df)
#'
#' # Stream a large file straight to disk.
#' tmp <- tempfile(fileext = ".csv")
#' lnk_bucket_get("csvs/user_modelled_crossing_fixes.csv", to = tmp)
#' file.info(tmp)$size
#' }
#'
#' @family bucket
#' @seealso [lnk_bucket_log()]
#' @export
lnk_bucket_get <- function(name,
                           prefix = "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass",
                           to = NULL) {
  stopifnot(
    is.character(name), length(name) == 1L, nzchar(name),
    is.character(prefix), length(prefix) == 1L, nzchar(prefix),
    is.null(to) || (is.character(to) && length(to) == 1L && nzchar(to))
  )

  url <- paste0(sub("/$", "", prefix), "/", sub("^/", "", name))

  if (is.null(to)) {
    resp <- httr::GET(url)
    if (httr::status_code(resp) >= 400L) {
      stop(sprintf("lnk_bucket_get: HTTP %d for %s",
                   httr::status_code(resp), url))
    }
    return(httr::content(resp, as = "raw"))
  }

  resp <- httr::GET(url, httr::write_disk(to, overwrite = TRUE))
  if (httr::status_code(resp) >= 400L) {
    stop(sprintf("lnk_bucket_get: HTTP %d for %s",
                 httr::status_code(resp), url))
  }
  invisible(to)
}
