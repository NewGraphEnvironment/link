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
finish_phases_lib <- function() {
  normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_phases.sh"),
                mustWork = FALSE)
}
finish_driver <- function() {
  normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_run.sh"),
                mustWork = FALSE)
}

skip_if_no_finish_lib <- function() {
  testthat::skip_if_not(file.exists(finish_lib()), "data-raw/study_area_finish.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 5.1 found; the study_area_finish.sh tests cannot run")
  }
}

finish_uid <- "20261018_000000-0000abcd"

# A scratch persist schema: the log tables, and a streams table holding only
# what coverage reads. AAAA and BBBB finished this run; CCCC opened a log row
# this run and failed; DDDD holds an earlier run's rows; EEEE finished this
# run and its rows are gone (lost at consolidate); HHHH finished this run and
# a later run rebuilt it; IIII finished this run, then a hand re-run under the
# same uid failed after its pre-persist.
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
  u <- finish_uid
  later <- "20261101_000000-0000beef"
  sql_log <- sprintf(paste(
    "INSERT INTO %s.log",
    "(run_id, watershed_group_code, date_start, date_end, run_uid, config_name)",
    "VALUES ('a', 'AAAA', '2026-10-18', '2026-10-18', '%s', 'default'),",
    "('b', 'BBBB', '2026-10-18', '2026-10-18', '%s', 'default'),",
    "('c', 'CCCC', '2026-10-18', NULL, '%s', 'default'),",
    "('d', 'DDDD', '2026-08-01', '2026-08-01', '20260801_000000-00000000', 'default'),",
    "('e', 'EEEE', '2026-10-18', '2026-10-18', '%s', 'default'),",
    "('h1', 'HHHH', '2026-10-18', '2026-10-18', '%s', 'default'),",
    "('h2', 'HHHH', '2026-11-01', '2026-11-01', '%s', 'default'),",
    "('i1', 'IIII', '2026-10-18', '2026-10-18', '%s', 'default'),",
    "('i2', 'IIII', '2026-10-19', NULL, '%s', 'default')"
  ), sc, u, u, u, u, u, later, u, u)
  DBI::dbExecute(conn, sql_log)
  if (streams) {
    DBI::dbExecute(conn, sprintf(
      "CREATE TABLE %s.streams (watershed_group_code varchar(4) NOT NULL)", sc
    ))
    DBI::dbExecute(conn, sprintf(paste(
      "INSERT INTO %s.streams VALUES",
      "('AAAA'), ('AAAA'), ('BBBB'), ('DDDD'), ('FFFF'), ('HHHH'), ('IIII')"
    ), sc))
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
    sprintf("source %s", shQuote(finish_phases_lib())),
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
  r <- run_finish_sh(w, sc, cov_body("AAAA,BBBB,CCCC,DDDD,EEEE,GGGG,HHHH,IIII"))
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "REC"), "AAAA,BBBB")
  expect_identical(printed(r, "NOROWS"), "CCCC,GGGG")
  # A group's NEWEST log row decides: HHHH was rebuilt by a later run, and
  # IIII's newest build under this uid never closed.
  expect_identical(printed(r, "STALE"), "DDDD,HHHH,IIII")
  expect_identical(printed(r, "LOST"), "EEEE")
  expect_identical(printed(r, "MISSING"), "CCCC,DDDD,EEEE,GGGG,HHHH,IIII")
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
  expect_identical(printed(r, "EXP"), "AAAA,BBBB,CCCC,EEEE,HHHH,IIII")
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
  expect_match(r$out, "LNK_GUARD_DOWNSTREAM=warn", fixed = TRUE)
  # The re-model gates nothing; the recompute settles on final access (#349).
  expect_match(r$out, "LNK_GUARD_DOWNSTREAM=warn LNK_HABITAT_GATE=0", fixed = TRUE)
  expect_match(r$out, "study_area_run INCOMPLETE", fixed = TRUE)
  cov <- utils::read.delim(file.path(w, "logs", "T0_coverage.tsv"), colClasses = "character")
  expect_identical(cov$class[order(cov$wsg)], c("recompute", "recompute", "no_rows"))
})

test_that("a missing group in a kept host's bucket defers to kept_hosts.tsv, the rest are re-modelled", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  # Host a is held: whatever its measured state, its groups are settled per
  # kept_hosts.tsv first. Host b was released, so its bucket is re-modelled.
  r <- run_finish_sh(w, sc, c(
    "HOST_ARR=(a b); HOST_BUCKET[a]=CCCC,DDDD; HOST_HOLD[a]=1",
    "HOST_BUCKET[b]=GGGG; HOST_HOLD[b]=0",
    "RUN_LABEL=prov-246",
    "run_finish AAAA,CCCC,DDDD,GGGG ''"
  ))
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "re-model only what is still missing: CCCC,DDDD", fixed = TRUE)
  expect_match(r$out, "Re-model each of these under this run_uid: GGGG", fixed = TRUE)
  expect_false(grepl("do NOT re-model", r$out, fixed = TRUE))
  expect_match(r$out, "LNK_RUN_LABEL=prov-246", fixed = TRUE)
  expect_match(r$out, "--run-label=prov-246 --wsgs=", fixed = TRUE)
})

