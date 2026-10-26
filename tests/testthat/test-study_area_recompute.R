# data-raw/study_area_recompute.sh: which groups may be recomputed while the
# legs are still running (link#374). The lib is bash, so each test runs it in
# a bash process against the stub world of helper-study_area_hosts.R, whose
# `psql` answers every local query from stub/psql_local.out: here, the
# dispatcher groups whose newest log row is this run's and closed.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the lib is absent and
# these skip; devtools::test() from the source tree runs them.
#
# LNK_TEST_RECOMPUTE_LIB points the tests at a mutant copy of the lib
# (proving they fail).

rc_uid <- "20261026_000000-aaaaaaaa"

rc_libs <- function() {
  p <- vapply(c("study_area_hosts.sh", "study_area_recompute.sh"), function(f) {
    normalizePath(testthat::test_path("..", "..", "data-raw", f), mustWork = FALSE)
  }, character(1))
  alt <- Sys.getenv("LNK_TEST_RECOMPUTE_LIB")
  if (nzchar(alt)) p[["study_area_recompute.sh"]] <- normalizePath(alt, mustWork = FALSE)
  p
}

skip_if_no_rc_lib <- function() {
  testthat::skip_if_not(all(file.exists(rc_libs())), "data-raw/study_area_*.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 5.1 found; the study_area_recompute.sh tests cannot run")
  }
}

# A run's group list: one row per (group, host), as run_wsgs_write writes it.
rc_wsgs <- function(world, rows, uid = rc_uid, header = NULL) {
  hdr <- header %||% "wsg\thost\tskip\trun_uid\tbucket_mode"
  writeLines(c(hdr, sprintf("%s\t%s\t%s\t%s\tclosure", rows$wsg, rows$host,
                            rows$skip, uid)),
             file.path(world, "logs", "T0_run_wsgs.tsv"))
}

rc_state <- function(world, rows, uid = rc_uid) {
  writeLines(c("wsg\tworkspace\tstate\trun_uid\tstate_utc",
               sprintf("%s\t%s\t%s\t%s\t2026-10-26T00:00:00Z", rows$wsg, rows$ws,
                       rows$state, uid)),
             file.path(world, "logs", "T0_consolidate_state.tsv"))
}

rc_deps <- function(world, pairs, rule = "line") {
  writeLines(c("wsg\trule\tdep", sprintf("%s\t%s\t%s", pairs$wsg, rule, pairs$dep)),
             file.path(world, "logs", "T0_recompute_deps.tsv"))
}

rc_run <- function(world, body) {
  script <- file.path(world, "run.sh")
  libs <- rc_libs()
  writeLines(c(
    "set -euo pipefail",
    sprintf("source %s", shQuote(libs[["study_area_hosts.sh"]])),
    sprintf("source %s", shQuote(libs[["study_area_recompute.sh"]])),
    sprintf("SCHEMA=fresh_t; RUN_UID=%s; L=%s", rc_uid, shQuote(file.path(world, "logs"))),
    body
  ), script)
  out <- withr::with_envvar(
    c(PATH = paste(file.path(world, "bin"), Sys.getenv("PATH"), sep = ":")),
    suppressWarnings(system2(hosts_bash(), script, stdout = TRUE, stderr = TRUE))
  )
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

# landed=<csv> rc=<n> from recompute_landed over the world's files.
rc_landed <- function(world) {
  r <- rc_run(world, c(
    'rc=0; x=$(recompute_landed "$L/T0_run_wsgs.tsv" "$L/T0_consolidate_state.tsv") || rc=$?',
    'echo "landed=$x"; echo "rc=$rc"'))
  list(landed = sub("^landed=", "", regmatches(r$out, regexpr("landed=[A-Z,]*", r$out))),
       rc = sub("^rc=", "", regmatches(r$out, regexpr("rc=[0-9]+", r$out))),
       out = r$out)
}

rc_ready <- function(world, landed, launched = "") {
  r <- rc_run(world, c(
    sprintf('rc=0; x=$(recompute_ready %s "$L/T0_recompute_deps.tsv" %s "$L/T0_run_wsgs.tsv") || rc=$?',
            shQuote(landed), shQuote(launched)),
    'echo "ready=$x"; echo "rc=$rc"'))
  list(ready = sub("^ready=", "", regmatches(r$out, regexpr("ready=[A-Z,]*", r$out))),
       rc = sub("^rc=", "", regmatches(r$out, regexpr("rc=[0-9]+", r$out))),
       out = r$out)
}

rows <- function(...) data.frame(..., stringsAsFactors = FALSE)

test_that("a dispatcher group lands when its newest log row is this run's and closed", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB"), host = "dispatcher", skip = "unknown"))
  put(w, "psql_local.out", db_answer("AAAA"))
  r <- rc_landed(w)
  expect_identical(r$rc, "0", info = r$out)
  expect_identical(r$landed, "AAAA")
})

