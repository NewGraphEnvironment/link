# data-raw/pretest.R — the pre-run gate (link#372): which groups to model
# before a provincial run, and whether they passed. Sourced by pretest_pick.R,
# pretest_verdict.R and tests/testthat/test-pretest.R. Sourcing defines
# functions only.
#
# Why a gate, and why these groups. On 2026-10-23 a provincial run was the
# first contact between newly landed code and OKAN and KTSU, and the
# dispatcher lost about five hours to them while three cloud hosts idled. A
# rule's cost is driven by an input the test groups did not carry, so the gate
# picks groups by input, not from a fixed list:
#   1. the files changed since the last run, in link (R/ and the run's config
#      bundle, with what it extends) and in fresh (between the two DESCRIPTION
#      pins);
#   2. each file's inputs, from a tracked map (data-raw/pretest_inputs.csv);
#   3. for each input, the groups at its extreme (a query per input,
#      data-raw/pretest/<input>.sql), among groups the last run finished;
#   4. each picked group must finish within k times its last-run minutes.
#
# A changed file the map does not name refuses the gate: an unmapped file is
# a path nobody has said is cheap, and passing it would be the gate failing
# toward pass. Two inputs are not queries:
#   any   every pick exercises the file (logging, config loading); when no
#         query input is picked, the fastest group with history is.
#   none  the file is off the modelling path (validator, compare, export).
#         For link, test-pretest.R checks every `none` row against the static
#         call graph from wsg_run_one.R's entry points (pretest_reach()).
#   unexercised  on the run's path but not on what the gate runs: the
#         recompute, the consolidate, the habitat gate (a run models with
#         LNK_HABITAT_GATE=0 and settles in the recompute). It refuses
#         nothing, and the gate names it in pretest.md and in its record.
#
# A pass is recorded in <persist schema>.log_pretest, and study_area_run.sh's
# pre-flight reads it through pretest_record_check(): a record holds while
# every file changed since the SHA it modelled maps to none, so a version
# bump or a CITATION commit does not need a new gate.

PRETEST_SPECIAL <- c("any", "none", "unexercised")
PRETEST_MAP_COLS <- c("repo", "pattern", "input", "why")
PRETEST_VERDICTS <- c("pass", "failed", "bound", "no_row")

# The functions wsg_run_one.R calls in link must include these; the entries
# themselves are read from the script (pretest_entries()), so a call added
# there is on the path without anyone updating a list.
PRETEST_ENTRIES <- c("lnk_db_conn", "lnk_config", "lnk_load_overrides",
                     "lnk_pipeline_species", "lnk_wsg_downstream_check",
                     "lnk_pipeline_run", ".lnk_timeout_statement")

# The gate's own rules: what it reads to judge a change. A record is judged
# by these at HEAD, so a change to any of them since the record voids it.
# A pattern, not a list: a new gate script is covered without anyone adding it.
PRETEST_RULES <- c(":(glob)data-raw/pretest*", ":(glob)data-raw/pretest/**")


pretest_map_read <- function(path) {
  m <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = character(),
                       colClasses = "character")
  if (!identical(names(m), PRETEST_MAP_COLS)) {
    stop(path, ": columns must be ", paste(PRETEST_MAP_COLS, collapse = ","),
         call. = FALSE)
  }
  bad <- !m$repo %in% c("link", "fresh")
  if (any(bad)) stop(path, ": repo must be link or fresh (row ", which(bad)[1] + 1L, ")",
                     call. = FALSE)
  if (any(!nzchar(m$pattern) | !nzchar(m$input) | !nzchar(m$why))) {
    stop(path, ": every row needs a pattern, an input and a why", call. = FALSE)
  }
  # A pattern that does not compile would match nothing and leave its file
  # unmapped; say so here rather than at the first changed file.
  for (p in unique(m$pattern)) {
    ok <- tryCatch(is.logical(suppressWarnings(grepl(p, "x", perl = TRUE))),
                   error = function(e) FALSE)
    if (!ok) stop(path, ": pattern does not compile: ", p, call. = FALSE)
  }
  m
}

# The config bundle and every bundle it extends, nearest first.
pretest_config_chain <- function(configs_dir, name) {
  chain <- character()
  while (!is.null(name) && !is.na(name) && nzchar(name)) {
    if (name %in% chain) stop("config extends cycle at ", name, call. = FALSE)
    f <- file.path(configs_dir, name, "config.yaml")
    if (!file.exists(f)) stop("no config bundle ", name, " (", f, ")", call. = FALSE)
    chain <- c(chain, name)
    name <- yaml::read_yaml(f)$extends
  }
  chain
}

# git, returning stdout; any non-zero exit is an error, never an empty result
# (an empty diff would read as "nothing changed"). system2() pastes its
# arguments into a shell command, so each is quoted; stderr goes to a file, so
# a git warning never becomes a line of output (a path, or half a SHA).
pretest_git <- function(dir, args) {
  err <- tempfile()
  on.exit(unlink(err))
  out <- suppressWarnings(system2("git", shQuote(c("-C", dir, args)),
                                  stdout = TRUE, stderr = err))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) {
    stop("git ", paste(args, collapse = " "), " in ", dir, " failed: ",
         paste(c(out, readLines(err, warn = FALSE)), collapse = " "), call. = FALSE)
  }
  out
}