test_that("--recompute-only lists the groups an earlier kept_hosts.tsv names apart", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, c(
    "HOST_ARR=(); KEPT_TSV_GROUPS=CCCC",
    "run_finish AAAA,CCCC,GGGG ''"
  ))
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "re-model only what is still missing: CCCC", fixed = TRUE)
  expect_match(r$out, "Re-model each of these under this run_uid: GGGG", fixed = TRUE)
})

test_that("a failed compare still reaches the report, which names the missing groups", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  writeLines(c(
    "#!/bin/sh", sprintf('echo "$*" >> "%s/rscript_calls"', w),
    'case "$*" in *study_area_compare*) exit 1 ;; esac', "exit 0"
  ), file.path(w, "bin", "Rscript"))
  r <- run_finish_sh(w, sc, "run_finish AAAA,BBBB,CCCC ''")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "compare failed", fixed = TRUE)
  expect_match(r$out, "LNK_RUN_UID=20261018_000000-0000abcd", fixed = TRUE)
  expect_match(r$out, "were NOT recomputed or compared: CCCC", fixed = TRUE)
})

test_that("--recompute-only refuses a config the run was not built with", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  ok <- run_finish_sh(w, sc, "run_config_check")
  expect_equal(ok$status, 0L, info = ok$out)
  bad <- run_finish_sh(w, sc, "CONFIG=bcfishpass; run_config_check")
  expect_equal(bad$status, 1L)
  expect_match(bad$out, "built with config 'default', not --config=bcfishpass", fixed = TRUE)
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET config_name = 'default_tuned' WHERE run_id = 'b'", sc
  ))
  mixed <- run_finish_sh(w, sc, "run_config_check")
  expect_equal(mixed$status, 1L)
  expect_match(mixed$out, "'default,default_tuned'", fixed = TRUE)
})

test_that("a full run expects every bucket less SKIPs no host finished, with every host's signals", {
  skip_if_no_finish_lib()
  w <- finish_world()
  r <- run_finish_sh(w, "unused", c(
    "DISP_BUCKET=AAAA,BBBB,SSSS; HOST_ARR=(a b)",
    "HOST_BUCKET[a]=CCCC,DDDD; HOST_BUCKET[b]=EEEE,TTTT",
    "ACC_FINISHED[dispatcher]=AAAA; ACC_DONE_LOG[dispatcher]=BBBB",
    "ACC_SKIP[dispatcher]=SSSS; ACC_SKIP[a]=EEEE; ACC_SKIP[b]=TTTT",
    "HOST_BUCKET_DONE[a]=CCCC; HOST_BUCKET_DONE[b]=EEEE",
    "run_expected_from_hosts",
    "echo \"EXP=$RUN_EXPECT\"; echo \"SIG=$RUN_SIGNALS\"; echo \"SKIP=$RUN_SKIP\""
  ))
  expect_equal(r$status, 0L, info = r$out)
  # EEEE was SKIPped by a, which does not run it, and finished by b: kept.
  expect_identical(printed(r, "EXP"), "AAAA,BBBB,CCCC,DDDD,EEEE")
  expect_identical(printed(r, "SIG"), "AAAA,BBBB,CCCC,EEEE")
  expect_identical(printed(r, "SKIP"), "SSSS,TTTT")
  expect_match(r$out, "WARN: SKIPped by a host", fixed = TRUE)
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

test_that("accounting short but coverage complete says so, and names no group to re-run", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "RUN_INCOMPLETE=1; run_finish AAAA,BBBB ''")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "did not cover its whole bucket", fixed = TRUE)
  expect_match(r$out, "recompute and the\n  compare above cover them all", info = r$out)
  expect_length(grep("wsg_recompute_one", rscript_calls(w)), 2L)
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

phase_rows <- function(w) {
  utils::read.delim(file.path(w, "logs", "T0_phases.tsv"), colClasses = "character",
                    quote = "", na.strings = character(), comment.char = "")
}

test_that("a complete run writes its tail's phase rows and prints them before the end (link#375)", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, c('phases_init "$LOG_DIR/T0_phases.tsv"', "run_finish AAAA,BBBB ''"))
  expect_equal(r$status, 0L, info = r$out)
  p <- phase_rows(w)
  expect_equal(p$phase, c("coverage", "views", "recompute", "compare"))
  expect_true(all(p$status == "ok"))
  expect_true(all(p$run_uid == finish_uid))
  expect_equal(p$groups, c("2", "", "2", "2"))
  expect_true(all(nzchar(p$start_utc) & nzchar(p$end_utc)))
  expect_match(r$out, "critical path: [0-9.]+ min")
  expect_lt(regexpr("critical path", r$out), regexpr("study_area_run done", r$out))
})

