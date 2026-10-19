# data-raw/study_area_finish.sh: which groups have rows from this run, and the
# recompute and compare over those (link#348). The lib is bash, so each test
# runs it in a bash process against a scratch schema on the local docker
# fwapg, with the driver's own pool functions and an Rscript stub on PATH that
# records its calls instead of running anything.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the scripts are absent and
# these skip; devtools::test() from the source tree runs them.

# LNK_TEST_FINISH_LIB points the tests at a mutant copy (proving they fail).
finish_lib <- function() {
  p <- Sys.getenv(
    "LNK_TEST_FINISH_LIB",
    testthat::test_path("..", "..", "data-raw", "study_area_finish.sh")
  )
  normalizePath(p, mustWork = FALSE)
}
finish_hosts_lib <- function() {
  normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_hosts.sh"),
                mustWork = FALSE)
}
finish_driver <- function() {
  normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_run.sh"),
                mustWork = FALSE)
}

skip_if_no_finish_lib <- function() {
  testthat::skip_if_not(file.exists(finish_lib()), "data-raw/study_area_finish.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 4 found; the study_area_finish.sh tests cannot run")
  }
}

finish_uid <- "20261018_000000-0000abcd"

# A scratch persist schema: the log tables, and a streams table holding only
# what coverage reads. AAAA and BBBB finished this run; CCCC opened a log row
# this run and failed; DDDD holds an earlier run's rows; EEEE finished this
# run and its rows are gone (lost at consolidate).
finish_fixture <- function(conn, env = parent.frame(), streams = TRUE) {
  psql <- Sys.which("psql")
  testthat::skip_if(!nzchar(psql), "psql not on PATH")
  info <- DBI::dbGetInfo(conn)
  testthat::skip_if(!identical(as.character(info$port), "5432") ||
                      !info$host %in% c("localhost", "127.0.0.1"),
                    "not the local docker fwapg the lib reads")
  sc <- paste0("lnk_test_finish_", Sys.getpid(), if (streams) "" else "_nostreams")
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
  link:::.lnk_log_create_tables(conn, sc)
  withr::defer(
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc)),
    envir = env
  )
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end, run_uid)
     VALUES ('a', 'AAAA', '2026-10-18', '2026-10-18', '%s'),
            ('b', 'BBBB', '2026-10-18', '2026-10-18', '%s'),
            ('c', 'CCCC', '2026-10-18', NULL,         '%s'),
            ('d', 'DDDD', '2026-08-01', '2026-08-01', '20260801_000000-00000000'),
            ('e', 'EEEE', '2026-10-18', '2026-10-18', '%s')",
    sc, finish_uid, finish_uid, finish_uid, finish_uid))
  if (streams) {
    DBI::dbExecute(conn, sprintf(
      "CREATE TABLE %s.streams (watershed_group_code varchar(4) NOT NULL)", sc))
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO %s.streams VALUES ('AAAA'), ('AAAA'), ('BBBB'), ('DDDD'), ('FFFF')",
      sc))
  }
  sc
}

# A scratch world: an Rscript stub recording every call, and the dirs the
# driver writes logs and per-job files into.
finish_world <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  for (sub in c("bin", "logs")) dir.create(file.path(d, sub))
  p <- file.path(d, "bin", "Rscript")
  writeLines(c("#!/bin/sh", sprintf('echo "$*" >> "%s/rscript_calls"', d), "exit 0"), p)
  Sys.chmod(p, "755")
  d
}

rscript_calls <- function(world) {
  p <- file.path(world, "rscript_calls")
  if (file.exists(p)) readLines(p) else character(0)
}

# Run `body` with both libs sourced, the driver's pool functions extracted
# from it as pool_probe.sh does, and the driver's globals set.
run_finish_sh <- function(world, schema, body) {
  script <- file.path(world, "run.sh")
  drv <- shQuote(finish_driver())
  writeLines(c(
    "set -euo pipefail",
    sprintf("source %s", shQuote(finish_hosts_lib())),
    sprintf("source %s", shQuote(finish_lib())),
    sprintf("eval \"$(sed -n '/^csv_lines() {/p' %s)\"", drv),
    sprintf("eval \"$(sed -n '/^csv_count() {/p' %s)\"", drv),
    sprintf("eval \"$(awk '/^recompute_one\\(\\)/,/^}/' %s)\"", drv),
    sprintf("eval \"$(awk '/^recompute_order\\(\\)/,/^}/' %s)\"", drv),
    sprintf("eval \"$(awk '/^run_recompute_pool\\(\\)/,/^}/' %s)\"", drv),
    sprintf("SCHEMA=%s; RUN_UID=%s; CONFIG=default; TS=T0", schema, finish_uid),
    sprintf("LOG_DIR=%s; REPO_ROOT=%s; RECOMPUTE_JOBS=2",
            shQuote(file.path(world, "logs")), shQuote(world)),
    "RECOMPUTE_FAIL=0; RECOMPUTE_FAIL_STAGE=''; RUN_INCOMPLETE=0",
    body
  ), script)
  out <- withr::with_envvar(
    c(PATH = paste(file.path(world, "bin"), Sys.getenv("PATH"), sep = ":")),
    suppressWarnings(system2(hosts_bash(), script, stdout = TRUE, stderr = TRUE))
  )
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

# The value a `name=<csv>` line printed by a test body carries.
printed <- function(r, name) {
  m <- regmatches(r$out, regexpr(sprintf("%s=[A-Z,]*", name), r$out))
  if (length(m) == 0L) NA_character_ else sub("^[^=]*=", "", m)
}

cov_body <- function(expected, signals = "") {
  c(
    sprintf("run_coverage %s %s", shQuote(expected), shQuote(signals)),
    paste0("echo \"STATE=$COV_STATE\"; echo \"REC=$COV_RECOMPUTE\"; ",
           "echo \"NOROWS=$COV_NOROWS\"; echo \"STALE=$COV_STALE\"; ",
           "echo \"LOST=$COV_LOST\"; echo \"MISSING=$COV_MISSING\"")
  )
}

test_that("coverage splits the run's groups by what this run built", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, cov_body("AAAA,BBBB,CCCC,DDDD,EEEE,GGGG"))
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "REC"), "AAAA,BBBB")
  expect_identical(printed(r, "NOROWS"), "CCCC,GGGG")
  expect_identical(printed(r, "STALE"), "DDDD")
  expect_identical(printed(r, "LOST"), "EEEE")
  expect_identical(printed(r, "MISSING"), "CCCC,DDDD,EEEE,GGGG")
  # FFFF has rows and is not a run group: it is in no class.
  expect_false(grepl("FFFF", r$out))
})