test_that("a remote group lands only when its host's consolidate row is ok", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB", "CCCC", "DDDD"),
                  host = c("job1", "job1", "job2", "job3"), skip = "unknown"))
  put(w, "psql_local.out", db_answer(character(0)))
  rc_state(w, rows(wsg = c("AAAA", "BBBB", "CCCC", "DDDD"),
                   ws = c("job1", "job1", "job2", "job3"),
                   state = c("ok", "ok", "in_flight", "failed:copy")))
  r <- rc_landed(w)
  expect_identical(r$rc, "0", info = r$out)
  expect_identical(r$landed, "AAAA,BBBB")
})

test_that("no consolidate state file yet means no remote group has landed", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB"), host = c("dispatcher", "job1"), skip = "unknown"))
  put(w, "psql_local.out", db_answer("AAAA"))
  r <- rc_landed(w)
  expect_identical(r$rc, "0", info = r$out)
  expect_identical(r$landed, "AAAA")
})

test_that("a group on two hosts lands only when both have landed it", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "AAAA"), host = c("dispatcher", "job1"), skip = "unknown"))
  put(w, "psql_local.out", db_answer("AAAA"))
  r <- rc_landed(w)
  expect_identical(r$landed, "", info = r$out)
  rc_state(w, rows(wsg = "AAAA", ws = "job1", state = "ok"))
  r <- rc_landed(w)
  expect_identical(r$landed, "AAAA", info = r$out)
})

test_that("a SKIP lands without a log row", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB"), host = "dispatcher", skip = c("yes", "no")))
  put(w, "psql_local.out", db_answer(character(0)))
  r <- rc_landed(w)
  expect_identical(r$landed, "AAAA", info = r$out)
})

test_that("landing fails closed on an unknown answer", {
  skip_if_no_rc_lib()
  # A database that does not answer.
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "unknown"))
  put(w, "psql_local.out", "psql: error: connection refused")
  r <- rc_landed(w)
  expect_identical(r$rc, "1", info = r$out)
  expect_identical(r$landed, "")
  # A state row from another run.
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "job1", skip = "unknown"))
  put(w, "psql_local.out", db_answer(character(0)))
  rc_state(w, rows(wsg = "AAAA", ws = "job1", state = "ok"), uid = "20260101_000000-bbbbbbbb")
  r <- rc_landed(w)
  expect_identical(r$rc, "1", info = r$out)
  expect_identical(r$landed, "")
  # A group list that is not run_wsgs_write's.
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "unknown"), header = "wsg\thost")
  put(w, "psql_local.out", db_answer("AAAA"))
  r <- rc_landed(w)
  expect_identical(r$rc, "1", info = r$out)
  # A group list row from another run.
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "unknown"), uid = "20260101_000000-bbbbbbbb")
  put(w, "psql_local.out", db_answer("AAAA"))
  r <- rc_landed(w)
  expect_identical(r$rc, "1", info = r$out)
  # An unreadable state file.
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "job1", skip = "unknown"))
  put(w, "psql_local.out", db_answer(character(0)))
  rc_state(w, rows(wsg = "AAAA", ws = "job1", state = "ok"))
  Sys.chmod(file.path(w, "logs", "T0_consolidate_state.tsv"), "000")
  r <- rc_landed(w)
  Sys.chmod(file.path(w, "logs", "T0_consolidate_state.tsv"), "644")
  expect_identical(r$rc, "1", info = r$out)
})