test_that("no group with rows from this run: coverage failed, the rest skipped, report before the exit (link#375)", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, c('phases_init "$LOG_DIR/T0_phases.tsv"', "run_finish CCCC,DDDD ''"))
  expect_equal(r$status, 1L, info = r$out)
  p <- phase_rows(w)
  expect_equal(p$phase, c("coverage", "views", "recompute", "compare"))
  expect_equal(p$status, c("failed", "skipped", "skipped", "skipped"))
  expect_equal(p$start_utc[2:4], c("", "", ""))
  expect_match(r$out, "phases (", fixed = TRUE)
  expect_lt(regexpr("phases (", r$out, fixed = TRUE),
            regexpr("study_area_run INCOMPLETE", r$out, fixed = TRUE))
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

# --- the run's groups, recorded when the buckets resolve (link#358) ---------

test_that("run_wsgs_write records every host's bucket, then each host's SKIPs once accounted", {
  skip_if_no_finish_lib()
  w <- finish_world()
  tsv <- file.path(w, "logs", "T0_run_wsgs.tsv")
  set_buckets <- c(
    "DISP_BUCKET=AAAA,SSSS; HOST_ARR=(job1 job2)",
    "HOST_BUCKET[job1]=CCCC,DDDD; HOST_BUCKET[job2]=DDDD,EEEE"
  )
  r <- run_finish_sh(w, "unused", c(set_buckets, sprintf("run_wsgs_write %s", shQuote(tsv))))
  expect_equal(r$status, 0L, info = r$out)
  x <- utils::read.delim(tsv, colClasses = "character")
  expect_identical(names(x), c("wsg", "host", "skip", "run_uid", "bucket_mode"))
  # DDDD is in two buckets: one row per host, as dispatched.
  expect_identical(paste(x$host, x$wsg), c(
    "dispatcher AAAA", "dispatcher SSSS", "job1 CCCC", "job1 DDDD", "job2 DDDD", "job2 EEEE"
  ))
  expect_true(all(x$skip == "unknown"))
  expect_true(all(x$run_uid == finish_uid))
  # The bucket mode (link#361) defaults to closure and follows BUCKET_MODE.
  expect_true(all(x$bucket_mode == "closure"))
  r <- run_finish_sh(w, "unused", c(set_buckets, "BUCKET_MODE=exact",
                                    sprintf("run_wsgs_write %s", shQuote(tsv))))
  expect_equal(r$status, 0L, info = r$out)
  expect_true(all(utils::read.delim(tsv, colClasses = "character")$bucket_mode == "exact"))

  # After accounting: a host's SKIPs are yes, the rest no; a host whose
  # accounting never ran stays unknown.
  r <- run_finish_sh(w, "unused", c(
    set_buckets,
    "ACC_SKIP[dispatcher]=SSSS; ACC_SKIP[job1]=''",
    sprintf("run_wsgs_write %s", shQuote(tsv))
  ))
  expect_equal(r$status, 0L, info = r$out)
  x <- utils::read.delim(tsv, colClasses = "character")
  expect_identical(x$skip, c("no", "yes", "no", "no", "unknown", "unknown"))
})

test_that("run_expected_from_file reads the run's groups less SKIPs, and refuses another run's file", {
  skip_if_no_finish_lib()
  w <- finish_world()
  tsv <- file.path(w, "logs", "T0_run_wsgs.tsv")
  rows <- function(uid = finish_uid, first = "AAAA") {
    c(
      "wsg\thost\tskip\trun_uid",
      sprintf("%s\tdispatcher\tno\t%s", first, uid),
      sprintf("SSSS\tdispatcher\tyes\t%s", uid),
      sprintf("DDDD\tjob1\tunknown\t%s", uid),
      sprintf("DDDD\tjob2\tyes\t%s", uid),
      sprintf("TTTT\tjob2\tyes\t%s", uid)
    )
  }
  read_it <- function() {
    run_finish_sh(w, "unused", sprintf(
      "rc=0; EXP=$(run_expected_from_file %s) || rc=$?; echo \"EXP=$EXP\"; echo \"RC=$rc\"",
      shQuote(tsv)
    ))
  }
  writeLines(rows(), tsv)
  r <- read_it()
  # SSSS and TTTT were SKIPped wherever they ran; DDDD was not, by job1.
  expect_identical(printed(r, "EXP"), "AAAA,DDDD")
  expect_match(r$out, "RC=0", fixed = TRUE)

  # The five-column file link#361 writes (bucket_mode appended) reads the same.
  writeLines(c(paste0(rows()[1], "\tbucket_mode"), paste0(rows()[-1], "\texact")), tsv)
  r <- read_it()
  expect_identical(printed(r, "EXP"), "AAAA,DDDD")
  expect_match(r$out, "RC=0", fixed = TRUE)

  writeLines(rows(uid = "20261101_000000-0000beef"), tsv)
  r <- read_it()
  expect_match(r$out, "RC=1", fixed = TRUE)
  expect_match(r$out, "another run_uid", fixed = TRUE)

  # A value that is not a group code never reaches the SQL coverage builds.
  writeLines(rows(first = "AA'A"), tsv)
  expect_match(read_it()$out, "RC=1", fixed = TRUE)

  writeLines(c("wsg\thost", "AAAA\tdispatcher"), tsv)
  expect_match(read_it()$out, "RC=1", fixed = TRUE)

  unlink(tsv)
  r <- read_it()
  expect_match(r$out, "RC=2", fixed = TRUE)
  expect_identical(printed(r, "EXP"), "")
})