# What a run reads from link besides R/: the package data, DESCRIPTION, and
# the data-raw scripts a run executes.
PRETEST_LINK_PATHS <- c("R/", "inst/extdata/", "DESCRIPTION", "data-raw/wsg_run_one.R",
                        "data-raw/wsg_recompute_one.R", "data-raw/schema_consolidate.R",
                        "data-raw/study_area_run.sh")

# Files changed in link between two commits, under PRETEST_LINK_PATHS, less
# the config bundles outside `chain` (another bundle's change cannot reach
# this run). `git diff a b` compares the two trees, which is the question:
# what differs between the code that last ran and this code.
pretest_changed_link <- function(repo, since, until, chain) {
  f <- pretest_git(repo, c("diff", "--name-only", since, until, "--", PRETEST_LINK_PATHS))
  bundle <- ifelse(grepl("^inst/extdata/configs/[^/]+/", f),
                   sub("^inst/extdata/configs/([^/]+)/.*$", "\\1", f), NA_character_)
  f <- f[is.na(bundle) | bundle %in% chain]
  data.frame(repo = rep("link", length(f)), path = f, stringsAsFactors = FALSE)
}

# The fresh tag a DESCRIPTION pins in Remotes: (`NewGraphEnvironment/fresh@v0.44.0`).
pretest_fresh_pin <- function(desc_lines) {
  hit <- regmatches(desc_lines, regexpr("NewGraphEnvironment/fresh@[^ ,]+", desc_lines))
  hit <- unique(sub("^NewGraphEnvironment/fresh@", "", hit))
  if (length(hit) != 1L) {
    stop("DESCRIPTION pins fresh ", length(hit), " times (want 1): ",
         paste(hit, collapse = ", "), call. = FALSE)
  }
  hit
}

# Files changed in fresh's R/ and inst/extdata/ (link reads falls.csv, and
# frs_wsg_drainage() reads wsg_outlet.csv) between two pins, read from a fresh
# checkout. A pin the checkout does not hold is an error: fetch its tags first.
pretest_changed_fresh <- function(fresh_repo, from, to) {
  if (identical(from, to)) {
    return(data.frame(repo = character(), path = character(), stringsAsFactors = FALSE))
  }
  for (ref in c(from, to)) {
    pretest_git(fresh_repo, c("rev-parse", "--verify", "--quiet", paste0(ref, "^{commit}")))
  }
  f <- pretest_git(fresh_repo, c("diff", "--name-only", from, to, "--", "R/", "inst/extdata/"))
  data.frame(repo = rep("fresh", length(f)), path = f, stringsAsFactors = FALSE)
}

# Each changed file against the map. `{config}` in a pattern stands for any
# bundle in `chain`. Returns `hits` (repo, path, input, why; one row per file
# per input) and `unmapped` (repo, path).
pretest_match <- function(changed, map, chain = character()) {
  rows <- list()
  unmapped <- changed[0, c("repo", "path"), drop = FALSE]
  for (i in seq_len(nrow(changed))) {
    r <- changed$repo[i]
    p <- changed$path[i]
    m <- map[map$repo == r, , drop = FALSE]
    hit <- vapply(m$pattern, function(pat) {
      pats <- if (grepl("{config}", pat, fixed = TRUE)) {
        vapply(chain, function(cf) gsub("{config}", cf, pat, fixed = TRUE), "")
      } else {
        pat
      }
      any(vapply(pats, function(x) grepl(x, p, perl = TRUE), logical(1)))
    }, logical(1), USE.NAMES = FALSE)
    if (!any(hit)) {
      unmapped <- rbind(unmapped, data.frame(repo = r, path = p, stringsAsFactors = FALSE))
      next
    }
    rows[[length(rows) + 1L]] <- data.frame(repo = r, path = p, input = m$input[hit],
                                            why = m$why[hit], stringsAsFactors = FALSE)
  }
  hits <- if (length(rows)) do.call(rbind, rows) else
    data.frame(repo = character(), path = character(), input = character(),
               why = character(), stringsAsFactors = FALSE)
  list(hits = unique(hits), unmapped = unmapped)
}

# The inputs to query: every input the hits name except any and none, sorted.
pretest_inputs <- function(hits) {
  sort(setdiff(unique(hits$input), PRETEST_SPECIAL))
}

