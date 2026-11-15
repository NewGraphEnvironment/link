#' Is this host's baseline already current at the supplied upstream?
#'
#' Predicate helper for `data-raw/snapshot_bcfp.sh` and any other host-side
#' snapshot driver. Returns `TRUE` when this host's most recent snapshot row
#' already stamps the upstream build `log` carries, by its version **and its
#' completion time** — meaning the local snapshot is aligned with the bucket
#' and re-running would just churn.
#'
#' Per-host scoping is deliberate. Different hosts (M4, M1, cypher) each
#' populate their own local Postgres; one host stamping this week's SHA
#' must not gate the others. The predicate filters the ledger to rows
#' where `host == <this host>` before checking.
#'
#' **What counts (link#276, link#446).** Only rows a snapshot wrote
#' (`run_label` starting `snapshot-`): a `csv-sync-` row loads nothing. With
#' `views = TRUE` (a snapshot asked for `--with-bcfp-views`), only snapshot
#' rows that loaded the views, so a newer views-less snapshot cannot skip a
#' reload of stale views. And the build must match by `date_completed` as
#' well as `model_version`: `model_version` is a code identity, so two weekly
#' builds of one commit share it (2026-08-18 and 2026-09-01 at
#' `v0.7.15-47-ga702229`), and a guard comparing only the version never
#' reloaded a host while the upstream rebuilt beneath it. A row whose date
#' cannot be read as an instant is not current.
#'
#' @param log A list with `model_version` and `date_completed` (the return of
#'   [lnk_bucket_log()]).
#' @param host Host to scope the check by. Defaults to `.lnk_host()`
#'   (`LNK_HOST_ALIAS` where set, else the node name), the name
#'   [lnk_baseline_append()] writes rows under.
#' @param path Path to the ledger CSV. Defaults to
#'   `data-raw/logs/bcfp_baselines.csv` relative to the working directory.
#' @param views `TRUE` when the snapshot will load bcfishpass's reference
#'   views, so only a row that loaded them can make it current.
#'
#' @return `TRUE` when the latest counting row for `host` matches `log`'s
#'   version and completion time (the snapshot can be skipped). `FALSE`
#'   otherwise — including when the ledger file is missing or has no counting
#'   row for `host`.
#'
#' @details
#' "Latest row for host" means the row with the lexicographically greatest
#' `run_started_pdt` among the counting rows where `host` matches. The ledger's
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
                                 host = .lnk_host(),
                                 path = "data-raw/logs/bcfp_baselines.csv",
                                 views = FALSE) {
  stopifnot(
    is.list(log),
    "model_version" %in% names(log),
    is.character(log$model_version),
    length(log$model_version) == 1L,
    nzchar(log$model_version),
    is.character(host), length(host) == 1L, nzchar(host),
    is.character(path), length(path) == 1L, nzchar(path),
    is.logical(views), length(views) == 1L, !is.na(views)
  )

  if (!file.exists(path)) {
    return(FALSE)
  }

  ledger <- lnk_baseline_read(path = path) # nolint: object_usage_linter
  counts <- if (views) {
    .lnk_baseline_loaded_views(ledger)
  } else {
    !is.na(ledger$run_label) & startsWith(ledger$run_label, "snapshot-")
  }
  host_rows <- ledger[ledger$host == host & counts, , drop = FALSE]
  if (nrow(host_rows) == 0L) {
    return(FALSE)
  }

  latest <- host_rows[order(host_rows$run_started_pdt,
                            decreasing = TRUE), , drop = FALSE][1L, , drop = FALSE]
  if (!identical(latest$bcfp_model_version, log$model_version)) {
    return(FALSE)
  }
  row_date <- .lnk_instant_utc(latest$bcfp_date_completed)
  log_date <- .lnk_instant_utc(log$date_completed)
  !is.na(row_date) && !is.na(log_date) &&
    as.numeric(row_date) == as.numeric(log_date)
}