ro_file <- function(w) file.path(w, "logs", "20261018_000000_run_wsgs.tsv")

test_that("--recompute-only names a group that failed on a cloud host, from the run's run_wsgs.tsv", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  # GGGG ran on job1 and failed there: no log row on the dispatcher, no rows.
  writeLines(c(
    "wsg\thost\tskip\trun_uid",
    sprintf("AAAA\tdispatcher\tno\t%s", finish_uid),
    sprintf("BBBB\tdispatcher\tno\t%s", finish_uid),
    sprintf("GGGG\tjob1\tunknown\t%s", finish_uid)
  ), ro_file(w))
  r <- run_finish_sh(w, sc, c(
    "run_expected_recompute_only ''; echo \"EXP=$RO_EXPECT\"",
    "run_finish \"$RO_EXPECT\" ''"
  ))
  expect_equal(r$status, 1L, info = r$out)
  # The file, and every group with a log row for the run (nothing dropped).
  expect_identical(printed(r, "EXP"), "AAAA,BBBB,CCCC,EEEE,GGGG,HHHH,IIII")
  expect_match(r$out, "the 3 in ", fixed = TRUE)
  expect_match(r$out, "4 more with a", fixed = TRUE)
  expect_match(r$out, "no rows:                         CCCC,GGGG", fixed = TRUE)
  expect_match(r$out, "Re-model each of these under this run_uid: CCCC,EEEE,GGGG,HHHH,IIII",
               fixed = TRUE)
})

test_that("--recompute-only falls back to the log for a run with no run_wsgs.tsv, and --wsgs= wins", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "run_expected_recompute_only ''; echo \"EXP=$RO_EXPECT\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "EXP"), "AAAA,BBBB,CCCC,EEEE,HHHH,IIII")
  expect_match(r$out, "pass the run's groups with --wsgs=", fixed = TRUE)

  writeLines(c("wsg\thost\tskip\trun_uid",
               sprintf("GGGG\tjob1\tno\t%s", finish_uid)), ro_file(w))
  r <- run_finish_sh(w, sc, "run_expected_recompute_only AAAA,BBBB; echo \"EXP=$RO_EXPECT\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "EXP"), "AAAA,BBBB")
  # Left out: the log's other groups and the file's GGGG.
  expect_match(r$out, "leave(s)? out 5 group", info = r$out)
  expect_match(r$out, "CCCC,EEEE,GGGG,HHHH,IIII", fixed = TRUE)

  # Another run's file stops a bare --recompute-only, and only warns beside --wsgs=.
  writeLines(c("wsg\thost\tskip\trun_uid",
               "GGGG\tjob1\tno\t20261101_000000-0000beef"), ro_file(w))
  r <- run_finish_sh(w, sc, "run_expected_recompute_only ''")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "FATAL", fixed = TRUE)
  r <- run_finish_sh(w, sc, "run_expected_recompute_only AAAA; echo \"EXP=$RO_EXPECT\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "EXP"), "AAAA")
})

# --- a consolidate that refuses one source (link#358) -----------------------

cons_tsv <- function(w, rows) {
  p <- file.path(w, "logs", "T0_consolidate.tsv")
  writeLines(c("host\tok\tstage\tgroups", rows), p)
  p
}

cons_setup <- c(
  "HOST_ARR=(a b c); CY_IP[a]=ip-a; CY_IP[b]=ip-b; CY_IP[c]=ip-c; HOST_SSH[a]=cypher@ip-a; HOST_SSH[b]=cypher@ip-b; HOST_SSH[c]=cypher@ip-c",
  "HOST_BUCKET[a]=CCCC,DDDD; HOST_BUCKET[b]=EEEE; HOST_BUCKET[c]=FFFF",
  # c reported nothing, so it was never a source.
  "HOST_BUCKET_DONE[a]=CCCC,DDDD; HOST_BUCKET_DONE[b]=EEEE; HOST_BUCKET_DONE[c]=''"
)

test_that("consolidate_outcomes names a refused source and keeps its groups out of the signals", {
  skip_if_no_finish_lib()
  w <- finish_world()
  p <- cons_tsv(w, c("cypher@ip-a\tFALSE\tdest_log_newer\tDDDD",
                     "cypher@ip-b\tTRUE\tcomplete\t"))
  r <- run_finish_sh(w, "unused", c(
    cons_setup,
    sprintf("consolidate_outcomes %s", shQuote(p)),
    "echo \"FAILED=$CONS_FAILED\"; echo \"EXCL=$CONS_EXCLUDED\"; echo \"STAGE=${HOST_CONS_FAIL[a]}\"",
    "echo \"BSTAGE=${HOST_CONS_FAIL[b]:-none}\"",
    # DDDD was SKIPped by the dispatcher and finished by a: it stays expected.
    "DISP_BUCKET=AAAA,DDDD; ACC_FINISHED[dispatcher]=AAAA; ACC_SKIP[dispatcher]=DDDD",
    "run_expected_from_hosts; echo \"SIG=$RUN_SIGNALS\"; echo \"EXP=$RUN_EXPECT\""
  ))
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "FAILED=a\n", fixed = TRUE)
  expect_identical(printed(r, "EXCL"), "CCCC,DDDD")
  expect_match(r$out, "STAGE=dest_log_newer", fixed = TRUE)
  expect_match(r$out, "BSTAGE=none", fixed = TRUE)
  expect_match(r$out, "cy[a]: consolidate failed at stage dest_log_newer", fixed = TRUE)
  expect_match(r$out, "DDDD", fixed = TRUE)
  # The refused host's bucket is no finish signal; it is still expected.
  expect_identical(printed(r, "SIG"), "AAAA,EEEE")
  expect_identical(printed(r, "EXP"), "AAAA,CCCC,DDDD,EEEE,FFFF")
})