test_that("a done signal admits a group with rows and no closed log row", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, cov_body("AAAA,DDDD", "DDDD"))
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "REC"), "AAAA,DDDD")
  expect_identical(printed(r, "MISSING"), "")
})

test_that("a persist with no streams table is unknown, never 'nothing has rows'", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn, streams = FALSE)
  w <- finish_world()
  r <- run_finish_sh(w, sc, c(
    "rc=0; run_coverage AAAA,CCCC '' || rc=$?",
    "echo \"RC=$rc STATE=$COV_STATE\"; echo \"NOROWS=$COV_NOROWS\""
  ))
  expect_match(r$out, "RC=1 STATE=unknown", fixed = TRUE)
  expect_identical(printed(r, "NOROWS"), "")
})

test_that("--recompute-only's expected set is every group with a log row for the run", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "echo \"EXP=$(run_expected_from_log)\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "EXP"), "AAAA,BBBB,CCCC,EEEE")
})

test_that("one missing group: the rest are recomputed and compared, and the run exits non-zero naming it", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "run_finish AAAA,BBBB,CCCC ''")
  expect_equal(r$status, 1L, info = r$out)
  calls <- rscript_calls(w)
  recomputed <- sort(sub(
    "^data-raw/wsg_recompute_one\\.R ([A-Z]{4}) default$", "\\1",
    grep("wsg_recompute_one", calls, value = TRUE)
  ))
  expect_identical(recomputed, c("AAAA", "BBBB"))
  compare <- grep("study_area_compare", calls, value = TRUE)
  expect_length(compare, 1L)
  expect_match(compare, " AAAA,BBBB default$")
  expect_match(r$out, "were NOT recomputed or compared: CCCC", fixed = TRUE)
  expect_match(r$out, "--recompute-only --run-uid=20261018_000000-0000abcd", fixed = TRUE)
  expect_match(r$out, "study_area_run INCOMPLETE", fixed = TRUE)
})

test_that("no group with rows from this run: no recompute, no compare, and it says why", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "run_finish CCCC,DDDD ''")
  expect_equal(r$status, 1L, info = r$out)
  calls <- rscript_calls(w)
  expect_length(grep("wsg_recompute_one|study_area_compare|barriers_views_build", calls), 0L)
  expect_match(r$out, "No run group has rows from a build this run finished", fixed = TRUE)
  expect_match(r$out, "no rows:                         CCCC", fixed = TRUE)
  expect_match(r$out, "an earlier run's or partial rows: DDDD", fixed = TRUE)
})

test_that("a complete run recomputes every group and exits 0", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "run_finish AAAA,BBBB ''")
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "study_area_run done", fixed = TRUE)
  expect_length(grep("wsg_recompute_one", rscript_calls(w)), 2L)
})

test_that("the driver refuses --run-uid / --wsgs without --recompute-only, and dispatch flags with it", {
  skip_if_no_finish_lib()
  run_drv <- function(...) {
    out <- suppressWarnings(system2(hosts_bash(), c(shQuote(finish_driver()), ...),
                                    stdout = TRUE, stderr = TRUE))
    list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
  }
  r <- run_drv(paste0("--run-uid=", finish_uid))
  expect_equal(r$status, 1L)
  expect_match(r$out, "--run-uid= is for --recompute-only", fixed = TRUE)
  r <- run_drv("--wsgs=AAAA")
  expect_equal(r$status, 1L)
  expect_match(r$out, "--wsgs= is for --recompute-only", fixed = TRUE)
  r <- run_drv("--recompute-only")
  expect_equal(r$status, 1L)
  expect_match(r$out, "needs --run-uid=", fixed = TRUE)
  r <- run_drv("--recompute-only", "--run-uid=20261018-bad")
  expect_equal(r$status, 1L)
  expect_match(r$out, "--run-uid= must look like", fixed = TRUE)
  r <- run_drv("--recompute-only", paste0("--run-uid=", finish_uid), "--focal=ADMS")
  expect_equal(r$status, 1L)
  expect_match(r$out, "--recompute-only takes no --focal", fixed = TRUE)
  r <- run_drv("--recompute-only", paste0("--run-uid=", finish_uid), "--wsgs=ADMS,bulk")
  expect_equal(r$status, 1L)
  expect_match(r$out, "--wsgs= takes comma-separated", fixed = TRUE)
})