test_that("a group is ready only when every dependency in the run has landed", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB", "CCCC", "DDDD"),
                  host = c("dispatcher", "dispatcher", "job1", "job1"), skip = "no"))
  # AAAA reads BBBB and ZZZZ (outside the run); BBBB reads CCCC; DDDD reads none.
  rc_deps(w, rows(wsg = c("AAAA", "AAAA", "BBBB"), dep = c("BBBB", "ZZZZ", "CCCC")))
  r <- rc_ready(w, "AAAA,BBBB,DDDD")
  expect_identical(r$rc, "0", info = r$out)
  # BBBB waits for CCCC; AAAA waits for BBBB's landing, which it has, so only
  # AAAA and DDDD; BBBB is not ready (CCCC has not landed).
  expect_identical(r$ready, "AAAA,DDDD")
  r <- rc_ready(w, "AAAA,BBBB,CCCC,DDDD", launched = "AAAA,DDDD")
  expect_identical(r$ready, "BBBB,CCCC")
})

test_that("only the line rule's rows count", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB"), host = "dispatcher", skip = "no"))
  writeLines(c("wsg\trule\tdep", "AAAA\tline\tBBBB", "BBBB\tclosure\tAAAA"),
             file.path(w, "logs", "T0_recompute_deps.tsv"))
  r <- rc_ready(w, "BBBB")
  expect_identical(r$ready, "BBBB", info = r$out)
})

test_that("a SKIP is never launched and never holds a dependant", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB"), host = "dispatcher", skip = c("no", "yes")))
  rc_deps(w, rows(wsg = "AAAA", dep = "BBBB"))
  r <- rc_ready(w, "AAAA")
  expect_identical(r$ready, "AAAA", info = r$out)
})

test_that("readiness fails closed on a bad dependency file", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "no"))
  writeLines(c("wsg\tdep", "AAAA\tBBBB"), file.path(w, "logs", "T0_recompute_deps.tsv"))
  r <- rc_ready(w, "AAAA")
  expect_identical(r$rc, "1", info = r$out)
  expect_identical(r$ready, "")
  rc_deps(w, rows(wsg = "AAAA", dep = "bad"))
  r <- rc_ready(w, "AAAA")
  expect_identical(r$rc, "1", info = r$out)
  expect_identical(r$ready, "")
  unlink(file.path(w, "logs", "T0_recompute_deps.tsv"))
  r <- rc_ready(w, "AAAA")
  expect_identical(r$rc, "1", info = r$out)
})

# --- recompute_scheduler -------------------------------------------------
# A stub recompute_one records its start and end and writes the .rc row as the
# driver's does; a stub recompute_order keeps the queue's order. RC_POLL=1.
rc_sched <- function(world, body, jobs = 2L, job_sleep = 1) {
  rc_run(world, c(
    sprintf('RC_DIR="$L/T0_recompute.d"; RC_DEPS="$L/T0_recompute_deps.tsv"; RC_FINAL="$L/T0_recompute_final"; RC_STOP="$L/T0_recompute_stop"'),
    'RUN_WSGS_TSV="$L/T0_run_wsgs.tsv"; CONS_STATE="$L/T0_consolidate_state.tsv"',
    sprintf("RECOMPUTE_JOBS=%d; RC_POLL=1; RC_PARENT=$$", jobs),
    sprintf(paste0("recompute_one() { echo \"start $1 $(date +%%s)\" >> \"$RC_DIR/calls\"; sleep %s; ",
                   "printf '%%s\\t0\\n' \"$1\" > \"$RC_DIR/$1.rc\"; ",
                   "echo \"end $1 $(date +%%s)\" >> \"$RC_DIR/calls\"; return 0; }"), job_sleep),
    "recompute_order() { .hosts_lines \"$1\"; }",
    # A scheduler that never ends fails its test instead of hanging it.
    'rc_wait() { local p="$1" r=0; ( sleep 20; kill "$p" 2>/dev/null ) & local wd=$!; wait "$p" || r=$?; kill "$wd" 2>/dev/null; return "$r"; }',
    body))
}

rc_launched <- function(world) {
  p <- file.path(world, "logs", "T0_recompute.d", "launched.tsv")
  if (!file.exists(p) || file.size(p) == 0) {
    return(data.frame(wsg = character(), mode = character()))
  }
  x <- utils::read.delim(p, header = FALSE, col.names = c("wsg", "at", "mode", "pid"),
                         colClasses = "character")
  # Every launch records the pid of its job (the fallback waits on it).
  expect_true(all(grepl("^[0-9]+$", x$pid)))
  x[, c("wsg", "mode")]
}