test_that("consolidate_outcomes refuses a record that does not account for every source", {
  skip_if_no_finish_lib()
  w <- finish_world()
  p <- cons_tsv(w, "cypher@ip-a\tFALSE\tdest_copy\t")
  r <- run_finish_sh(w, "unused", c(
    cons_setup,
    sprintf("rc=0; consolidate_outcomes %s || rc=$?; echo \"RC=$rc\"", shQuote(p))
  ))
  expect_match(r$out, "RC=1", fixed = TRUE)
  expect_match(r$out, "cy[b]", fixed = TRUE)
  r <- run_finish_sh(w, "unused", c(
    cons_setup,
    "rc=0; consolidate_outcomes /nonexistent/T0_consolidate.tsv || rc=$?; echo \"RC=$rc\""
  ))
  expect_match(r$out, "RC=1", fixed = TRUE)
})

test_that("a refused source's groups are not recomputed; the others are, and the run exits non-zero", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  # BBBB came from host a, whose consolidate was refused; its rows here, and
  # its closed log row, belong to some other copy. AAAA came from elsewhere.
  r <- run_finish_sh(w, sc, c(
    "HOST_ARR=(a); HOST_BUCKET[a]=BBBB; HOST_HOLD[a]=1",
    "run_finish AAAA,BBBB '' BBBB"
  ))
  expect_equal(r$status, 1L, info = r$out)
  calls <- rscript_calls(w)
  recomputed <- sub("^data-raw/wsg_recompute_one\\.R ([A-Z]{4}) default$", "\\1",
                    grep("wsg_recompute_one", calls, value = TRUE))
  expect_identical(recomputed, "AAAA")
  expect_match(grep("study_area_compare", calls, value = TRUE), " AAAA default$")
  expect_match(r$out, "not consolidated (its host's consolidate failed): BBBB", fixed = TRUE)
  expect_match(r$out, "re-model only what is still missing: BBBB", fixed = TRUE)
  cov <- utils::read.delim(file.path(w, "logs", "T0_coverage.tsv"), colClasses = "character")
  expect_identical(cov$class[order(cov$wsg)], c("recompute", "not_consolidated"))
})

# The consolidate program's outcome writer is pinned in test-study_area_legs.R
# ("the consolidate program is what consolidate_outcomes reads"): since
# link#369 it lives in study_area_legs.sh, one call per host.

