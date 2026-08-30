#' Do all hosts' pre-flight stamps agree?
#'
#' A stale install on one cypher silently produces different rollup
#' numbers: the provincial run looks fine, and the bcfishpass parity diff
#' then contains version drift as well as methodology drift, with no way to
#' separate them afterwards. This is the #183 sibling-host parity hook,
#' absorbed into link#246.
#'
#' Three properties, each of which fails toward stop:
#'
#' - **Everybody answered.** `n_expected` has no default on purpose. A
#'   dropped ssh yields a short table, and a short table judged on its own
#'   terms produces "no mismatches found" — an affirmative claim of
#'   agreement among hosts that never replied.
#' - **Nothing is unresolved.** A field that is the literal `"NA"` on any
#'   host is a failure, not a neutral. `NA == NA` is not agreement.
#' - **Nothing is dirty.** A SHA recorded against a dirty tree is a lie,
#'   the same position [lnk_stamp()] already takes for packages.
#'
#' Only then are the key fields compared, against row 1 (the dispatcher) as
#' reference. `link_sha` and `fresh_sha` are deliberately **not** keys —
#' see [lnk_preflight_stamp()] for why comparing them is either guaranteed
#' to fail or guaranteed to pass vacuously.
#'
#' @param stamps A data frame, one row per host, from
#'   [lnk_preflight_stamp()].
#' @param n_expected Number of hosts that were supposed to report.
#'   Required.
#' @param keys Fields that must be identical across hosts.
#' @param forbid_na Fields that may not be the literal `"NA"` on any host.
#' @param forbid_dirty Fail when any host's checkout is dirty.
#' @param quiet Suppress the human-readable report.
#'
#' @return Invisibly, a list with `ok`, `n`, `mismatches`, `reference`,
#'   `offenders`, `problems` and `message`.
#'
#' @family preflight
#'
#' @export
#'
#' @examples
#' row <- function(host, ...) {
#'   d <- list(host = host, link_version = "0.46.0", link_sha = "NA",
#'             fresh_version = "0.33.0", fresh_sha = "NA",
#'             repo_sha = "abc123def456", repo_dirty = "FALSE",
#'             config_hash = "cfg012345678", fwapg_sha = "e6e1eb0aaaaa",
#'             r_version = "4.4.1")
#'   as.data.frame(utils::modifyList(d, list(...)), stringsAsFactors = FALSE)
#' }
#' agree <- rbind(row("m1"), row("cy-job1"))
#' lnk_preflight_parity(agree, n_expected = 2, quiet = TRUE)$ok
#'
#' drift <- rbind(row("m1"), row("cy-job1", fresh_version = "0.31.0"))
#' lnk_preflight_parity(drift, n_expected = 2, quiet = TRUE)$offenders
lnk_preflight_parity <- function(stamps,
                                 n_expected,
                                 keys = c("link_version", "fresh_version",
                                          "repo_sha", "config_hash",
                                          "fwapg_sha"),
                                 forbid_na = c("link_version", "fresh_version",
                                               "repo_sha", "fwapg_sha"),
                                 forbid_dirty = TRUE,
                                 quiet = FALSE) {
  stopifnot(
    is.data.frame(stamps),
    is.numeric(n_expected), length(n_expected) == 1L,
    !is.na(n_expected), n_expected >= 1L,
    is.character(keys), length(keys) >= 1L,
    is.character(forbid_na),
    is.logical(forbid_dirty), length(forbid_dirty) == 1L, !is.na(forbid_dirty),
    is.logical(quiet), length(quiet) == 1L, !is.na(quiet))

  need <- unique(c("host", keys, forbid_na, if (forbid_dirty) "repo_dirty"))
  absent <- setdiff(need, names(stamps))
  if (length(absent)) {
    stop("stamps is missing column(s): ", paste(absent, collapse = ", "),
         call. = FALSE)
  }

  problems <- character(0)

  # Checked first and unconditionally: a short or empty table is the one
  # failure that every other check would otherwise silently agree with.
  if (nrow(stamps) != n_expected) {
    problems <- c(problems, sprintf(
      "expected %d host stamp(s), got %d - a host did not report",
      as.integer(n_expected), nrow(stamps)))
  }

  for (k in intersect(forbid_na, names(stamps))) {
    bad <- stamps$host[stamps[[k]] %in% c("NA", "")]
    if (length(bad)) {
      problems <- c(problems, sprintf("%s unresolved on: %s", k,
                                      paste(bad, collapse = ", ")))
    }
  }

  if (forbid_dirty) {
    bad <- stamps$host[tolower(stamps$repo_dirty) %in% c("true", "1", "yes", "t")]
    if (length(bad)) {
      problems <- c(problems, sprintf("dirty checkout on: %s",
                                      paste(bad, collapse = ", ")))
    }
  }

  mismatches <- data.frame(host = character(0), field = character(0),
                           value = character(0), reference = character(0),
                           stringsAsFactors = FALSE)
  ref <- if (nrow(stamps)) stamps[1L, , drop = FALSE] else NULL
  if (!is.null(ref) && nrow(stamps) > 1L) {
    for (k in keys) {
      off <- which(stamps[[k]] != ref[[k]])
      if (length(off)) {
        mismatches <- rbind(mismatches, data.frame(
          host = stamps$host[off], field = k, value = stamps[[k]][off],
          reference = ref[[k]], stringsAsFactors = FALSE))
      }
    }
    if (nrow(mismatches)) {
      problems <- c(problems, sprintf("%d field mismatch(es) vs %s",
                                      nrow(mismatches), ref$host))
    }
  }

  out <- list(ok = length(problems) == 0L,
              n = nrow(stamps),
              mismatches = mismatches,
              reference = if (is.null(ref)) NA_character_ else ref$host,
              offenders = sort(unique(mismatches$host)),
              problems = problems,
              message = .lnk_parity_message(stamps, problems, mismatches))
  if (!quiet) message(out$message)
  invisible(out)
}


.lnk_parity_message <- function(stamps, problems, mismatches) {
  if (length(problems) == 0L) {
    return(sprintf("[preflight] host parity - OK across %d host(s): %s",
                   nrow(stamps), paste(stamps$host, collapse = ", ")))
  }
  lines <- c("[preflight] host parity - FAILED",
             paste0("  ", problems))
  if (nrow(mismatches)) {
    lines <- c(lines, sprintf("    %s: %s = %s (reference %s)",
                              mismatches$host, mismatches$field,
                              mismatches$value, mismatches$reference))
  }
  paste(lines, collapse = "\n")
}
