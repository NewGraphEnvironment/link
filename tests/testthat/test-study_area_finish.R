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
    "CY_WS_ARR=(a b); CY_BUCKET[a]=CCCC,DDDD; CY_HOLD[a]=1",
    "CY_BUCKET[b]=GGGG; CY_HOLD[b]=0",
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
    "CY_WS_ARR=(); KEPT_TSV_GROUPS=CCCC",
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
    "DISP_BUCKET=AAAA,BBBB,SSSS; CY_WS_ARR=(a b)",
    "CY_BUCKET[a]=CCCC,DDDD; CY_BUCKET[b]=EEEE,TTTT",
    "ACC_FINISHED[dispatcher]=AAAA; ACC_DONE_LOG[dispatcher]=BBBB",
    "ACC_SKIP[dispatcher]=SSSS; ACC_SKIP[a]=EEEE; ACC_SKIP[b]=TTTT",
    "CY_BUCKET_DONE[a]=CCCC; CY_BUCKET_DONE[b]=EEEE",
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