# The picks. `values` is a named list, one data frame (wsg, value) per input;
# `history` is (wsg, minutes, host), one row per group with a finished build.
# Each input takes its top `per_input` groups by value among groups with
# history (ties broken by group code, so a pick reproduces). When no query
# input is named and `any` is, the fastest group with history is the pick.
# Returns (wsg, input, value, rank), one row per group per input that picked it.
pretest_pick <- function(values, history, per_input = 2L, any = FALSE) {
  stopifnot(per_input >= 1L, !anyDuplicated(history$wsg))
  out <- list()
  for (inp in names(values)) {
    v <- values[[inp]]
    v <- v[v$wsg %in% history$wsg & !is.na(v$value), , drop = FALSE]
    if (!nrow(v)) stop("input ", inp, ": no group with history has a value", call. = FALSE)
    v <- v[order(-v$value, v$wsg), , drop = FALSE]
    v <- utils::head(v, per_input)
    out[[inp]] <- data.frame(wsg = v$wsg, input = inp, value = v$value,
                             rank = seq_len(nrow(v)), stringsAsFactors = FALSE)
  }
  if (!length(out) && any) {
    h <- history[!is.na(history$minutes), , drop = FALSE]
    h <- h[order(h$minutes, h$wsg), , drop = FALSE][1, ]
    out[["any"]] <- data.frame(wsg = h$wsg, input = "any", value = h$minutes, rank = 1L,
                               stringsAsFactors = FALSE)
  }
  if (!length(out)) {
    return(data.frame(wsg = character(), input = character(), value = numeric(),
                      rank = integer(), stringsAsFactors = FALSE))
  }
  r <- do.call(rbind, out)
  rownames(r) <- NULL
  r
}

# The groups to model, each once, with its history and bound, largest
# history first so a breach on a big group shows early.
pretest_groups <- function(picks, history, k = 3, floor_min = 5) {
  g <- unique(picks$wsg)
  h <- history[match(g, history$wsg), , drop = FALSE]
  inputs <- vapply(g, function(w) paste(sort(unique(picks$input[picks$wsg == w])), collapse = ","), "")
  out <- data.frame(wsg = g, inputs = unname(inputs), minutes = h$minutes, host = h$host,
                    bound = pretest_bound(h$minutes, k, floor_min), stringsAsFactors = FALSE)
  out[order(-out$minutes, out$wsg), , drop = FALSE]
}

# k times the group's last-run minutes, never below the floor. Minutes are
# whole-group (log date_start to date_end); a group with no history has no
# bound and must not have been picked.
pretest_bound <- function(minutes, k = 3, floor_min = 5) {
  stopifnot(k > 0, floor_min >= 0)
  if (anyNA(minutes)) stop("a picked group has no history minutes", call. = FALSE)
  pmax(k * minutes, floor_min)
}

# The statement bound for one group, in whole minutes: no statement outlasts
# its group, so a statement past the group's bound has already breached it.
pretest_statement_min <- function(bound, cap = 30) {
  as.integer(pmax(1, pmin(cap, ceiling(bound))))
}

# One verdict per group. `exit` is the group's wsg_run_one.R exit status
# (124: pretest_run.sh killed it at its wall-clock bound); `run_minutes` is
# its finished row in the scratch log (NA when none).
pretest_verdict <- function(exit, run_minutes, bound) {
  stopifnot(length(exit) == length(run_minutes), length(exit) == length(bound))
  v <- ifelse(is.na(exit) | exit != 0L, "failed",
              ifelse(is.na(run_minutes), "no_row",
                     ifelse(run_minutes > bound, "bound", "pass")))
  v[!is.na(exit) & exit == 124L] <- "bound"
  v
}

# The gate passes only when every group passed. No group is not a pass.
pretest_overall <- function(verdicts) {
  if (length(verdicts) && all(verdicts == "pass")) "pass" else "fail"
}

# The functions of package `pkg` a function names, read from its parsed body
# and formals (not from deparsed text, which wraps lines): `pkg::x`,
# `pkg:::x`, and `getFromNamespace("x", "pkg")` (a call with no namespace
# argument counts for any package, as within a package it names its own).
pretest_ns_calls <- function(f, pkg) {
  out <- character()
  # Elements are read by index and an empty one (`x[, 1]`, a formal with no
  # default) is skipped before it is bound: binding it is an error.
  walk_each <- function(x) {
    for (i in seq_along(x)) if (!identical(x[[i]], quote(expr = ))) walk(x[[i]])
  }
  walk <- function(x) {
    if (is.call(x)) {
      h <- x[[1]]
      if ((identical(h, as.name("::")) || identical(h, as.name(":::"))) &&
          identical(as.character(x[[2]]), pkg)) {
        out <<- c(out, as.character(x[[3]]))
      }
      if (identical(h, as.name("getFromNamespace")) ||
          (is.call(h) && length(h) == 3L && identical(as.character(h[[3]]), "getFromNamespace"))) {
        a <- as.list(x)[-1]
        nm <- if (!is.null(a[["x"]])) a[["x"]] else if (length(a)) a[[1]] else NULL
        where <- if (!is.null(a[["ns"]])) a[["ns"]] else if (length(a) >= 2L) a[[2]] else NULL
        if (is.character(nm) && (is.null(where) || identical(where, pkg))) out <<- c(out, nm)
      }
      walk_each(x)
    }
  }
  walk(body(f))
  walk_each(formals(f))
  unique(out)
}

