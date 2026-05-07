#' Append a row to the run-tracking baseline ledger
#'
#' Records that a particular run (csv-sync, parity comparison, etc.) ran
#' against a specific upstream build. Constructs row from the
#' [lnk_bucket_log()] result + caller-supplied `run_label` / `notes`.
#' Stamps `run_started_pdt` (Pacific) and `host` (`Sys.info()[["nodename"]]`)
#' automatically.
#'
#' Validates ledger column shape on append: fails loud if the CSV header
#' doesn't match the expected `cols_baseline` shape (drift in the ledger
#' file is signaled, not silently corrupted).
#'
#' @param log A list with at minimum `model_version` and `date_completed`.
#'   Optional `head_sha` (full or short). The shape returned by
#'   [lnk_bucket_log()] qualifies; hand-built lists also work.
#' @param run_label A string identifying the run, e.g.
#'   `"csv-sync-20260507"`, `"provincial_default_extrabreaks"`.
#' @param link_schema The persistent target schema for the run, when
#'   applicable. Defaults to `"n/a"` for runs that don't write a
#'   pipeline schema (csv-sync, etc.).
#' @param notes Free-form notes column. Useful for short-sha references
#'   or any per-run context worth recording.
#' @param path Path to the ledger CSV. Defaults to
#'   `data-raw/logs/bcfp_baselines.csv`. Created with the canonical
#'   header if it does not yet exist.
#'
#' @return The path the row was appended to, invisibly.
#'
#' @details
#' `bcfp_model_run_id` is populated from `log$model_run_id` if present,
#' otherwise empty. The Path-2 (no DB tunnel) workflow doesn't have access
#' to `bcfishpass.log.model_run_id`; the SHA in `log$model_version` /
#' `log$head_sha` still uniquely identifies the upstream build.
#'
#' @examples
#' \dontrun{
#' log <- lnk_bucket_log()
#' tmp <- withr::local_tempfile(fileext = ".csv")
#' lnk_baseline_append(log,
#'                     run_label = "csv-sync-20260507",
#'                     notes = paste0("auto-append; head_sha=",
#'                                    substr(log$head_sha, 1, 7)),
#'                     path = tmp)
#' lnk_baseline_read(tmp)
#' }
#'
#' @family baseline
#' @seealso [lnk_baseline_read()], [lnk_bucket_log()]
#' @export
lnk_baseline_append <- function(log,
                                run_label,
                                link_schema = "n/a",
                                notes = "",
                                path = "data-raw/logs/bcfp_baselines.csv") {
  stopifnot(
    is.list(log),
    !is.null(log$model_version), nzchar(log$model_version),
    !is.null(log$date_completed), nzchar(log$date_completed),
    is.character(run_label), length(run_label) == 1L, nzchar(run_label),
    is.character(link_schema), length(link_schema) == 1L,
    is.character(notes), length(notes) == 1L,
    is.character(path), length(path) == 1L, nzchar(path)
  )

  expected <- names(cols_baseline) # nolint: object_usage_linter

  # Validate existing header shape (or create file with canonical header).
  if (file.exists(path)) {
    header <- readLines(path, n = 1L, warn = FALSE)
    actual <- strsplit(header, ",", fixed = TRUE)[[1]]
    if (!identical(actual, expected)) {
      stop(sprintf(
        "lnk_baseline_append: column shape mismatch in %s\n  expected: %s\n  actual:   %s",
        path,
        paste(expected, collapse = ", "),
        paste(actual, collapse = ", ")
      ))
    }
  } else {
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    writeLines(paste(expected, collapse = ","), path)
  }

  row <- list(
    run_started_pdt     = format(Sys.time(),
                                 tz = "America/Vancouver",
                                 "%Y-%m-%d %H:%M"),
    host                = Sys.info()[["nodename"]],
    run_label           = run_label,
    link_schema         = link_schema,
    bcfp_model_run_id   = if (!is.null(log$model_run_id)) {
      as.character(log$model_run_id)
    } else {
      ""
    },
    bcfp_model_version  = log$model_version,
    bcfp_date_completed = log$date_completed,
    notes               = notes
  )

  # CSV-quote anything containing comma / quote / newline. Simple writer
  # over utils::write.csv to avoid header collisions on append.
  csv_field <- function(x) {
    s <- as.character(x)
    if (grepl('[",\n]', s)) {
      paste0('"', gsub('"', '""', s, fixed = TRUE), '"')
    } else {
      s
    }
  }
  line <- paste(vapply(row[expected], csv_field, character(1)),
                collapse = ",")
  cat(line, "\n", sep = "", file = path, append = TRUE)

  invisible(path)
}