test_that("the driver records the run's groups before any spend and hands run_finish the excluded set", {
  # Structural: the full-run path needs cloud hosts, so no test executes it.
  # These pin the wiring the lib tests above rely on (link#358, link#369).
  skip_if_no_finish_lib()
  drv <- readLines(finish_driver())
  legs <- readLines(normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_legs.sh")))
  first_write <- grep('^run_wsgs_write "\\$RUN_WSGS_TSV"$', drv)
  spin <- grep("=== spin cyphers", drv, fixed = TRUE)
  accounting <- grep("=== dispatcher completeness (database) ===", drv, fixed = TRUE)
  expect_length(first_write, 1L)
  expect_lt(first_write, spin[1])
  rewrite <- grep('^run_wsgs_write "\\$RUN_WSGS_TSV" \\\\$', drv)
  expect_length(rewrite, 1L)
  expect_gt(rewrite, accounting)
  # Each host's SKIPs are recorded as soon as it is accounted.
  expect_length(grep('  run_wsgs_write "$RUN_WSGS_TSV" \\', legs, fixed = TRUE), 1L)
  expect_length(grep('^run_finish "\\$RUN_EXPECT" "\\$RUN_SIGNALS" "\\$\\{CONS_EXCLUDED:-\\}"$', drv), 1L)
  expect_length(grep('  elif consolidate_outcomes "$tsv" "$ws" && [ -n "${HOST_CONS_FAIL[$ws]:-}" ]; then',
                     legs, fixed = TRUE), 1L)
  expect_length(grep("run_expected_recompute_only \"$WSGS_ARG\" || exit 1", drv, fixed = TRUE), 1L)
  expect_length(grep("  run_finish \"$RO_EXPECT\" \"\" \"$RO_EXCLUDED\"", drv, fixed = TRUE), 1L)
  expect_length(grep("[ -z \"${CONS_FAILED:-}\" ] || RUN_INCOMPLETE=1", drv, fixed = TRUE), 1L)
  # The state record goes in_flight before the copy, and is rewritten once
  # the copy has an outcome.
  writes <- grep('consolidate_state_write "$CONS_STATE"', legs, fixed = TRUE)
  copy <- grep(".legs_consolidate_r \"$src\" \"$tsv\"", legs, fixed = TRUE)
  expect_length(writes, 2L)
  expect_length(copy, 1L)
  expect_lt(writes[1], copy)
  expect_gt(writes[2], copy)
  expect_match(legs[writes[1] - 2L], "HOST_CONS_STATE[$ws]=in_flight", fixed = TRUE)
})

state_file <- function(w) file.path(w, "logs", "20261018_000000_consolidate_state.tsv")

test_that("consolidate_state_write records in_flight before, then ok or the failed stage", {
  skip_if_no_finish_lib()
  w <- finish_world()
  p <- state_file(w)
  r <- run_finish_sh(w, "unused", c(
    cons_setup,
    sprintf("consolidate_state_write %s in_flight; cp %s %s.before", shQuote(p), shQuote(p), shQuote(p)),
    "HOST_CONS_FAIL[a]=dest_copy",
    sprintf("consolidate_state_write %s ok", shQuote(p))
  ))
  expect_equal(r$status, 0L, info = r$out)
  before <- utils::read.delim(paste0(p, ".before"), colClasses = "character")
  expect_identical(names(before), c("wsg", "workspace", "state", "run_uid", "state_utc"))
  # c reported nothing, so it was never a source and has no rows.
  expect_identical(paste(before$workspace, before$wsg, before$state),
                   c("a CCCC in_flight", "a DDDD in_flight", "b EEEE in_flight"))
  after <- utils::read.delim(p, colClasses = "character")
  expect_identical(after$state, c("failed:dest_copy", "failed:dest_copy", "ok"))
  expect_true(all(after$run_uid == finish_uid))
})

test_that("--recompute-only keeps every group not consolidated ok out until --wsgs= names them", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  # BBBB's host failed; ZZZZ's never finished (R died mid-copy); ZZZZ is in
  # no other record, so only the union names it.
  writeLines(c("wsg\tworkspace\tstate\trun_uid",
               sprintf("AAAA\tb\tok\t%s", finish_uid),
               sprintf("BBBB\ta\tfailed:dest_copy\t%s", finish_uid),
               sprintf("ZZZZ\tc\tin_flight\t%s", finish_uid)), state_file(w))
  r <- run_finish_sh(w, sc, c(
    "run_expected_recompute_only ''; echo \"EXCL=$RO_EXCLUDED\"; echo \"EXP=$RO_EXPECT\"",
    "run_finish \"$RO_EXPECT\" '' \"$RO_EXCLUDED\""
  ))
  expect_equal(r$status, 1L, info = r$out)
  expect_identical(printed(r, "EXCL"), "BBBB,ZZZZ")
  expect_match(printed(r, "EXP"), "ZZZZ", fixed = TRUE)
  recomputed <- sub("^data-raw/wsg_recompute_one\\.R ([A-Z]{4}) default$", "\\1",
                    grep("wsg_recompute_one", rscript_calls(w), value = TRUE))
  expect_false(any(c("BBBB", "ZZZZ") %in% recomputed))
  expect_true("AAAA" %in% recomputed)
  expect_match(r$out, "not consolidated:                BBBB,ZZZZ", fixed = TRUE)

  r <- run_finish_sh(w, sc, "run_expected_recompute_only AAAA,BBBB; echo \"EXCL=$RO_EXCLUDED\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "EXCL"), "")

  # Another run's record stops a bare --recompute-only.
  writeLines(c("wsg\tworkspace\tstate\trun_uid", "BBBB\ta\tok\t20261101_000000-0000beef"),
             state_file(w))
  r <- run_finish_sh(w, sc, "run_expected_recompute_only ''")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "not this run's consolidate record", fixed = TRUE)

  # No record: the run never reached consolidate; nothing is excluded.
  unlink(state_file(w))
  r <- run_finish_sh(w, sc, "run_expected_recompute_only ''; echo \"EXCL=$RO_EXCLUDED\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "EXCL"), "")
})

test_that("a failed host's finished group outside its bucket is still classed not_consolidated", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, "run_finish AAAA '' BBBB")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "not consolidated (its host's consolidate failed): BBBB", fixed = TRUE)
})

test_that("a kept host's group finished outside its bucket is settled there, not re-modelled", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  # ZZZZ: finished by a outside its bucket, still on the kept host
  # (HOST_UNCONS, which kept_hosts.tsv writes), and excluded with a's bucket.
  r <- run_finish_sh(w, sc, c(
    "HOST_ARR=(a); HOST_BUCKET[a]=BBBB; HOST_HOLD[a]=1; HOST_UNCONS[a]=BBBB,ZZZZ",
    "run_finish AAAA '' BBBB,ZZZZ"
  ))
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "re-model only what is still missing: BBBB,ZZZZ", fixed = TRUE)
  expect_false(grepl("Re-model each of these under this run_uid", r$out, fixed = TRUE))
})