test_that("the scheduler starts ready groups early, then the final set, then returns 0", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB", "CCCC"), host = c("dispatcher", "dispatcher", "job1"),
                  skip = "no"))
  rc_deps(w, rows(wsg = "BBBB", dep = "CCCC"))
  put(w, "psql_local.out", db_answer(c("AAAA", "BBBB")))
  r <- rc_sched(w, c(
    "recompute_scheduler & sp=$!",
    "sleep 4",
    'cp "$RC_DIR/launched.tsv" "$L/early.tsv"',
    'recompute_final_write "AAAA,BBBB,CCCC"',
    'src=0; rc_wait "$sp" || src=$?; echo "sched_rc=$src"'))
  expect_match(r$out, "sched_rc=0", info = r$out)
  early <- utils::read.delim(file.path(w, "logs", "early.tsv"), header = FALSE)
  # BBBB reads CCCC, which has not landed: only AAAA starts early.
  expect_identical(early$V1, "AAAA")
  l <- rc_launched(w)
  expect_identical(sort(l$wsg), c("AAAA", "BBBB", "CCCC"))
  expect_identical(l$mode[l$wsg == "AAAA"], "early")
  expect_identical(l$mode[l$wsg != "AAAA"], c("final", "final"))
  expect_true(all(file.exists(file.path(w, "logs", "T0_recompute.d", paste0(l$wsg, ".rc")))))
})

test_that("the scheduler starts a group once its dependency's host is consolidated", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("BBBB", "CCCC"), host = c("dispatcher", "job1"), skip = "no"))
  rc_deps(w, rows(wsg = "BBBB", dep = "CCCC"))
  put(w, "psql_local.out", db_answer("BBBB"))
  r <- rc_sched(w, c(
    "recompute_scheduler & sp=$!",
    "sleep 3",
    'n0=$(wc -l < "$RC_DIR/launched.tsv" | tr -d " "); echo "n_before=$n0"',
    sprintf("printf 'wsg\\tworkspace\\tstate\\trun_uid\\tstate_utc\\nCCCC\\tjob1\\tok\\t%s\\tx\\n' > \"$CONS_STATE\"", rc_uid),
    "sleep 4",
    'recompute_final_write "BBBB,CCCC"',
    'rc_wait "$sp"'))
  expect_match(r$out, "n_before=0", info = r$out)
  l <- rc_launched(w)
  expect_identical(l$mode[l$wsg == "BBBB"], "early", info = r$out)
  expect_identical(l$mode[l$wsg == "CCCC"], "early")
})

test_that("the scheduler never runs more jobs than slots", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  g <- c("AAAA", "BBBB", "CCCC", "DDDD", "EEEE")
  rc_wsgs(w, rows(wsg = g, host = "dispatcher", skip = "no"))
  rc_deps(w, rows(wsg = character(), dep = character()))
  put(w, "psql_local.out", db_answer(g))
  r <- rc_sched(w, c(
    "recompute_scheduler & sp=$!",
    "sleep 2",
    sprintf('recompute_final_write "%s"', paste(g, collapse = ",")),
    'rc_wait "$sp"'), jobs = 2L, job_sleep = 2)
  calls <- readLines(file.path(w, "logs", "T0_recompute.d", "calls"))
  ev <- do.call(rbind, strsplit(calls, " "))
  t <- as.numeric(ev[, 3]); d <- ifelse(ev[, 1] == "start", 1, -1)
  o <- order(t, d)   # an end at the same second frees its slot first
  expect_lte(max(cumsum(d[o])), 2L)
  expect_setequal(rc_launched(w)$wsg, g)
})

test_that("a stop file ends the scheduler without starting anything new", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB"), host = "dispatcher", skip = "no"))
  rc_deps(w, rows(wsg = character(), dep = character()))
  put(w, "psql_local.out", db_answer(character(0)))
  r <- rc_sched(w, c(
    "recompute_scheduler & sp=$!",
    "sleep 2",
    'touch "$RC_STOP"',
    'src=0; rc_wait "$sp" || src=$?; echo "sched_rc=$src"'))
  expect_match(r$out, "sched_rc=2", info = r$out)
  expect_identical(nrow(rc_launched(w)), 0L)
})

