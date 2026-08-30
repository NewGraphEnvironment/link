#' One-line provenance stamp for cross-host pre-flight parity
#'
#' The parity payload in a fixed field order, drawn from the facts
#' [lnk_stamp()] already collects plus the git state of the checkout this
#' host installed from. Kept separate from [lnk_stamp()] so the shell
#' contract — the field order — is a documented, tested thing rather than
#' an inline `Rscript -e` incantation that drifts between two call sites.
#'
#' **`repo_sha` is the load-bearing field, not `link_sha`.**
#' `.lnk_pkg_git_sha()` resolves a SHA from a `.git` beside the installed
#' package. On the dispatcher link is `pkgload::load_all`'d from a checkout,
#' so it finds one; on every cypher link is pak-installed, so it does not
#' and returns `NA`. `fresh_sha` is `NA` on both unless pak recorded a
#' `RemoteSha`. Comparing `link_sha` across hosts would therefore always
#' fail, and comparing `fresh_sha` would be a vacuous `NA == NA` pass — a
#' check that looks like a check. `repo_sha` is read from
#' `~/Projects/repo/link` **on the host itself**, which on a cypher is
#' exactly what `git reset --hard origin/<branch>` produced. It is an
#' independent observation rather than a restatement of what the
#' dispatcher believes (link#246).
#'
#' Unresolvable facts are the literal string `"NA"`, never empty, so a
#' truncated ssh response is distinguishable from a resolved absence.
#'
#' @param cfg An `lnk_config` from [lnk_config()]. Supplies `config_hash`.
#' @param repo Path to the git checkout this host's install came from.
#'
#' @return A named character vector in the documented field order.
#'
#' @family preflight
#'
#' @export
#'
#' @examples
#' s <- lnk_preflight_stamp(lnk_config("bcfishpass"))
#' names(s)
#' s[["fresh_version"]]
lnk_preflight_stamp <- function(cfg = lnk_config("bcfishpass"), repo = ".") {
  stopifnot(is.character(repo), length(repo) == 1L, nzchar(repo))
  s <- lnk_stamp(cfg, conn = NULL, db_snapshot = FALSE)
  g <- .lnk_repo_git_state(repo)

  na <- function(x) {
    if (length(x) != 1L || is.na(x)) "NA" else as.character(x)
  }
  sh <- function(x) substr(na(x), 1L, 12L)

  c(host          = na(s$host),
    link_version  = na(s$software$link$version),
    link_sha      = sh(s$software$link$git_sha),
    fresh_version = na(s$software$fresh$version),
    fresh_sha     = sh(s$software$fresh$git_sha),
    repo_sha      = sh(g$sha),
    repo_dirty    = na(g$dirty),
    config_hash   = sh(s$config_hash),
    fwapg_sha     = sh(s$fwapg_sha),
    r_version     = na(getRversion()))
}

# The field order the shell's STAMP_COLS must match. Exposed as a function
# so the contract has exactly one definition and a test can assert it.
.lnk_preflight_stamp_cols <- function() {
  c("host", "link_version", "link_sha", "fresh_version", "fresh_sha",
    "repo_sha", "repo_dirty", "config_hash", "fwapg_sha", "r_version")
}

# git state of a working directory, as opposed to of an installed package.
# Returns NA for both fields when `repo` is not a git checkout, which the
# parity judge treats as a failure rather than as agreement.
.lnk_repo_git_state <- function(repo) {
  run <- function(args) {
    out <- tryCatch(
      suppressWarnings(system2("git", c("-C", repo, args),
                               stdout = TRUE, stderr = FALSE)),
      error = function(e) NULL)
    if (is.null(out)) return(NULL)
    st <- attr(out, "status")
    if (!is.null(st) && !identical(as.integer(st), 0L)) return(NULL)
    out
  }
  sha <- run(c("rev-parse", "HEAD"))
  if (is.null(sha) || !length(sha) || !nzchar(sha[1])) {
    return(list(sha = NA_character_, dirty = NA))
  }
  porcelain <- run(c("status", "--porcelain"))
  list(sha = sha[1],
       dirty = if (is.null(porcelain)) NA else length(porcelain) > 0L)
}
