# data-raw/recompute_readers.R — the groups outside a partial run that read it
# (link#274). Sourced by data-raw/recompute_readers_check.R and by
# tests/testthat/test-recompute_readers.R. Sourcing defines functions and one
# constant, nothing else.
#
# A group's recompute (wsg_recompute_one.R) walks downstream through every
# group's barrier rows. A run rebuilds its own groups' rows, so a group the
# schema holds outside the run, whose walk reads a rebuilt group, keeps access
# computed against the old rows until something recomputes it. Which groups a
# walk reads is recompute_deps.R's line rule (complete by construction).
#
# One hop only: a recompute writes its own group's access, habitat and mapping
# codes, never barrier rows, so a reader's readers read nothing that moved.
#
# A reader is recomputed only when its last build matches what the recompute
# would run now (readers_classify); anything unknown refuses, because a
# recompute that reads wrongly cannot be undone (the habitat gate only clears).

# The files a recompute runs from or under: the package, its data and config
# bundles, the job script, the views it reads, and the two driver files that
# set its environment and prepare its views. A difference between a reader's
# link_sha and the working tree in any of them refuses the reader. A fixed
# list rather than data-raw/pretest_inputs.csv, which maps files to the inputs
# the pre-run gate models, not to what the recompute reaches.
READERS_PATHS <- c(
  "R/", "inst/extdata/", "DESCRIPTION", "NAMESPACE",
  "data-raw/wsg_recompute_one.R", "data-raw/barriers_views_build.R",
  "data-raw/study_area_run.sh", "data-raw/study_area_finish.sh"
)

.readers_wsg_ok <- function(x) is.character(x) && all(grepl("^[A-Z]{4}$", x))

# readers_outside(deps, run, rebuilt, held): the groups `held` by the schema,
# not in `run`, that read a group in `rebuilt` under the line rule. `run` is
# every group the run owns (its buckets with SKIPs, and any group with a log
# row of its run_uid), `rebuilt` the run groups whose rows it wrote or tried
# to (never a SKIP). Returns data.frame(wsg, reads), reads a sorted CSV of the
# rebuilt groups the reader reads; sorted by wsg.
readers_outside <- function(deps, run, rebuilt, held) {
  if (!is.data.frame(deps) || !identical(names(deps), c("wsg", "rule", "dep"))) {
    stop("deps must have columns wsg, rule, dep", call. = FALSE)
  }
  line <- deps[deps$rule == "line", , drop = FALSE]
  if (!.readers_wsg_ok(line$wsg) || !.readers_wsg_ok(line$dep)) {
    stop("deps holds a row that is not a pair of watershed group codes", call. = FALSE)
  }
  for (x in list(run, rebuilt, held)) {
    if (!is.character(x) || !.readers_wsg_ok(x)) {
      stop("run, rebuilt and held must be watershed group codes", call. = FALSE)
    }
  }
  if (!all(rebuilt %in% run)) stop("every rebuilt group must be in the run", call. = FALSE)
  hit <- line[line$dep %in% rebuilt & !line$wsg %in% run & line$wsg %in% held, , drop = FALSE]
  if (nrow(hit) == 0L) {
    return(data.frame(wsg = character(), reads = character()))
  }
  w <- sort(unique(hit$wsg), method = "radix")
  data.frame(
    wsg = w,
    reads = vapply(w, function(g) {
      paste(sort(unique(hit$dep[hit$wsg == g]), method = "radix"), collapse = ",")
    }, character(1), USE.NAMES = FALSE)
  )
}

# readers_classify(readers, missing, facts, expect, refuse_all): one row per
# reader, class `waiting` (it reads a run group in `missing`, coverage's
# unfinished classes), `refused` (a fact below fails, or `refuse_all` names a
# reason that holds for every reader), or `recompute`. Precedence is that
# order. `facts` has one row per group: has_log, open (newest log row has no
# date_end), config_hash, fresh_sha, fwapg_sha, link_dirty, fresh_dirty,
# link_sha, path_changed (files changed since link_sha on READERS_PATHS; NA
# when git cannot resolve the sha) and downstream (the dry-run status of the
# error-mode downstream check, "pass" to pass). `expect` is what the recompute
# would stamp now: config_hash, fresh_sha, fwapg_sha. Every refusal reason
# that holds is listed, `;`-separated. Returns data.frame(wsg, class, reason,
# reads).
readers_classify <- function(readers, missing, facts, expect, refuse_all = character()) {
  if (!is.data.frame(readers) || !identical(names(readers), c("wsg", "reads"))) {
    stop("readers must have columns wsg, reads", call. = FALSE)
  }
  need <- c("config_hash", "fresh_sha", "fwapg_sha")
  scalar_chr <- function(v) is.character(v) && length(v) == 1L
  if (!is.list(expect) || !all(need %in% names(expect)) ||
        !all(vapply(expect[need], scalar_chr, logical(1)))) {
    stop("expect must give config_hash, fresh_sha and fwapg_sha", call. = FALSE)
  }
  cols <- c("wsg", "has_log", "open", "config_hash", "fresh_sha", "fwapg_sha",
            "link_dirty", "fresh_dirty", "link_sha", "path_changed", "downstream")
  if (!is.data.frame(facts) || !all(cols %in% names(facts))) {
    stop("facts lacks a column: ", paste(setdiff(cols, names(facts)), collapse = ", "),
      call. = FALSE
    )
  }
  # A known value that matches; anything unknown fails the test.
  same <- function(a, b) !is.na(a) && !is.na(b) && identical(as.character(a), b)
  is_false <- function(x) !is.na(x) && identical(as.logical(x), FALSE)
  out <- lapply(seq_len(nrow(readers)), function(i) {
    g <- readers$wsg[i]
    reads <- strsplit(readers$reads[i], ",", fixed = TRUE)[[1]]
    unfinished <- intersect(reads, missing)
    if (length(unfinished)) {
      return(c(g, "waiting", paste0("reads_unfinished:", paste(unfinished, collapse = ","))))
    }
    why <- refuse_all
    f <- facts[facts$wsg == g, , drop = FALSE]
    if (nrow(f) != 1L || !isTRUE(as.logical(f$has_log))) {
      why <- c(why, "no_log")
    } else {
      if (!is_false(f$open)) why <- c(why, "newest_build_open")
      if (!same(f$config_hash, expect$config_hash)) why <- c(why, "config_differs")
      if (!same(f$fresh_sha, expect$fresh_sha)) why <- c(why, "fresh_differs")
      if (!same(f$fwapg_sha, expect$fwapg_sha)) why <- c(why, "fwapg_differs")
      if (!is_false(f$link_dirty)) why <- c(why, "link_dirty")
      if (!is_false(f$fresh_dirty)) why <- c(why, "fresh_dirty")
      pc <- suppressWarnings(as.integer(f$path_changed))
      if (is.na(pc)) {
        why <- c(why, "sha_unresolvable")
      } else if (pc > 0L) {
        why <- c(why, sprintf("path_changed:%d", pc))
      }
      if (!same(f$downstream, "pass")) why <- c(why, "downstream_unpersisted")
    }
    if (length(why)) c(g, "refused", paste(why, collapse = ";")) else c(g, "recompute", "")
  })
  if (length(out) == 0L) {
    return(data.frame(wsg = character(), class = character(), reason = character(),
                      reads = character()))
  }
  m <- do.call(rbind, out)
  data.frame(wsg = m[, 1], class = m[, 2], reason = m[, 3], reads = readers$reads)
}