# Files a package's modelling path reaches from `entries`, by the static call
# graph (codetools), following getFromNamespace("<name>", "<pkg>") calls too.
# `ns` is a loaded namespace with srcrefs (pkgload::load_all). Calls built at
# run time (do.call on a string, match.fun) are not seen, which is why a
# reached file is evidence and an unreached file only a check.
pretest_reach <- function(ns, entries, what = c("files", "functions")) {
  what <- match.arg(what)
  fns <- Filter(function(n) is.function(get(n, ns)), ls(ns, all.names = TRUE))
  pkg <- environmentName(ns)
  calls <- lapply(fns, function(n) {
    f <- get(n, ns)
    g <- intersect(codetools::findGlobals(f, merge = TRUE), fns)
    s <- pretest_ns_calls(f, pkg)
    unique(c(g, intersect(s, fns)))
  })
  names(calls) <- fns
  seen <- intersect(entries, fns)
  q <- seen
  while (length(q)) {
    x <- q[1]
    q <- q[-1]
    nw <- setdiff(calls[[x]], seen)
    seen <- c(seen, nw)
    q <- c(q, nw)
  }
  if (what == "functions") return(sort(seen))
  files <- vapply(seen, function(n) {
    s <- attr(get(n, ns), "srcref")
    if (is.null(s)) NA_character_ else basename(attr(s, "srcfile")$filename)
  }, "")
  sort(unique(stats::na.omit(files)))
}

# Changed link files mapped only `none` that the modelling path reaches at the
# code being checked (`reached`: basenames from pretest_reach()). The map's
# `none` is a claim test-pretest.R checks; this checks it where the gate and
# the driver run, so a call added into a `none` file voids that claim.
pretest_none_reached <- function(hits, reached, repo = "link") {
  if (is.null(reached) || !nrow(hits)) return(character())
  r <- hits[hits$repo == repo & grepl("^R/", hits$path), , drop = FALSE]
  only_none <- vapply(split(r$input, r$path), function(x) all(x == "none"), logical(1))
  p <- names(only_none)[only_none]
  p[basename(p) %in% reached]
}