test_that("run_coverage classes an excluded group even when the expected set lacks it", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  r <- run_finish_sh(w, sc, c(
    "run_coverage AAAA '' BBBB",
    "echo \"REC=$COV_RECOMPUTE\"; echo \"UNCONS=$COV_UNCONS\"; echo \"MISSING=$COV_MISSING\""
  ))
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "REC"), "AAAA")
  expect_identical(printed(r, "UNCONS"), "BBBB")
  expect_identical(printed(r, "MISSING"), "BBBB")
})

# --- a group whose statement hit the bound (link#371) -----------------------

# The run's host logs are named for the run_uid's timestamp, which is TS in a
# full run and an earlier TS under --recompute-only.
run_log <- function(w, host, lines) {
  writeLines(lines, file.path(w, "logs", sprintf("20261018_000000_run_%s.log", host)))
}

test_that("run_timeouts names the missing groups whose statement hit the bound, from every host's log", {
  skip_if_no_finish_lib()
  w <- finish_world()
  run_log(w, "local", c(
    "[wsg_run_one] OKAN statement_timeout=30min",
    "[wsg_run_one] OKAN TIMEOUT after 30min: CREATE TEMP TABLE pg_temp.frs_near_river_walk AS SELECT 1",
    "[WARN] dispatcher WSG OKAN failed (continuing)",
    "[wsg_run_one] AAAA done in 1.0 min (persist=x)",
    # Cut after the digits (the last line read): a bare 30 is 30 ms to
    # Postgres, so it must not become the run's bound.
    "[wsg_run_one] BBBB statement_timeout=30"
  ))
  # Mid-line, as an R warning flushed without a newline leaves it (link#347).
  run_log(w, "job1", "  Could not find a column.[wsg_run_one] KTSU TIMEOUT after 30min: SELECT pg_sleep(3600)")
  # A log cut mid-glyph (a dropped session): bytes macOS sed refuses in a
  # UTF-8 locale, which under the driver's set -e would end the report.
  writeBin(c(charToRaw("[wsg_run_one] KTSU statement_timeout=30min\n"), as.raw(c(0xe2, 0x9c)),
             charToRaw("\n")), file.path(w, "logs", "20261018_000000_run_job2.log"))
  # Another run's log: never read.
  writeLines("[wsg_run_one] XXXX TIMEOUT after 30min: SELECT 1",
             file.path(w, "logs", "20261019_000000_run_local.log"))
  r <- run_finish_sh(w, "unused", c(
    "run_timeouts OKAN,KTSU,AAAA,XXXX; echo \"TO=$TIMED_OUT\"; printf '%s\\n' \"$TIMEOUT_LINES\"",
    "run_timeouts AAAA; echo \"NONE=[$TIMED_OUT][$TIMEOUT_LINES]\"; echo \"BOUND=[$RUN_BOUND]\"",
    "echo REACHED_END"
  ))
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(printed(r, "TO"), "KTSU,OKAN")
  expect_match(r$out, "OKAN (bound 30min): CREATE TEMP TABLE pg_temp.frs_near_river_walk AS SELECT 1",
               fixed = TRUE)
  expect_match(r$out, "KTSU (bound 30min): SELECT pg_sleep(3600)", fixed = TRUE)
  expect_match(r$out, "NONE=[][]", fixed = TRUE)
  expect_match(r$out, "BOUND=[30min]", fixed = TRUE)
  expect_match(r$out, "REACHED_END", fixed = TRUE)
  expect_false(grepl("XXXX (bound", r$out, fixed = TRUE))
})

test_that("the report names a missing group that timed out, and its statement", {
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  run_log(w, "local", "[wsg_run_one] CCCC TIMEOUT after 1min: SELECT pg_sleep(3600) -- LNK_TEST_STALL_WSG")
  r <- run_finish_sh(w, sc, "run_finish AAAA,BBBB,CCCC ''")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "statement bound hit:             CCCC", fixed = TRUE)
  # The re-model it prints is bounded too.
  expect_match(r$out, "PGOPTIONS='-c statement_timeout=30min'", fixed = TRUE)
  expect_match(r$out, "CCCC (bound 1min): SELECT pg_sleep(3600) -- LNK_TEST_STALL_WSG", fixed = TRUE)
})

