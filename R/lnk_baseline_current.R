#' Is this host's baseline already current at the supplied upstream?
#'
#' Predicate helper for `data-raw/snapshot_bcfp.sh` and any other host-side
#' snapshot driver. Returns `TRUE` when the most recent ledger row for this
#' host already stamps the same upstream build that `log` carries — meaning
#' the local snapshot is already aligned with the bucket and re-running
#' would just churn.
#'
#' Per-host scoping is deliberate. Different hosts (M4, M1, cypher) each
#' populate their own local Postgres; one host stamping this week's SHA
#' must not gate the others. The predicate filters the ledger to rows
#' where `host == <this host>` before checking.
#'
#' @param log A list with at minimum `model_version` (e.g. the return of
#'   [lnk_bucket_log()]).
#' @param host Hostname to scope the check by. Defaults to
#'   `Sys.info()[["nodename"]]`. Pass an explicit value to test other
#'   hosts' rows.
#' @param path Path to the ledger CSV. Defaults to
#'   `data-raw/logs/bcfp_baselines.csv` relative to the working directory.
#'
#' @return `TRUE` when the latest row for `host` matches `log$model_version`
#'   (snapshot can be skipped — the host is already current at this upstream
#'   build). `FALSE` otherwise — including when the ledger file is missing,
#'   has no rows for `host`, or has a different model_version on its latest
#'   row for this host.
#'
#' @details
#' "Latest row for host" means the row with the lexicographically greatest
#' `run_started_pdt` among rows where `host` matches. The ledger's
#' `run_started_pdt` is written as `YYYY-MM-DD HH:MM` (PDT/PST), so
#' lexicographic ordering is also chronological ordering as long as the
#' format stays stable.
#'
#' @examples
#' \dontrun{
#' log <- lnk_bucket_log()
#'
#' if (lnk_baseline_current(log)) {
#'   message("This host already snapshotted at ", log$model_version,
#'           "; skipping.")
#'   quit(status = 0)
#' }
#' # ... otherwise proceed with the snapshot ...
#' }
#'
#' @family baseline
#' @seealso [lnk_baseline_read()], [lnk_baseline_append()], [lnk_bucket_log()]
#' @export
lnk_baseline_current <- function(log,
                                 host = Sys.info()[["nodename"]],
                                 path = "data-raw/logs/bcfp_baselines.csv") {
  stopifnot(
    is.list(log),
    "model_version" %in% names(log),
    is.character(log$model_version),
    length(log$model_version) == 1L,
    nzchar(log$model_version),
    is.character(host), length(host) == 1L, nzchar(host),
    is.character(path), length(path) == 1L, nzchar(path)
  )

  if (!file.exists(path)) {
    return(FALSE)
  }

  ledger <- lnk_baseline_read(path = path) # nolint: object_usage_linter
  host_rows <- ledger[ledger$host == host, , drop = FALSE]
  if (nrow(host_rows) == 0L) {
    return(FALSE)
  }

  latest <- host_rows[order(host_rows$run_started_pdt,
                            decreasing = TRUE), , drop = FALSE][1L, , drop = FALSE]
  identical(latest$bcfp_model_version, log$model_version)
}