test_that("the scheduler ends when the driver that started it is gone", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "no"))
  rc_deps(w, rows(wsg = character(), dep = character()))
  put(w, "psql_local.out", db_answer(character(0)))
  r <- rc_sched(w, c(
    "sleep 30 & parent=$!",
    "RC_PARENT=$parent",
    "recompute_scheduler & sp=$!",
    "sleep 2",
    'kill "$parent"',
    'src=0; rc_wait "$sp" || src=$?; echo "sched_rc=$src"'))
  expect_match(r$out, "sched_rc=3", info = r$out)
})

test_that("a poll that fails starts nothing", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "no"))
  rc_deps(w, rows(wsg = character(), dep = character()))
  put(w, "psql_local.out", "psql: error: connection refused")
  r <- rc_sched(w, c(
    "recompute_scheduler & sp=$!",
    "sleep 3",
    'touch "$RC_STOP"',
    'rc_wait "$sp" || true'))
  expect_identical(nrow(rc_launched(w)), 0L, info = r$out)
})

test_that("the final set starts a group whose dependency never landed", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  # CCCC failed on job1: it never lands and is not in the final set. BBBB,
  # which reads it, is recomputed anyway, as the end-of-run pool always has.
  rc_wsgs(w, rows(wsg = c("AAAA", "BBBB", "CCCC"), host = c("dispatcher", "dispatcher", "job1"),
                  skip = "no"))
  rc_deps(w, rows(wsg = "BBBB", dep = "CCCC"))
  put(w, "psql_local.out", db_answer(c("AAAA", "BBBB")))
  r <- rc_sched(w, c(
    "recompute_scheduler & sp=$!",
    "sleep 2",
    'recompute_final_write "AAAA,BBBB"',
    'src=0; rc_wait "$sp" || src=$?; echo "sched_rc=$src"'))
  expect_match(r$out, "sched_rc=0", info = r$out)
  l <- rc_launched(w)
  expect_setequal(l$wsg, c("AAAA", "BBBB"))
  expect_identical(l$mode[l$wsg == "BBBB"], "final")
})

