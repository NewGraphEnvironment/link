#' Does the installed 'fresh' provide what the pipeline calls?
#'
#' `link` calls `fresh::` in a dozen places with no `requireNamespace()`
#' guard, including a default argument on an exported function
#' ([lnk_wsg_downstream_check()], whose `outlets` defaults to
#' `fresh::frs_wsg_outlets()`). A `fresh` that is merely *present* is
#' therefore not enough — it has to export the symbols.
#'
#' On the cypher droplets the installed version is whatever was baked into
#' the machine image, and the failure mode is silent: `wsg_run_one.R`
#' catches the missing-symbol error and `quit(status = 1)`s, the bucket
#' loop logs `[WARN]` and continues, the host exits 0, and the watershed
#' groups are simply absent from the persist. Nothing downstream can tell
#' "not modelled" from "modelled empty". That is the 2026-08 failure this
#' exists to stop (link#246).
#'
#' Symbols are checked rather than a version string because a version is a
#' proxy that fails in both directions: it can read `0.33.0` on a partial
#' install or against a shadowing library path, and it can read "wrong"
#' while every needed symbol is present. Loading the namespace also
#' exercises `fresh`'s own `Imports` resolution, which reading a
#' `DESCRIPTION` off disk does not.
#'
#' @param required Character vector of `fresh` exports the pipeline cannot
#'   run without. Defaults to the curated list in `.lnk_fresh_required()`.
#' @param required_internal Character vector of non-exported `fresh`
#'   objects reached via [utils::getFromNamespace()].
#' @param min_version Minimum acceptable `fresh` version. Defaults to the
#'   floor declared in link's own `DESCRIPTION`, so the pin lives in one
#'   place.
#' @param quiet Suppress the human-readable report. The report is the
#'   point on a cypher, where the log is all the operator gets.
#'
#' @return Invisibly, a list with `ok`, `version`, `version_ok`,
#'   `missing`, `missing_internal` and `message`.
#'
#' @family preflight
#'
#' @export
#'
#' @examples
#' res <- lnk_preflight_fresh(quiet = TRUE)
#' res$ok
#' res$version
#'
#' # A symbol fresh does not export fails, and is named in the report:
#' bad <- lnk_preflight_fresh(required = "frs_not_a_real_export", quiet = TRUE)
#' bad$missing
lnk_preflight_fresh <- function(required = .lnk_fresh_required(),
                                required_internal = .lnk_fresh_required_internal(),
                                min_version = .lnk_fresh_floor(),
                                quiet = FALSE) {
  stopifnot(
    is.character(required), length(required) >= 1L, all(nzchar(required)),
    is.character(required_internal), all(nzchar(required_internal)),
    is.character(min_version), length(min_version) == 1L, nzchar(min_version),
    is.logical(quiet), length(quiet) == 1L, !is.na(quiet))

  version <- .lnk_pkg_version_or_na("fresh")
  ns <- .lnk_fresh_ns()

  if (is.null(ns)) {
    out <- list(ok = FALSE, version = NA_character_, version_ok = FALSE,
                missing = required, missing_internal = required_internal,
                message = "fresh is not installed or its namespace will not load")
  } else {
    missing <- setdiff(required, getNamespaceExports(ns))
    missing_internal <- required_internal[
      !vapply(required_internal, exists, logical(1),
              envir = ns, inherits = FALSE)]
    version_ok <- !is.na(version) &&
      utils::compareVersion(version, min_version) >= 0L
    out <- list(
      ok = length(missing) == 0L && length(missing_internal) == 0L && version_ok,
      version = version, version_ok = version_ok,
      missing = missing, missing_internal = missing_internal,
      message = .lnk_fresh_message(version, min_version, missing,
                                   missing_internal, version_ok))
  }

  if (!quiet) message(out$message)
  invisible(out)
}


# Namespace lookup behind its own function so the "fresh is absent" branch
# stays testable. Mocking `base::asNamespace` instead would break every
# other namespace lookup in the same test file, including testthat's own.
.lnk_fresh_ns <- function() {
  tryCatch(asNamespace("fresh"), error = function(e) NULL)
}