test_that("the driver bounds a statement on both modelling legs and refuses a bad bound", {
  skip_if_no_finish_lib()
  drv <- readLines(finish_driver())
  # Structural: the legs need hosts to run. Between the run-buckets banner and
  # the wait, the bound is set once on the local leg and once in the ssh
  # string; the recompute leg is left to wsg_recompute_one.R's own SET.
  from <- grep("=== run buckets (DS-first) ===", drv, fixed = TRUE)
  to <- grep("host runs finished (per-WSG soft-fail", drv, fixed = TRUE)
  expect_length(from, 1L)
  expect_length(to, 1L)
  legs <- drv[from:to]
  legs <- legs[!grepl("^[[:space:]]*#", legs)]
  bound <- "statement_timeout=${STATEMENT_TIMEOUT_MIN}min"
  # The local leg sets it here; the ssh leg's command is built by
  # remote_leg_cmd (study_area_remote.sh, link#376), which the driver calls.
  expect_length(grep(bound, legs, fixed = TRUE), 1L)
  expect_length(grep("LNK_STATEMENT_TIMEOUT_MIN=", legs, fixed = TRUE), 1L)
  expect_length(grep('"$(remote_leg_cmd "$WS" "$B_SPACE")"', legs, fixed = TRUE), 1L)
  remote <- readLines(testthat::test_path("..", "..", "data-raw", "study_area_remote.sh"))
  leg_fn <- remote[grep("^remote_leg_cmd\\(\\) \\{", remote):length(remote)]
  leg_fn <- leg_fn[seq_len(which(leg_fn == "}")[1])]
  # ... and the minutes it asked for, which wsg_run_one.R checks it got.
  expect_length(grep("export LNK_STATEMENT_TIMEOUT_MIN='$STATEMENT_TIMEOUT_MIN'", leg_fn, fixed = TRUE), 1L)
  expect_length(grep("TEST HOOK:    LNK_TEST_STALL_WSG", drv, fixed = TRUE), 1L)
  expect_length(grep(paste0("export PGOPTIONS='-c ", bound, "'"), leg_fn, fixed = TRUE), 1L)
  rc_from <- grep("^recompute_one\\(\\) \\{", drv)
  rc_to <- rc_from + which(drv[-seq_len(rc_from)] == "}")[1]
  expect_length(rc_from, 1L)
  expect_length(grep("PGOPTIONS", drv[rc_from:rc_to], fixed = TRUE), 0L)
  expect_length(grep("echo \"  statement:", drv, fixed = TRUE), 1L)

  run_drv <- function(...) {
    out <- suppressWarnings(system2(hosts_bash(), c(shQuote(finish_driver()), ...),
                                    stdout = TRUE, stderr = TRUE))
    list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
  }
  for (bad in c("0", "00", "abc", "", "-5", "1441", "1.5")) {
    r <- run_drv(paste0("--statement-timeout=", bad))
    expect_equal(r$status, 1L, info = bad)
    expect_match(r$out, "--statement-timeout", fixed = TRUE, info = bad)
  }
  r <- run_drv("--recompute-only", paste0("--run-uid=", finish_uid), "--statement-timeout=30")
  expect_equal(r$status, 1L)
  expect_match(r$out, "--recompute-only takes no", fixed = TRUE)
})

test_that("the TIMEOUT line wsg_run_one.R writes is the one run_timeouts reads", {
  skip_if_no_finish_lib()
  src <- readLines(testthat::test_path("..", "..", "data-raw", "wsg_run_one.R"))
  fmt <- regmatches(src, regexpr('"\\[wsg_run_one\\] %s TIMEOUT after %s: %s\\\\n"', src))
  expect_length(fmt, 1L)
  line <- sprintf(eval(parse(text = fmt)), "OKAN", "30min", "CREATE TEMP TABLE t AS SELECT 1")
  w <- finish_world()
  run_log(w, "local", sub("\n$", "", line))
  r <- run_finish_sh(w, "unused", "run_timeouts OKAN; printf '%s\\n' \"$TIMEOUT_LINES\"")
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "OKAN (bound 30min): CREATE TEMP TABLE t AS SELECT 1", fixed = TRUE)
})

test_that("the printed re-model carries the bound the run's groups reported", {
  # --recompute-only takes no --statement-timeout, so the bound comes from the
  # run's own logs (code-check round 1).
  skip_if_no_finish_lib()
  conn <- skip_if_no_db()
  sc <- finish_fixture(conn)
  w <- finish_world()
  run_log(w, "local", c(
    "[wsg_run_one] AAAA statement_timeout=2h",
    "[wsg_run_one] CCCC statement_timeout=2h",
    "[wsg_run_one] CCCC TIMEOUT after 2h: SELECT 1"
  ))
  r <- run_finish_sh(w, sc, "run_finish AAAA,BBBB,CCCC ''")
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "PGOPTIONS='-c statement_timeout=2h'", fixed = TRUE)
  expect_match(r$out, "raise it for CCCC", fixed = TRUE)
  # The printed command is one command a shell parses, with the bound on it.
  out <- strsplit(r$out, "\n")[[1]]
  i <- grep("^    PGOPTIONS='", out)
  j <- grep("Rscript data-raw/wsg_run_one.R <WSG>", out, fixed = TRUE)
  expect_length(i, 1L)
  expect_length(j, 1L)
  cmd <- sub("<WSG>", "CCCC", out[i:j], fixed = TRUE)
  f <- file.path(w, "remodel.sh")
  writeLines(cmd, f)
  chk <- suppressWarnings(system2(hosts_bash(), c("-n", shQuote(f)), stdout = TRUE, stderr = TRUE))
  expect_null(attr(chk, "status"), info = paste(c(cmd, chk), collapse = "\n"))
  # One command: every line but the last continues it.
  expect_true(all(grepl("\\\\$", cmd[-length(cmd)])), info = paste(cmd, collapse = "\n"))
})