# --- the driver's wiring (structural) ---------------------------------------
test_that("the driver prepares, starts, stops and finishes the early recompute in order", {
  drv_path <- testthat::test_path("..", "..", "data-raw", "study_area_run.sh")
  fin_path <- testthat::test_path("..", "..", "data-raw", "study_area_finish.sh")
  testthat::skip_if_not(file.exists(drv_path) && file.exists(fin_path),
                        "data-raw/study_area_*.sh absent")
  drv <- readLines(drv_path)
  fin <- readLines(fin_path)
  line <- function(x, pat) {
    i <- grep(pat, x, fixed = TRUE)
    expect_length(i, 1L)
    i[1]
  }
  # The flag, and --recompute-only turning it off.
  line(drv, "--recompute-at-end) RECOMPUTE_EARLY=0 ;;")
  line(drv, "  RECOMPUTE_EARLY=0")
  # Prep before the backup (a running pg_dump would make the view build wait),
  # the dependency map waited on before dispatch, the scheduler started after
  # CONS_STATE is set (it is a subshell) and before legs_wait.
  prep <- line(drv, "  recompute_views_prep")
  backup <- line(drv, '  echo "=== dispatcher persist ($SCHEMA): backup in the background ==="')
  expect_lt(prep, backup)
  deps_wait <- line(drv, '  drc=0; wait "$RC_DEPS_PID" || drc=$?')
  dispatch <- line(drv, 'echo "=== run buckets (DS-first) ==="')
  expect_lt(deps_wait, dispatch)
  cons <- grep('^CONS_STATE="\\$LOG_DIR/\\$\\{TS\\}_consolidate_state.tsv"$', drv)
  sched <- line(drv, '  recompute_scheduler > "$LOG_DIR/${TS}_recompute_scheduler.log" 2>&1 &')
  wait_legs <- grep("^legs_wait$", drv)
  expect_length(cons, 1L)
  expect_lt(cons, sched)
  expect_lt(sched, wait_legs)
  # The trap stops it starting anything new, before the burn.
  t <- grep("^on_exit\\(\\) \\{", drv)
  body <- drv[t:(t + which(drv[-seq_len(t)] == "}")[1])]
  expect_lt(grep('[ -z "${RC_SCHED_PID:-}" ] || touch "$RC_STOP"', body, fixed = TRUE),
            grep("burn_cyphers || rc=$?", body, fixed = TRUE))
  # run_finish hands over the final set, never rebuilds the views or clears
  # the per-job directory when the scheduler ran, and audits the early starts.
  r <- grep("^run_finish_recompute\\(\\) \\{", fin)
  rb <- fin[r:(r + which(fin[-seq_len(r)] == "}")[1])]
  early <- grep("run_finish_recompute_early", rb, fixed = TRUE)
  views <- grep("recompute_views_prep", rb, fixed = TRUE)
  wipe <- grep('rm -rf "$RC_DIR"; mkdir -p "$RC_DIR"', rb, fixed = TRUE)
  els <- grep("^  else$", rb)
  expect_length(early, 1L)
  expect_true(all(c(views, wipe) > els[1]))
  expect_length(grep('Rscript data-raw/recompute_audit.R "$SCHEMA" "$RUN_UID"', rb, fixed = TRUE), 1L)
  # The audit reads the scheduler's own launch record, so the per-job
  # directory goes only after it, and only when everything passed.
  audit <- grep('Rscript data-raw/recompute_audit.R "$SCHEMA" "$RUN_UID"', rb, fixed = TRUE)
  expect_length(grep('"$RC_DEPS" "$RUN_WSGS_TSV" "$CONS_STATE" "$RC_DIR/launched.tsv"', rb, fixed = TRUE), 1L)
  rm_dir <- grep('then rm -rf "$RC_DIR"; fi', rb, fixed = TRUE)
  expect_length(rm_dir, 1L)
  expect_lt(audit, rm_dir)
  e <- grep("^run_finish_recompute_early\\(\\) \\{", fin)
  eb <- fin[e:(e + which(fin[-seq_len(e)] == "}")[1])]
  expect_lt(grep('recompute_final_write "$ALL_WSGS"', eb, fixed = TRUE),
            grep('wait "$RC_SCHED_PID" || src=$?', eb, fixed = TRUE))
  # A dead scheduler's still-running jobs are waited for before the fallback
  # decides what is left, and every substitution there survives errexit.
  expect_lt(grep('while kill -0 "$pid" 2>/dev/null; do sleep 5; done', eb, fixed = TRUE),
            grep("done_rc=$(find", eb, fixed = TRUE))
  expect_length(grep("| tr -d ' ') || n_early=0", eb, fixed = TRUE), 1L)
  expect_length(grep('| cut -f1 | .hosts_csv) || done_rc=""', eb, fixed = TRUE), 1L)
  # An empty dependency map is refused before dispatch.
  expect_length(grep('&& [ "$(wc -l < "$RC_DEPS")" -gt 1 ]; }', drv, fixed = TRUE), 1L)
  # The empty-coverage branch releases the scheduler too.
  rf <- grep("^run_finish\\(\\) \\{", fin)
  fb <- fin[rf:(rf + which(fin[-seq_len(rf)] == "}")[1])]
  expect_length(grep('recompute_final_write "" || touch "$RC_STOP"', fb, fixed = TRUE), 1L)
})

test_that("the final set is acted on at once, not at the next poll", {
  skip_if_no_rc_lib()
  w <- hosts_world()
  rc_wsgs(w, rows(wsg = "AAAA", host = "dispatcher", skip = "no"))
  rc_deps(w, rows(wsg = character(), dep = character()))
  put(w, "psql_local.out", db_answer(character(0)))
  r <- rc_sched(w, c(
    "RC_POLL=30",
    "recompute_scheduler & sp=$!",
    "sleep 2",
    't0=$(date +%s); recompute_final_write "AAAA"',
    'rc_wait "$sp"',
    'echo "took=$(( $(date +%s) - t0 ))"'), job_sleep = 0)
  took <- as.integer(sub("took=", "", regmatches(r$out, regexpr("took=[0-9]+", r$out))))
  expect_lte(took, 5L)
  expect_identical(rc_launched(w)$wsg, "AAAA")
})
