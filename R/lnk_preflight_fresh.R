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
#' @param required_internal_formals Named list mapping each non-exported
#'   `fresh` function link calls to its formal arguments, in order.
#'   Defaults to `.lnk_fresh_required_internal_formals()`. Order is checked
#'   here and not for exports because link calls three of the four
#'   internals positionally, so a reordered signature would bind its
#'   arguments to the wrong formals without an error, and because fresh
#'   promises nothing about an internal's arguments between releases. The
#'   installed function passes when the listed formals are its leading
#'   formals, in order, and every formal after them has a default: a later
#'   fresh that adds a trailing optional argument still passes.
#' @param required_formals Named list mapping a `fresh` function to the
#'   arguments link passes it that older releases lack. A symbol can be
#'   exported and still reject the call: `frs_habitat_classify()` existed
#'   long before it took `params_method`. Defaults to
#'   `.lnk_fresh_required_formals()`.
#' @param min_version Minimum acceptable `fresh` version. Defaults to the
#'   floor declared in link's own `DESCRIPTION`, so the pin lives in one
#'   place.
#' @param quiet Suppress the human-readable report. The report is the
#'   point on a cypher, where the log is all the operator gets.
#'
#' @return Invisibly, a list with `ok`, `version`, `version_ok`,
#'   `missing`, `missing_internal`, `missing_formals` (`"fn(arg)"`
#'   strings), `mismatched_internal_formals` (`"fn(want: a, b; have: a,
#'   c)"` strings) and `message`.
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
                                required_formals = .lnk_fresh_required_formals(),
                                required_internal_formals =
                                  .lnk_fresh_required_internal_formals(),
                                min_version = .lnk_fresh_floor(),
                                quiet = FALSE) {
  stopifnot(
    is.character(required), length(required) >= 1L, all(nzchar(required)),
    is.character(required_internal), all(nzchar(required_internal)),
    is.list(required_formals),
    length(required_formals) == 0L || !is.null(names(required_formals)),
    all(nzchar(names(required_formals))),
    is.list(required_internal_formals),
    length(required_internal_formals) == 0L ||
      !is.null(names(required_internal_formals)),
    all(nzchar(names(required_internal_formals))),
    all(vapply(required_internal_formals, is.character, logical(1))),
    is.character(min_version), length(min_version) == 1L, nzchar(min_version),
    is.logical(quiet), length(quiet) == 1L, !is.na(quiet))

  version <- .lnk_pkg_version_or_na("fresh")
  ns <- .lnk_fresh_ns()

  if (is.null(ns)) {
    out <- list(ok = FALSE, version = NA_character_, version_ok = FALSE,
                missing = required, missing_internal = required_internal,
                missing_formals = .lnk_fresh_formals_label(required_formals),
                mismatched_internal_formals = .lnk_fresh_internal_formals_label(
                  required_internal_formals, NULL),
                message = "fresh is not installed or its namespace will not load")
  } else {
    missing <- setdiff(required, getNamespaceExports(ns))
    missing_internal <- required_internal[
      !vapply(required_internal, exists, logical(1),
              envir = ns, inherits = FALSE)]
    missing_formals <- .lnk_fresh_missing_formals(ns, required_formals)
    mismatched_internal_formals <- .lnk_fresh_mismatched_internal_formals(
      ns, required_internal_formals)
    version_ok <- !is.na(version) &&
      utils::compareVersion(version, min_version) >= 0L
    out <- list(
      ok = length(missing) == 0L && length(missing_internal) == 0L &&
        length(missing_formals) == 0L &&
        length(mismatched_internal_formals) == 0L && version_ok,
      version = version, version_ok = version_ok,
      missing = missing, missing_internal = missing_internal,
      missing_formals = missing_formals,
      mismatched_internal_formals = mismatched_internal_formals,
      message = .lnk_fresh_message(version, min_version, missing,
                                   missing_internal, version_ok,
                                   missing_formals,
                                   mismatched_internal_formals))
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
  c("frs_aggregate", "frs_barriers_minimal", "frs_break_apply", "frs_break_find",
    "frs_candidates_pick",
    "frs_col_generate", "frs_col_join", "frs_db_conn",
    "frs_habitat_classify",
    "frs_habitat_overlay", "frs_habitat_predicates", "frs_network_features",
    "frs_order_child",
    "frs_params", "frs_point_snap", "frs_wsg_drainage", "frs_wsg_outlets")
}

# Arguments link passes that older fresh releases do not accept. The call
# would fail with "unused argument" only once a WSG reached that phase.
# R/lnk_pipeline_classify.R: params_method arrived in fresh 0.35.0 (#286);
# R/lnk_habitat_validate.R: frs_habitat_predicates(model) in the same
# release (#299), and frs_habitat_predicates(near_river_table) in 0.41.0
# (fresh#259), which the validator passes the persisted near-river table
# through (#364). 0.41.0 and 0.42.0 export the same formals; only the
# Imports floor tells the inheriting release apart. fresh 0.54.0 (fresh#293)
# made frs_habitat_predicates(near_river_lfid) required whenever
# near_river_table is given, keying the near-river join on linear_feature_id
# (#452).
# R/lnk_points_snap.R: frs_point_snap(to, col_id, col_geom, col_blk), the
# table form of fresh 0.40.0, and R/lnk_aggregate.R: frs_aggregate(where),
# which lnk_aggregate() refines the walk through (#478).
# R/lnk_db_conn.R: frs_db_conn(connect_timeout), the bound of fresh 0.55.0
# (fresh#305), which lnk_db_conn() passes through (#288).
# R/lnk_pipeline_classify.R: frs_order_child(channel_width_max, gradient_max),
# passed when a rear rule's bypass sets width_known_below_min (#326).
# R/lnk_pipeline_access.R: frs_network_features(result), the existence walk
# of fresh 0.47.0 (fresh#281), for every walk read only for membership (#394),
# and its "distinct" value of 0.48.0 (fresh#284) on the observation walk
# (#401). A new value of an existing argument is invisible to this check, so
# only the Imports floor guards it.
.lnk_fresh_required_formals <- function() {
  list(frs_db_conn = "connect_timeout",
       frs_habitat_classify = "params_method",
       frs_habitat_predicates = c("model", "near_river_table",
                                  "near_river_lfid"),
       frs_network_features = "result",
       frs_order_child = c("channel_width_max", "gradient_max"),
       frs_aggregate = c("where", "to"),
       frs_point_snap = c("to", "col_id", "col_geom", "col_blk"))
}

# "fn(arg)" for each required formal the namespace does not provide. A
# function that is itself absent reports every argument it was asked for;
# the missing export is reported separately.
.lnk_fresh_missing_formals <- function(ns, required_formals) {
  out <- character(0)
  for (fn in names(required_formals)) {
    obj <- if (exists(fn, envir = ns, inherits = FALSE)) {
      get(fn, envir = ns)
    }
    have <- if (is.function(obj)) names(formals(obj)) else character(0)
    gone <- setdiff(required_formals[[fn]], have)
    if (length(gone)) out <- c(out, sprintf("%s(%s)", fn, gone))
  }
  out
}

.lnk_fresh_formals_label <- function(required_formals) {
  out <- character(0)
  for (fn in names(required_formals)) {
    out <- c(out, sprintf("%s(%s)", fn, required_formals[[fn]]))
  }
  out
}

# Non-exported fresh functions link reaches via getFromNamespace(), each
# with its formals in order (#504). Measured identical at fresh v0.55.1,
# v0.56.0 and v0.57.0, and link passes every one of them:
# - .frs_run_connectivity in lnk_pipeline_connect(), by name.
# - .frs_habitat_models in .lnk_wsg_model() (R/lnk_config.R, #299),
#   positionally.
# - .frs_near_river_specs in .lnk_near_river_pairs() (R/lnk_discharge.R,
#   #364): fresh's own resolver of which near_river pairs a bundle's rules
#   read, so link never re-derives it; positionally.
# - .frs_sql_num in .lnk_near_river_pair_sets() (R/lnk_pipeline_persist.R),
#   the formatter fresh stores a pair's numbers with (#364); positionally,
#   through vapply().
# Positional calls make the order load-bearing, so the order is pinned.
# A change to this list is a change to fresh's contract test of these
# internals too (NewGraphEnvironment/fresh#329), which reads the same list.
# data-raw/query_habitat_thresholds_mad.R reaches a fifth internal,
# fresh:::.frs_rule_to_sql, off the run path and outside the namespace walk
# below, so it is not pinned here.
.lnk_fresh_required_internal_formals <- function() {
  list(
    .frs_run_connectivity = c("conn", "table", "habitat", "species",
                              "params", "params_fresh", "verbose"),
    .frs_habitat_models = c("wsg_codes", "params_method"),
    .frs_near_river_specs = c("params", "species", "models"),
    .frs_sql_num = "x")
}

.lnk_fresh_required_internal <- function() {
  names(.lnk_fresh_required_internal_formals())
}

# "fn(want: a, b; have: a, c)" for each internal whose installed formals do
# not begin with the declared ones in order, or whose formals after them lack
# a default. An internal that is absent reports nothing here: missing_internal
# names it. Run time is tolerant of a trailing optional formal because the
# floor is `>=` and this gates real launches; the test compares exactly.
.lnk_fresh_mismatched_internal_formals <- function(ns, required) {
  out <- character(0)
  for (fn in names(required)) {
    if (!exists(fn, envir = ns, inherits = FALSE)) next
    obj <- get(fn, envir = ns)
    want <- required[[fn]]
    if (!is.function(obj) || is.primitive(obj)) {
      out <- c(out, sprintf("%s(want: %s; have: not a closure)", fn,
                            paste(want, collapse = ", ")))
      next
    }
    fm <- formals(obj)
    have <- names(fm)
    extra <- fm[setdiff(seq_along(have), seq_along(want))]
    no_default <- vapply(extra, identical, logical(1), quote(expr = ))
    if (!identical(utils::head(have, length(want)), want) || any(no_default)) {
      out <- c(out, sprintf("%s(want: %s; have: %s)", fn,
                            paste(want, collapse = ", "),
                            paste(have, collapse = ", ")))
    }
  }
  out
}

.lnk_fresh_internal_formals_label <- function(required, have) {
  vapply(names(required), function(fn) {
    sprintf("%s(want: %s; have: %s)", fn,
            paste(required[[fn]], collapse = ", "),
            if (is.null(have)) "<absent>" else paste(have, collapse = ", "))
  }, character(1), USE.NAMES = FALSE)
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

# The fresh internals one function reaches through getFromNamespace(), read
# from its parsed body and formals (#504). A call is normalised with
# match.call() against utils::getFromNamespace, so a bare, `utils::` or
# `utils:::` head and positional or named arguments all read alike (as
# pretest_ns_calls() in data-raw/pretest.R reads them). A non-literal `ns`,
# or a non-literal `x` where `ns` is "fresh", is an error rather than a
# skip: a walker that passed over it would report a clean scan for code it
# could not read.
#
# Known limit: get(x, envir = asNamespace("fresh")), asNamespace("fresh")$x
# and getExportedValue() are not seen. A `fresh:::x` is caught by
# .lnk_fresh_callsites(), whose test requires every symbol it finds to be an
# export.
.lnk_fresh_internal_calls_in <- function(fun) {
  stopifnot(is.function(fun))
  found <- character(0)
  # The `:::` head is built with call(), since a literal one reads to
  # R CMD check as a `:::` call on utils.
  heads <- list(quote(getFromNamespace), quote(utils::getFromNamespace),
                call(":::", quote(utils), quote(getFromNamespace)))
  drop_empty <- function(xs) {
    xs[!vapply(xs, identical, logical(1), quote(expr = ))]
  }
  walk <- function(x) {
    if (is.call(x) &&
        any(vapply(heads, identical, logical(1), x[[1L]]))) {
      m <- match.call(utils::getFromNamespace, x)
      ns <- m[["ns"]]
      if (!is.null(ns)) {
        if (!(is.character(ns) && length(ns) == 1L)) {
          stop("getFromNamespace() with a non-literal `ns`: ",
               paste(deparse(x), collapse = " "), call. = FALSE)
        }
        if (identical(ns, "fresh")) {
          nm <- m[["x"]]
          if (!(is.character(nm) && length(nm) == 1L)) {
            stop("getFromNamespace() on fresh with a non-literal `x`: ",
                 paste(deparse(x), collapse = " "), call. = FALSE)
          }
          found <<- c(found, nm)
        }
      }
    }
    if (is.call(x) || is.pairlist(x) || is.expression(x) || is.list(x)) {
      for (el in drop_empty(as.list(x))) walk(el)
    }
    invisible(NULL)
  }
  walk(body(fun))
  walk(formals(fun))
  sort(unique(found))
}

# Every fresh internal link's own namespace reaches through
# getFromNamespace(); its test requires the set to equal
# .lnk_fresh_required_internal(), so an internal added or dropped without
# updating the pinned list fails.
.lnk_fresh_internal_callsites <- function(pkg = "link") {
  ns <- asNamespace(pkg)
  found <- character(0)
  for (nm in ls(ns, all.names = TRUE)) {
    obj <- tryCatch(get(nm, envir = ns), error = function(e) NULL)
    if (!is.function(obj)) next
    found <- c(found, .lnk_fresh_internal_calls_in(obj))
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
                               missing_internal, version_ok,
                               missing_formals = character(0),
                               mismatched_internal_formals = character(0)) {
  head <- sprintf("fresh %s (floor %s)",
                  if (is.na(version)) "NOT INSTALLED" else version, min_version)
  if (length(missing) == 0L && length(missing_internal) == 0L &&
      length(missing_formals) == 0L &&
      length(mismatched_internal_formals) == 0L && version_ok) {
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
  if (length(missing_formals)) {
    parts <- c(parts, sprintf("  missing arguments: %s",
                              paste(missing_formals, collapse = ", ")))
  }
  if (length(mismatched_internal_formals)) {
    parts <- c(parts, sprintf("  changed internal signatures: %s",
                              paste(mismatched_internal_formals,
                                    collapse = ", ")))
  }
  parts <- c(parts,
    "  fix: pak::pkg_install(\"NewGraphEnvironment/fresh@<ref>\") at or above the floor")
  paste(c(paste0("[preflight] ", head, " - FAILED"), parts), collapse = "\n")
}
