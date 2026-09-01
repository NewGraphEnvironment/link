#' Judge the outcome of a parallel fan-out
#'
#' Decides whether a work-list that was fanned out across N workers actually
#' completed. Every job is expected to record its own exit status; this reads
#' that record against the list of jobs that were *supposed* to run and
#' returns a verdict the caller can act on.
#'
#' Written for the post-consolidate recompute pool in
#' `data-raw/study_area_run.sh` (link#250), which has no shell test harness —
#' the predicate lives here because testthat can prove what shell cannot, the
#' same reasoning that put `lnk_preflight_vintage()` and
#' `lnk_preflight_parity()` in R. `data-raw/fanout_judge.R` is the
#' shell-callable wrapper.
#'
#' @section Why it takes names, not a count:
#' A count answers "how many finished" and cannot answer "which one didn't".
#' Passing the expected job ids lets the verdict name the jobs that never
#' reported, and lets it notice a job that reported but was never asked for —
#' which is a harness bug, not a work failure, and needs a different fix.
#'
#' `expected` deliberately has **no default**. Judging a result table on its
#' own terms produces an affirmative claim of success about jobs that never
#' reported at all — the failure mode this function exists to prevent. Same
#' doctrine as `n_expected` in [lnk_preflight_parity()].
#'
#' @section Statuses:
#' Evaluated in order, so the first that applies wins:
#'
#' \describe{
#'   \item{`none_expected`}{`expected` is empty. A fan-out over nothing exits
#'     0 exactly like a successful one, so this is a failure unless the caller
#'     passes `allow_empty = TRUE`.}
#'   \item{`none_ran`}{Nothing reported. Distinct from `all_failed`: no job
#'     got far enough to record anything, which points at the harness rather
#'     than at the work.}
#'   \item{`all_failed`}{Every job that reported failed, and none succeeded.
#'     Reported separately from how many are missing — both counts are always
#'     available.}
#'   \item{`ok`}{Every expected job reported, every status was zero, and there
#'     were no duplicate or unexpected ids.}
#'   \item{`partial`}{Anything else — some ran, some did not, or some failed.}
#' }
#'
#' @param rc A data frame with a `job` column and an `rc` column, both
#'   character. One row per job that actually reported. An `rc` that is `NA`,
#'   empty, or not a run of digits counts as a **failure**, never as a
#'   neutral: `as.integer("abc")` is `NA`, `NA != 0` is `NA`, and `which()`
#'   silently drops it.
#' @param expected Character vector of job ids that were supposed to run. No
#'   default — see Details.
#' @param label Character. Name for the phase, used in the message.
#' @param allow_empty Logical. Whether an empty `expected` is acceptable.
#'   Default `FALSE`.
#' @param quiet Logical. Suppress the summary message. Default `FALSE`.
#'
#' @return Invisibly, a list with `ok`, `status`, `label`, the counts
#'   (`n_expected`, `n_ran`, `n_ok`, `n_failed`, `n_missing`, `n_unexpected`),
#'   the id vectors (`failed`, `missing`, `unexpected`), the input `rc`,
#'   plus `problems` and a formatted `message`.
#'
#' @family preflight
#' @seealso [lnk_preflight_parity()]
#'
#' @examples
#' ran <- data.frame(job = c("BULK", "PARS", "ADMS"),
#'                   rc  = c("0", "0", "0"),
#'                   stringsAsFactors = FALSE)
#' res <- lnk_fanout_judge(ran, expected = c("BULK", "PARS", "ADMS"))
#' res$status
#'
#' # A job that failed and a job that never reported are different problems.
#' partial <- data.frame(job = c("BULK", "PARS"), rc = c("0", "1"),
#'                       stringsAsFactors = FALSE)
#' bad <- lnk_fanout_judge(partial, expected = c("BULK", "PARS", "ADMS"),
#'                         label = "recompute", quiet = TRUE)
#' bad$failed
#' bad$missing
#'
#' @export
lnk_fanout_judge <- function(rc, expected, label = "fanout",
                             allow_empty = FALSE, quiet = FALSE) {
  stopifnot(
    is.data.frame(rc),
    is.character(expected),
    is.character(label), length(label) == 1L, nzchar(label),
    is.logical(allow_empty), length(allow_empty) == 1L, !is.na(allow_empty),
    is.logical(quiet), length(quiet) == 1L, !is.na(quiet)
  )

  absent_cols <- setdiff(c("job", "rc"), names(rc))
  if (length(absent_cols)) {
    stop("lnk_fanout_judge(): `rc` is missing column(s): ",
         paste(absent_cols, collapse = ", "),
         ". Expected a data frame with `job` and `rc`.", call. = FALSE)
  }

  job <- as.character(rc$job)
  status <- as.character(rc$rc)
  problems <- character(0)

  # An unparseable status is a FAILURE, not a neutral. `as.integer("abc")` is
  # NA and every comparison against NA disappears from `which()`, so a job
  # whose status could not be read would otherwise be counted as fine.
  unreadable <- is.na(status) | !grepl("^[0-9]+$", status)
  nonzero <- !unreadable & status != "0"

  failed <- sort(unique(job[unreadable | nonzero]))
  succeeded <- sort(unique(job[!unreadable & !nonzero]))
  missing <- sort(setdiff(expected, job))
  unexpected <- sort(setdiff(job, expected))
  duplicated_jobs <- sort(unique(job[duplicated(job)]))

  if (any(unreadable)) {
    problems <- c(problems, sprintf(
      "unreadable exit status for: %s",
      paste(sprintf("%s=%s", job[unreadable],
                    ifelse(is.na(status[unreadable]), "NA",
                           sprintf("'%s'", status[unreadable]))),
            collapse = ", ")))
  }
  if (any(nonzero)) {
    problems <- c(problems, sprintf(
      "%d job(s) exited non-zero: %s", sum(nonzero),
      paste(sprintf("%s(rc=%s)", job[nonzero], status[nonzero]),
            collapse = ", ")))
  }
  if (length(missing)) {
    problems <- c(problems, sprintf(
      "%d job(s) never reported: %s", length(missing),
      paste(missing, collapse = ", ")))
  }
  if (length(unexpected)) {
    problems <- c(problems, sprintf(
      "%d job(s) reported but were not asked for: %s", length(unexpected),
      paste(unexpected, collapse = ", ")))
  }
  if (length(duplicated_jobs)) {
    problems <- c(problems, sprintf(
      "%d job(s) reported more than once: %s", length(duplicated_jobs),
      paste(duplicated_jobs, collapse = ", ")))
  }

  n_expected <- length(expected)
  n_ran <- length(unique(job))
  n_ok <- length(setdiff(succeeded, failed))

  # Order matters: the first branch that applies is the most accurate reading.
  # `all_failed` outranks `partial` even when jobs are also missing, because
  # "nothing succeeded" is both truer and more alarming; the missing count is
  # reported alongside it either way.
  st <- if (n_expected == 0L) {
    "none_expected"
  } else if (n_ran == 0L) {
    "none_ran"
  } else if (n_ok == 0L) {
    "all_failed"
  } else if (length(problems) == 0L) {
    "ok"
  } else {
    "partial"
  }

  if (st == "none_expected") {
    problems <- c(
      sprintf("no jobs were expected%s",
              if (allow_empty) " (allowed)" else
                " - a fan-out over nothing exits 0 exactly like a successful one"),
      problems)
  } else if (st == "none_ran") {
    problems <- c(sprintf("no job reported at all (%d expected)", n_expected),
                  problems)
  }

  ok <- if (st == "none_expected") allow_empty else st == "ok"

  out <- list(
    ok = ok, status = st, label = label,
    n_expected = n_expected, n_ran = n_ran, n_ok = n_ok,
    n_failed = length(failed), n_missing = length(missing),
    n_unexpected = length(unexpected),
    failed = failed, missing = missing, unexpected = unexpected,
    rc = rc, problems = problems,
    message = .lnk_fanout_message(label, st, ok, n_ok, n_expected, problems))
  if (!quiet) message(out$message)
  invisible(out)
}


.lnk_fanout_message <- function(label, status, ok, n_ok, n_expected,
                                problems) {
  if (ok && status == "ok") {
    return(sprintf("[fanout] %s - OK: %d/%d job(s) succeeded",
                   label, n_ok, n_expected))
  }
  if (ok) {
    return(sprintf("[fanout] %s - OK (%s): %d/%d job(s) succeeded",
                   label, status, n_ok, n_expected))
  }
  paste(c(sprintf("[fanout] %s - FAILED (%s): %d/%d job(s) succeeded",
                  label, status, n_ok, n_expected),
          paste0("  ", problems)),
        collapse = "\n")
}
