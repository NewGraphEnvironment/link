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
