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

PRETEST_SPECIAL <- c("any", "none")
PRETEST_MAP_COLS <- c("repo", "pattern", "input", "why")
PRETEST_VERDICTS <- c("pass", "failed", "bound", "no_row")

# The functions wsg_run_one.R calls in link. The modelling path is everything
# they reach.
PRETEST_ENTRIES <- c("lnk_db_conn", "lnk_config", "lnk_load_overrides",
                     "lnk_pipeline_species", "lnk_wsg_downstream_check",
                     "lnk_pipeline_run", ".lnk_timeout_statement")

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
# (an empty diff would read as "nothing changed").
pretest_git <- function(dir, args) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(dir), args),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) {
    stop("git ", paste(args, collapse = " "), " in ", dir, " failed: ",
         paste(out, collapse = " "), call. = FALSE)
  }
  out
}

# Files changed in link between two commits: R/ and the config bundles in
# `chain`. `git diff a b` compares the two trees, which is the question: what
# code differs between the last run and this one.
pretest_changed_link <- function(repo, since, until, chain) {
  paths <- c("R/", file.path("inst/extdata/configs", chain, ""))
  f <- pretest_git(repo, c("diff", "--name-only", since, until, "--", paths))
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

# Files changed in fresh's R/ between two pins, read from a fresh checkout. A
# pin the checkout does not hold is an error: fetch its tags first.
pretest_changed_fresh <- function(fresh_repo, from, to) {
  if (identical(from, to)) {
    return(data.frame(repo = character(), path = character(), stringsAsFactors = FALSE))
  }
  for (ref in c(from, to)) {
    pretest_git(fresh_repo, c("rev-parse", "--verify", "--quiet", paste0(ref, "^{commit}")))
  }
  f <- pretest_git(fresh_repo, c("diff", "--name-only", from, to, "--", "R/"))
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

# One verdict per group. `exit` is the group's wsg_run_one.R exit status;
# `run_minutes` is its finished row in the scratch log (NA when none).
pretest_verdict <- function(exit, run_minutes, bound) {
  stopifnot(length(exit) == length(run_minutes), length(exit) == length(bound))
  ifelse(is.na(exit) | exit != 0L, "failed",
         ifelse(is.na(run_minutes), "no_row",
                ifelse(run_minutes > bound, "bound", "pass")))
}

# The gate passes only when every group passed. No group is not a pass.
pretest_overall <- function(verdicts) {
  if (length(verdicts) && all(verdicts == "pass")) "pass" else "fail"
}

# Files a package's modelling path reaches from `entries`, by the static call
# graph (codetools), following getFromNamespace("<name>", "<pkg>") calls too.
# `ns` is a loaded namespace with srcrefs (pkgload::load_all). Calls built at
# run time (do.call on a string, match.fun) are not seen, which is why a
# reached file is evidence and an unreached file only a check.
pretest_reach <- function(ns, entries) {
  fns <- Filter(function(n) is.function(get(n, ns)), ls(ns, all.names = TRUE))
  calls <- lapply(fns, function(n) {
    f <- get(n, ns)
    g <- intersect(codetools::findGlobals(f, merge = TRUE), fns)
    txt <- deparse(body(f))
    s <- regmatches(txt, gregexpr("getFromNamespace\\(\"[.A-Za-z0-9_]+\"", txt))
    s <- sub("getFromNamespace\\(\"([^\"]+)\"", "\\1", unlist(s))
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
  files <- vapply(seen, function(n) {
    s <- attr(get(n, ns), "srcref")
    if (is.null(s)) NA_character_ else basename(attr(s, "srcfile")$filename)
  }, "")
  sort(unique(stats::na.omit(files)))
}