# The `fresh` exports link actually calls, curated rather than derived at
# runtime. Auto-deriving by grepping for `fresh::` over-fires: most matches
# in R/ are roxygen cross-references and ordinary comments, not call sites
# (measured 2026-08-30: 21 distinct symbols mentioned, 12 genuinely called).
# `.lnk_fresh_callsites()` below is the drift guard that keeps this honest.
.lnk_fresh_required <- function() {
  c("frs_break_apply", "frs_break_find", "frs_candidates_pick",
    "frs_col_generate", "frs_col_join", "frs_habitat_classify",
    "frs_habitat_overlay", "frs_network_features", "frs_order_child",
    "frs_params", "frs_wsg_drainage", "frs_wsg_outlets")
}

# Non-exported fresh objects link reaches via getFromNamespace().
# R/lnk_pipeline_connect.R:101.
.lnk_fresh_required_internal <- function() {
  ".frs_run_connectivity"
}

# Every `fresh::sym` / `fresh:::sym` reached from link's own namespace,
# discovered by walking parsed function bodies rather than reading R/.
#
# Walking the namespace works for an INSTALLED package, where R/ does not
# exist. A source-directory scan would silently find nothing there and
# report a clean drift check — the "guard that matches a container rather
# than the artifact" failure. This measures the code that will actually run.
.lnk_fresh_callsites <- function(pkg = "link") {
  ns <- asNamespace(pkg)
  found <- character(0)

  # A formal with no default is the empty symbol. It is a perfectly good
  # object to hold in a list, but passing it as an argument raises
  # "argument is missing, with no default" — so filter on identity before
  # recursing, never by trying to evaluate it.
  drop_empty <- function(xs) {
    xs[!vapply(xs, identical, logical(1), quote(expr = ))]
  }

  walk <- function(x) {
    if (is.call(x)) {
      fn <- x[[1L]]
      if (is.call(fn) && length(fn) == 3L && is.name(fn[[1L]]) &&
          as.character(fn[[1L]]) %in% c("::", ":::") &&
          identical(as.character(fn[[2L]]), "fresh")) {
        found <<- c(found, as.character(fn[[3L]]))
      }
    }
    if (is.call(x) || is.pairlist(x) || is.expression(x) || is.list(x)) {
      for (el in drop_empty(as.list(x))) walk(el)
    }
    invisible(NULL)
  }

  for (nm in ls(ns, all.names = TRUE)) {
    obj <- tryCatch(get(nm, envir = ns), error = function(e) NULL)
    if (!is.function(obj)) next
    walk(body(obj))
    walk(formals(obj))            # default args count: frs_wsg_outlets()
  }
  sort(unique(found))
}

# Single-source the version floor from link's own DESCRIPTION, so the pin
# cannot rot in a second place. Returns "0.0.0" when no floor is declared —
# a permissive default is correct here because the symbol check, not the
# version, is what this function is actually for.
.lnk_fresh_floor <- function(desc = utils::packageDescription("link")) {
  dep <- paste(c(desc$Imports, desc$Depends, desc$Suggests), collapse = ", ")
  if (!nzchar(dep)) return("0.0.0")
  m <- regmatches(dep, regexpr("fresh[[:space:]]*\\([[:space:]]*>=[^)]*\\)", dep))
  if (!length(m) || !nzchar(m)) return("0.0.0")
  v <- gsub("[^0-9.]", "", sub(".*>=", "", m))
  if (!nzchar(v)) "0.0.0" else v
}

.lnk_fresh_message <- function(version, min_version, missing,
                               missing_internal, version_ok) {
  head <- sprintf("fresh %s (floor %s)",
                  if (is.na(version)) "NOT INSTALLED" else version, min_version)
  if (length(missing) == 0L && length(missing_internal) == 0L && version_ok) {
    return(paste0("[preflight] ", head, " - OK, all required symbols present"))
  }
  parts <- character(0)
  if (!version_ok) {
    parts <- c(parts, sprintf("  version below the floor declared in link's DESCRIPTION"))
  }
  if (length(missing)) {
    parts <- c(parts, sprintf("  missing exports: %s",
                              paste(missing, collapse = ", ")))
  }
  if (length(missing_internal)) {
    parts <- c(parts, sprintf("  missing internals: %s",
                              paste(missing_internal, collapse = ", ")))
  }
  parts <- c(parts,
    "  fix: pak::pkg_install(\"NewGraphEnvironment/fresh@<ref>\") at or above the floor")
  paste(c(paste0("[preflight] ", head, " - FAILED"), parts), collapse = "\n")
}