# The SQL for each group's newest finished build under one config in a
# persist schema's log: the history a pick is bounded against, and the link
# SHAs it was built at. A schema can hold another config's builds (`default`'s
# YAML schema is `fresh`, which the bcfishpass bundle writes).
pretest_history_sql <- function(schema, config) {
  stopifnot(grepl("^[a-z_][a-z0-9_]*$", schema), grepl("^[a-z][a-z0-9_]*$", config))
  sprintf(
    "SELECT DISTINCT ON (watershed_group_code)
            watershed_group_code AS wsg, host, link_sha, link_dirty, date_start,
            extract(epoch FROM (date_end - date_start)) / 60 AS minutes
       FROM %s.log
      WHERE date_end IS NOT NULL AND date_start IS NOT NULL AND config_name = '%s'
      ORDER BY watershed_group_code, date_start DESC", schema, config)
}

# Where a bundle's history comes from. A bundle that extends another borrows
# (--history-schema, --history-config) from a config on its chain until its own builds
# cover every group it models: only then do they stand for what the gate must reach, so
# one build of its own, or a first run stopped partway, does not end the borrowing. A
# bundle with no parent has nothing to borrow and keeps its own history, whole or not.
# Returns list(schema, config, borrowed) or stops with the reason.
pretest_history_source <- function(schema, config, history_schema, history_config, chain, own_complete) {
  if (!nzchar(history_schema) && !nzchar(history_config)) {
    if (length(chain) > 1L && !own_complete) {
      stop(schema, ".log does not cover the groups ", config, " models; borrow from a config it extends: ",
           "--history-schema=<schema> --history-config=", chain[2], call. = FALSE)
    }
    return(list(schema = schema, config = config, borrowed = FALSE))
  }
  if (!nzchar(history_schema) || !nzchar(history_config)) {
    stop("--history-schema and --history-config go together", call. = FALSE)
  }
  if (!grepl("^[a-z_][a-z0-9_]*$", history_schema)) {
    stop("bad --history-schema '", history_schema, "'", call. = FALSE)
  }
  if (identical(history_config, config) || !history_config %in% chain) {
    stop("--history-config ", history_config, " is not a config ", config, " extends (chain: ",
         paste(chain, collapse = " < "), ")", call. = FALSE)
  }
  if (own_complete) {
    stop(schema, ".log covers every group ", config,
         " models: a gate must cover those builds, so leave out --history-schema and --history-config",
         call. = FALSE)
  }
  list(schema = history_schema, config = history_config, borrowed = TRUE)
}

# The history a record is held to, by the rule above: the schema's own builds when they
# stand, otherwise what the newest pass or fail record for the config borrowed, or NULL
# when it borrowed nothing. A record older than the borrow columns reads as none.
#
# A record taken with no history at all (range_source every_input, link#450) is held
# to none while the bundle still has no build of its own here (`own_n` finished
# groups): list(schema, config, every_input = TRUE). Once it has builds, those are
# what a gate must cover, and an every-input record cannot.
pretest_record_history <- function(records, schema, config, own_complete, chain, own_n = 1L) {
  r <- records[records$config_name == config & records$verdict %in% c("pass", "fail"), , drop = FALSE]
  newest <- if (nrow(r)) r[order(r$run_at, decreasing = TRUE), , drop = FALSE][1, ] else NULL
  if (own_n == 0L && !is.null(newest) && !is.null(newest$range_source) &&
      identical(newest$range_source, "every_input")) {
    return(list(schema = schema, config = config, every_input = TRUE))
  }
  if (own_complete || length(chain) == 1L) return(list(schema = schema, config = config))
  if (!nrow(r) || is.null(r$history_schema) || is.null(r$history_config)) return(NULL)
  rec <- newest
  if (is.na(rec$history_schema) || is.na(rec$history_config)) return(NULL)
  if (!rec$history_config %in% chain) return(NULL)
  list(schema = rec$history_schema, config = rec$history_config)
}

# Why no range can cover a history whatever it spans ("" when one can): a build with
# no link_sha, or whose tree was dirty or unknown, has no code to hold a diff against.
pretest_history_uncoverable <- function(history_shas, history_dirty) {
  stopifnot(length(history_dirty) == length(history_shas))
  if (anyNA(history_shas)) {
    return("history holds a build with no link_sha, which no range can be shown to cover")
  }
  if (any(is.na(history_dirty) | history_dirty)) {
    return("history holds a build from a dirty tree, whose code is not its link_sha")
  }
  ""
}

# Why a borrowed history cannot stand for a bundle ("" when it can). The gate picks
# only groups the history holds, so a history short of what the bundle models hides
# the extreme of an input: on 2026-11-01 a 4-group history picked exactly its 4.
pretest_history_complete <- function(wsgs, modelable) {
  length(wsgs) > 0L && !length(setdiff(modelable, wsgs))
}

pretest_history_short <- function(history_wsgs, modelable, source_name) {
  miss <- setdiff(modelable, history_wsgs)
  if (!length(miss)) return("")
  sprintf("%s holds %d of the %d groups the config models (missing %s%s), so the picks would not reach each input's extreme; load the full history (data-raw/pretest_history_load.sh), and for a group the parent never built, model it under the parent first or launch on --pretest-note",
          source_name, length(modelable) - length(miss), length(modelable),
          paste(utils::head(miss, 5), collapse = ", "), if (length(miss) > 5) ", ..." else "")
}

# Why a borrowing bundle's own builds so far keep a gate from clearing a run ("" when
# they do not). Said apart from the borrowed history, because re-loading that cannot
# help: the remedy is in the bundle's own log.
pretest_own_builds_why <- function(repo, since, end, own, schema) {
  if (!NROW(own)) return("")
  why <- pretest_since_covers(repo, since, end, own$link_sha, own$link_dirty)
  if (!nzchar(why)) return("")
  bad <- is.na(own$link_sha) | is.na(own$link_dirty) | own$link_dirty
  groups <- if (any(bad)) own$wsg[bad] else own$wsg
  sprintf("%s.log's own builds (%s%s): %s; re-model them clean at this code, or delete their rows",
          schema, paste(utils::head(groups, 5), collapse = ", "), if (length(groups) > 5) ", ..." else "", why)
}

# The groups a config models, from the source tree: a run's own list (lnk_wsg_resolve()).
pretest_modelable_groups <- function(repo, config) {
  suppressPackageStartupMessages(pkgload::load_all(repo, quiet = TRUE, helpers = FALSE))
  ns <- asNamespace("link")
  cfg <- get("lnk_config", ns)(config)
  get("lnk_wsg_resolve", ns)(cfg, get("lnk_load_overrides", ns)(cfg))
}

# The default --since: the link SHA of the earliest of the groups' newest
# finished builds. A group re-modelled by hand after a run keeps the run's
# SHA as the oldest, so the range covers every group's history.
pretest_since_default <- function(history) {
  h <- history[!is.na(history$link_sha), , drop = FALSE]
  if (!nrow(h)) stop("no history row carries a link_sha; pass --since=", call. = FALSE)
  if (any(is.na(h$link_dirty) | h$link_dirty)) {
    dirty <- h$wsg[is.na(h$link_dirty) | h$link_dirty]
    stop("history rows built from a dirty tree (", paste(dirty, collapse = ", "),
         "): their code is not a commit; pass --since=", call. = FALSE)
  }
  h$link_sha[order(h$date_start)][1]
}

# The link functions a script calls: every function-call symbol in it, kept
# when the namespace defines it. Must cover PRETEST_ENTRIES.
pretest_entries <- function(script, ns) {
  pd <- utils::getParseData(parse(script, keep.source = TRUE))
  calls <- unique(pd$text[pd$token == "SYMBOL_FUNCTION_CALL"])
  fns <- Filter(function(n) is.function(get(n, ns)), ls(ns, all.names = TRUE))
  e <- intersect(calls, fns)
  miss <- setdiff(PRETEST_ENTRIES, e)
  if (length(miss)) {
    stop(script, " no longer calls ", paste(miss, collapse = ", "),
         ": re-check PRETEST_ENTRIES and the map's none rows", call. = FALSE)
  }
  e
}

# The link files the modelling path reaches, loading the source tree at
# `repo`, from the calls in its wsg_run_one.R. A reach without the pipeline
# itself means the walk saw nothing: an error, never an empty answer.
pretest_reach_repo <- function(repo) {
  suppressPackageStartupMessages(pkgload::load_all(repo, quiet = TRUE, export_all = FALSE))
  ns <- asNamespace("link")
  if (is.null(attr(get("lnk_pipeline_run", ns), "srcref"))) {
    stop("link loaded without srcrefs; the reach cannot be read", call. = FALSE)
  }
  r <- pretest_reach(ns, pretest_entries(file.path(repo, "data-raw", "wsg_run_one.R"), ns))
  if (!all(c("lnk_pipeline_run.R", "lnk_pipeline_prepare.R") %in% r)) {
    stop("the modelling path's reach is missing the pipeline (", length(r), " files)", call. = FALSE)
  }
  r
}

# The fresh files link's modelling path reaches, at the fresh in `fresh_dir`
# (a checkout at the tag to judge): link's reach to the fresh functions it
# calls (fresh::, fresh:::, getFromNamespace("<name>", "fresh")), then fresh's
# graph from those. Loads both source trees.
pretest_reach_fresh <- function(repo, fresh_dir) {
  suppressPackageStartupMessages(pkgload::load_all(repo, quiet = TRUE))
  ln <- asNamespace("link")
  fns <- pretest_reach(ln, pretest_entries(file.path(repo, "data-raw", "wsg_run_one.R"), ln),
                       what = "functions")
  calls <- unique(unlist(lapply(fns, function(n) pretest_ns_calls(get(n, ln), "fresh"))))
  if (!length(calls)) stop("link's modelling path calls no fresh function: the walk saw nothing", call. = FALSE)
  suppressPackageStartupMessages(pkgload::load_all(fresh_dir, quiet = TRUE, export_all = TRUE,
                                                   attach = FALSE))
  # The source tree may be a temporary worktree: leave nothing loaded from it.
  on.exit(try(pkgload::unload("fresh", quiet = TRUE), silent = TRUE), add = TRUE)
  fr <- asNamespace("fresh")
  missing <- setdiff(calls, ls(fr, all.names = TRUE))
  if (length(missing)) stop("fresh at ", fresh_dir, " lacks ", paste(missing, collapse = ", "), call. = FALSE)
  r <- pretest_reach(fr, calls)
  if (!"frs_habitat_classify.R" %in% r) {
    stop("fresh's reach is missing frs_habitat_classify.R (", length(r), " files)", call. = FALSE)
  }
  r
}

# pretest_reach_fresh() at a tag of a fresh checkout, through a temporary
# worktree that is removed afterwards, whatever happens.
pretest_reach_fresh_at <- function(repo, fresh_repo, tag) {
  wt <- tempfile("fresh_")
  pretest_git(fresh_repo, c("worktree", "add", "--detach", wt, tag))
  tryCatch(pretest_reach_fresh(repo, wt),
           finally = try(pretest_git(fresh_repo, c("worktree", "remove", "--force", wt)), silent = TRUE))
}

# Is `a` an ancestor of, or equal to, `b`? FALSE also when either is unknown
# to the repo; only exit 1 means "not an ancestor", anything else is an error.
pretest_is_ancestor <- function(repo, a, b) {
  st <- suppressWarnings(system2("git", shQuote(c("-C", repo, "merge-base", "--is-ancestor", a, b)),
                                 stdout = FALSE, stderr = FALSE))
  if (identical(as.integer(st), 0L)) return(TRUE)
  if (identical(as.integer(st), 1L)) return(FALSE)
  stop("git merge-base --is-ancestor ", a, " ", b, " failed (", st, ")", call. = FALSE)
}

# The history a gate's range must hold: every build at or after `since` and at
# or before `end` (the code the gate picks for, or modelled), so its code is
# in the diff. A build off that line (an unmerged branch, a squash-merged
# one) is in no diff. Returns "" or the first reason it does not.
pretest_since_covers <- function(repo, since, end, history_shas, history_dirty) {
  bad <- pretest_history_uncoverable(history_shas, history_dirty)
  if (nzchar(bad)) return(bad)
  for (h in unique(history_shas)) {
    if (!pretest_is_ancestor(repo, since, h)) {
      return(sprintf("the range starts at %s, after history built at %s", substr(since, 1, 12),
                     substr(h, 1, 12)))
    }
    if (!pretest_is_ancestor(repo, h, end)) {
      return(sprintf("history built at %s is not on the line to %s, so its code is in no diff",
                     substr(h, 1, 12), substr(end, 1, 12)))
    }
  }
  ""
}

# Does a gate record clear a run? `records` is <schema>.log_pretest; the
# newest pass or fail row for the config decides (a later fail overrides an
# earlier pass; override rows are the run's, not the gate's). It holds when:
#   - it passed, on a clean tree;
#   - its fresh is the installed fresh (when it modelled anything);
#   - its range starts at or before every link SHA the history was built at,
#     so the picks were chosen from everything since the last run;
#   - every file changed between the SHA it modelled and HEAD maps to none,
#     and DESCRIPTION pins the same fresh at both (a pin bump is fresh's
#     change, which only a new gate can pick for).
# Returns list(ok, why, record).
pretest_record_check <- function(records, config, head_sha, fresh_sha, history_shas,
                                 history_dirty, repo, map, chain, reached = NULL,
                                 every_input = FALSE) {
  no <- function(...) list(ok = FALSE, why = paste0(...), record = rec)
  rec <- NULL
  r <- records[records$config_name == config & records$verdict %in% c("pass", "fail"), , drop = FALSE]
  if (!nrow(r)) return(no("no gate record for config ", config))
  rec <- r[order(r$run_at, decreasing = TRUE), , drop = FALSE][1, ]
  if (rec$verdict != "pass") return(no("the newest gate record failed: ", rec$notes))
  if (isTRUE(rec$link_dirty) || is.na(rec$link_dirty)) return(no("the gate ran on a dirty tree"))
  if (is.na(rec$fresh_sha)) return(no("the gate recorded no fresh SHA"))
  if (!identical(rec$fresh_sha, fresh_sha)) {
    return(no("the gate modelled fresh ", substr(rec$fresh_sha, 1, 12), ", installed is ",
              substr(fresh_sha, 1, 12)))
  }
  if (every_input) {
    # No history to hold a range to (link#450): the record must have picked on every
    # input rather than on a diff.
    if (!identical(rec$range_source, "every_input")) {
      return(no("no history under config ", config, ", and the newest gate record diffed a range"))
    }
  } else {
    if (!length(history_shas)) return(no("no history under config ", config, " to hold the gate's range to"))
    cover <- pretest_since_covers(repo, rec$since_sha, rec$link_sha, history_shas, history_dirty)
    if (nzchar(cover)) return(no("the gate's ", cover))
  }
  if (!pretest_is_ancestor(repo, rec$link_sha, head_sha)) {
    return(no("the gate modelled ", substr(rec$link_sha, 1, 12), ", not an ancestor of HEAD"))
  }
  rules <- pretest_git(repo, c("diff", "--name-only", rec$link_sha, head_sha, "--", PRETEST_RULES))
  if (length(rules)) {
    return(no("the gate's own rules changed since it ran: ", paste(rules, collapse = ", ")))
  }
  desc_pin <- function(ref) pretest_fresh_pin(pretest_git(repo, c("show", paste0(ref, ":DESCRIPTION"))))
  if (!identical(desc_pin(rec$link_sha), desc_pin(head_sha))) {
    return(no("DESCRIPTION pins fresh ", desc_pin(head_sha), ", the gate ran at ", desc_pin(rec$link_sha)))
  }
  ch <- pretest_changed_link(repo, rec$link_sha, head_sha, chain)
  m <- pretest_match(ch, map, chain)
  if (nrow(m$unmapped)) {
    return(no("changed since the gate and unmapped: ", paste(m$unmapped$path, collapse = ", ")))
  }
  moved <- unique(c(m$hits$path[m$hits$input != "none"], pretest_none_reached(m$hits, reached)))
  if (length(moved)) {
    return(no("changed since the gate, on the modelling path: ", paste(moved, collapse = ", ")))
  }
  list(ok = TRUE, why = "", record = rec)
}


# -- History found without flags, and minutes from a committed record (link#450) --

# Every query input the gate knows: one per data-raw/pretest/<input>.sql. With no
# history to diff against, every input counts as changed.
pretest_all_inputs <- function(script_dir) {
  f <- list.files(file.path(script_dir, "pretest"), pattern = "\\.sql$")
  sort(sub("\\.sql$", "", f))
}

# The schemas holding a link run log, which an ancestor's history is found among
# (pretest_history_count_sql() then counts each config's groups there). Scratch
# schemas (the gate's own, zz_ test schemas) are left out.
pretest_history_candidates_sql <- function() {
  # A link run log has config_name; other schemas' `log` tables (bcdata's) do not.
  "SELECT table_schema AS schema FROM information_schema.columns
    WHERE table_name = 'log' AND column_name = 'config_name'
      AND table_schema NOT LIKE 'fresh\\_pretest\\_%' AND table_schema NOT LIKE 'zz\\_%'
    ORDER BY 1"
}

pretest_history_count_sql <- function(schema, configs) {
  stopifnot(grepl("^[a-z_][a-z0-9_]*$", schema), all(grepl("^[a-z][a-z0-9_]*$", configs)))
  sprintf(
    "SELECT '%s'::text AS schema, config_name AS config,
            count(DISTINCT watershed_group_code)::integer AS n_groups, max(date_start) AS newest
       FROM %s.log
      WHERE date_end IS NOT NULL AND date_start IS NOT NULL AND config_name IN (%s)
      GROUP BY config_name", schema, schema, paste0("'", configs, "'", collapse = ", "))
}

# The ancestor history to hold a bundle to when no flag names one: the nearest config
# on its chain (after itself) with finished builds on this database, in the schema
# holding the most of its groups, then the newest. `candidates` is (schema, config,
# n_groups, newest). Returns list(schema, config, borrowed = TRUE), or NULL.
pretest_ancestor_pick <- function(candidates, chain) {
  if (length(chain) < 2L || !NROW(candidates)) return(NULL)
  # As plain numbers: a bigint count arrives as integer64, whose arithmetic without
  # bit64 attached orders on the raw bits (a 2-group test schema outranked 241 groups).
  candidates$n_groups <- as.numeric(as.character(candidates$n_groups))
  for (anc in chain[-1]) {
    c <- candidates[candidates$config == anc & candidates$n_groups > 0, , drop = FALSE]
    if (!nrow(c)) next
    c <- c[order(-c$n_groups, -as.numeric(c$newest), c$schema), , drop = FALSE]
    return(list(schema = c$schema[1], config = anc, borrowed = TRUE))
  }
  NULL
}

PRETEST_BUILD_MINUTES_COLS <- c("wsg", "config", "run_uid", "host", "host_class",
                                "link_sha", "fresh_sha", "date_start", "minutes")
PRETEST_FIXED_MIN <- 60

# The committed record of build minutes (data-raw/logs/build_minutes.csv), one row per
# group per config per run, appended after each provincial run by
# data-raw/build_minutes_append.R. An empty frame when absent.
pretest_build_minutes_read <- function(path) {
  if (!file.exists(path)) {
    return(stats::setNames(data.frame(matrix(character(), 0, length(PRETEST_BUILD_MINUTES_COLS))),
                           PRETEST_BUILD_MINUTES_COLS))
  }
  b <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character",
                       na.strings = "")
  if (!identical(names(b), PRETEST_BUILD_MINUTES_COLS)) {
    stop(path, ": columns must be ", paste(PRETEST_BUILD_MINUTES_COLS, collapse = ","), call. = FALSE)
  }
  b$minutes <- suppressWarnings(as.numeric(b$minutes))
  b$date_start <- as.POSIXct(b$date_start, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (anyNA(b$minutes) || any(b$minutes < 0) || anyNA(b$date_start) ||
      !all(grepl("^[A-Z]{4}$", b$wsg))) {
    stop(path, ": every row needs a group code, a date_start (YYYY-MM-DDTHH:MM:SSZ) and minutes >= 0",
         call. = FALSE)
  }
  b
}

# Each eligible group's last minutes, scaled to the gate host, and where they came from.
#   local   newest finished row in the history schema's log (wsg, host, date_start, minutes)
#   record  build_minutes rows; a group takes its newest row under the nearest config on
#           the chain that has one
# A local row wins unless the record holds a newer one; a group in neither takes
# PRETEST_FIXED_MIN, unscaled. `speed_of(host)` gives a host's speed (study_area_packing.R's
# learned factors; larger is faster) and `gate_speed` the speed of the host the gate runs
# on, so minutes measured on a host at speed s become minutes * s / gate_speed here.
# Groups in `exclude` take the median of the rest (a known stall). Returns
# (wsg, minutes, host, source), one row per group in `groups`.
pretest_minutes <- function(groups, local, record, chain, speed_of, gate_speed,
                            exclude = character(), fixed = PRETEST_FIXED_MIN) {
  out <- data.frame(wsg = groups, minutes = NA_real_, host = NA_character_,
                    source = NA_character_, stringsAsFactors = FALSE)
  rec <- record[record$config %in% chain & record$wsg %in% groups, , drop = FALSE]
  if (nrow(rec)) {
    rec$rank <- match(rec$config, chain)
    rec <- rec[order(rec$wsg, rec$rank, -as.numeric(rec$date_start)), , drop = FALSE]
    rec <- rec[!duplicated(rec$wsg), , drop = FALSE]
  }
  loc <- if (NROW(local)) local[local$wsg %in% groups & !is.na(local$minutes), , drop = FALSE] else NULL
  for (i in seq_along(groups)) {
    g <- groups[i]
    l <- if (!is.null(loc)) loc[loc$wsg == g, , drop = FALSE] else loc
    r <- if (nrow(rec)) rec[rec$wsg == g, , drop = FALSE] else rec
    use_r <- nrow(r) == 1L && (is.null(l) || !nrow(l) ||
                               as.numeric(r$date_start) > as.numeric(l$date_start[1]))
    if (use_r) {
      out[i, c("minutes", "host", "source")] <- list(r$minutes * speed_of(r$host) / gate_speed,
                                                     r$host, "record")
    } else if (!is.null(l) && nrow(l)) {
      out[i, c("minutes", "host", "source")] <- list(l$minutes[1] * speed_of(l$host[1]) / gate_speed,
                                                     l$host[1], "log")
    } else {
      out[i, c("minutes", "host", "source")] <- list(fixed, "fixed", "fixed")
    }
  }
  ex <- out$wsg %in% exclude
  if (any(ex)) {
    med <- stats::median(out$minutes[!ex & out$source != "fixed"])
    if (is.na(med)) med <- fixed
    out$minutes[ex] <- med
    out$host[ex] <- "median"
    out$source[ex] <- "median"
  }
  out
}
