# data-raw/study_area_phases.sh: when each phase of a run started and ended,
# per host (link#375). The lib is bash, so each test runs it in a bash process
# with a stub `date` on PATH that steps one minute per call, so times, minutes
# and the critical path are known in advance.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the lib is absent and
# these skip; devtools::test() from the source tree runs them.

# LNK_TEST_PHASES_LIB points the tests at a mutant copy (proving they fail).
phases_lib <- function() {
  p <- Sys.getenv(
    "LNK_TEST_PHASES_LIB",
    testthat::test_path("..", "..", "data-raw", "study_area_phases.sh")
  )
  normalizePath(p, mustWork = FALSE)
}

skip_if_no_phases_lib <- function() {
  testthat::skip_if_not(file.exists(phases_lib()), "data-raw/study_area_phases.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 4 found; the study_area_phases.sh tests cannot run")
  }
}

# Runs `body` after sourcing the lib, with RUN_UID set and the file at
# <dir>/p.tsv. The stub date's n-th call reads 2026-10-24T00:<n>:00Z.
run_phases <- function(body, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(d, "bin"))
  writeLines(c(
    "#!/bin/sh",
    sprintf('c="%s/date_n"; n=$(cat "$c" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$c"', d),
    'printf "2026-10-24T00:%02d:00Z %d\\n" "$n" $((1761264000 + 60 * n))'
  ), file.path(d, "bin", "date"))
  Sys.chmod(file.path(d, "bin", "date"), "755")
  script <- c(
    "set -euo pipefail",
    sprintf('export PATH="%s/bin:$PATH"', d),
    sprintf("source %s", shQuote(phases_lib())),
    "RUN_UID=u1",
    sprintf('phases_init "%s/p.tsv"', d),
    body
  )
  f <- file.path(d, "t.sh")
  writeLines(script, f)
  out <- suppressWarnings(system2(hosts_bash(), shQuote(f), stdout = TRUE, stderr = TRUE))
  tsv <- file.path(d, "p.tsv")
  rows <- if (file.exists(tsv)) {
    utils::read.delim(tsv, colClasses = "character", quote = "", na.strings = character(),
                      comment.char = "")
  } else {
    NULL
  }
  list(out = out, status = attr(out, "status"), rows = rows,
       lines = if (file.exists(tsv)) readLines(tsv) else character())
}

test_that("a phase's row carries its start, end, minutes, groups and status", {
  skip_if_no_phases_lib()
  r <- run_phases(c("phase_begin model dispatcher", "phase_end model dispatcher 4 ok"))
  expect_null(r$status)
  expect_equal(r$lines[1], "run_uid\tphase\thost\tstart_utc\tend_utc\tminutes\tgroups\tstatus")
  expect_equal(nrow(r$rows), 1L)
  expect_equal(unlist(r$rows[1, ], use.names = FALSE),
               c("u1", "model", "dispatcher", "2026-10-24T00:01:00Z",
                 "2026-10-24T00:02:00Z", "1.0", "4", "ok"))
  expect_true(any(grepl("[phase] model dispatcher ok 2026-10-24T00:01:00Z -> 2026-10-24T00:02:00Z (1.0 min, 4 groups)",
                        r$out, fixed = TRUE)))
})

test_that("the header is written once, and a new init on the file keeps its rows", {
  skip_if_no_phases_lib()
  r <- run_phases(c(
    "phase_begin views", "phase_end views '' '' ok",
    'phases_init "$PHASES_TSV"',
    "phase_begin compare", "phase_end compare '' 3 ok"
  ))
  expect_equal(sum(grepl("^run_uid\t", r$lines)), 1L)
  expect_equal(r$rows$phase, c("views", "compare"))
  expect_equal(r$rows$host, c("", ""))
  expect_equal(r$rows$groups, c("", "3"))
})

test_that("a skipped phase has blank times and no minutes", {
  skip_if_no_phases_lib()
  r <- run_phases("phase_skip consolidate")
  expect_equal(unlist(r$rows[1, ], use.names = FALSE),
               c("u1", "consolidate", "", "", "", "", "", "skipped"))
  expect_true(any(grepl("[phase] consolidate skipped", r$out, fixed = TRUE)))
})

test_that("a start given to phase_begin is the row's start", {
  skip_if_no_phases_lib()
  r <- run_phases(c("phase_begin prep '' '2026-10-23T23:50:00Z 1761263400'",
                    "phase_end prep '' 2 ok"))
  expect_equal(r$rows$start_utc, "2026-10-23T23:50:00Z")
  expect_equal(r$rows$minutes, "11.0")
})

test_that("subshells that end in parallel each write a whole row", {
  skip_if_no_phases_lib()
  # Each subshell's own date stub would race on the counter, so the legs take
  # real time: this checks the rows, not their times.
  r <- run_phases(c(
    "export PATH=\"${PATH#*:}\"",
    "for h in a b c d e f g h; do phase_begin model $h; done",
    "for h in a b c d e f g h; do ( phase_end model $h 1 ok quiet ) & done",
    "wait",
    "for h in a b c d e f g h; do phase_forget model $h; done",
    'n=0; for k in "${!PHASE_OPEN[@]}"; do n=$((n + 1)); done; echo "open=$n"'
  ))
  expect_equal(nrow(r$rows), 8L)
  expect_setequal(r$rows$host, letters[1:8])
  expect_true(all(lengths(strsplit(r$lines[-1], "\t", fixed = TRUE)) == 8L))
  expect_true(all(r$rows$status == "ok"))
  # quiet: the subshells printed nothing; the parent forgot what they closed.
  expect_false(any(grepl("[phase]", r$out, fixed = TRUE)))
  expect_true("open=0" %in% r$out)
})

test_that("phases_close_open closes every open phase as failed, and only those", {
  skip_if_no_phases_lib()
  r <- run_phases(c(
    "phase_begin prep",
    "phase_begin model dispatcher",
    "phase_begin model job1",
    "phase_end model job1 3 ok",
    "phases_close_open",
    'n=0; for k in "${!PHASE_OPEN[@]}"; do n=$((n + 1)); done; echo "open=$n"'
  ))
  expect_equal(nrow(r$rows), 3L)
  failed <- r$rows[r$rows$status == "failed", ]
  expect_setequal(paste(failed$phase, failed$host), c("prep ", "model dispatcher"))
  expect_true(all(nzchar(failed$start_utc) & nzchar(failed$end_utc)))
  expect_true("open=0" %in% r$out)
})

test_that("an end with no begin keeps its end and claims no start", {
  skip_if_no_phases_lib()
  r <- run_phases("phase_end burn '' '' ok")
  expect_equal(r$rows$start_utc, "")
  expect_equal(r$rows$minutes, "")
  expect_equal(r$rows$end_utc, "2026-10-24T00:01:00Z")
})

test_that("the report gives the critical path from first start to last end", {
  skip_if_no_phases_lib()
  # model a 00:01-00:02 and b 00:03-00:05 (one extra date call between);
  # recompute 00:06-00:07; a skipped consolidate adds nothing. First start
  # 00:01 to last end 00:07 is 6.0 min. The sum of rows (4.0) and first end to
  # last end (5.0) both differ, so either mistake fails this.
  r <- run_phases(c(
    "phase_begin model a", "phase_end model a 1 ok quiet",
    "phase_begin model b", "date >/dev/null", "phase_end model b 2 ok quiet",
    "phase_skip consolidate",
    "phase_begin recompute", "phase_end recompute '' 3 ok quiet",
    "phases_report"
  ))
  expect_equal(r$rows$minutes, c("1.0", "2.0", "", "1.0"))
  expect_true(any(grepl("critical path: 6.0 min", r$out, fixed = TRUE)))
  expect_true(any(grepl("longest model leg: 2.0 min (b)", r$out, fixed = TRUE)))
})

test_that("a report with nothing timed prints no critical path", {
  skip_if_no_phases_lib()
  r <- run_phases(c("phase_skip refresh", "phases_report"))
  expect_false(any(grepl("critical path", r$out, fixed = TRUE)))
  expect_null(r$status)
})

test_that("with no file every function is a no-op that succeeds", {
  skip_if_no_phases_lib()
  r <- run_phases(c(
    "PHASES_TSV=''",
    "phase_begin model dispatcher", "phase_end model dispatcher 1 ok",
    "phase_skip burn", "phases_close_open", "phases_report",
    'rc=$?; n=0; for k in "${!PHASE_OPEN[@]}"; do n=$((n + 1)); done; echo "open=$n rc=$rc"'
  ))
  expect_null(r$status)
  expect_equal(length(r$lines), 1L) # the header from init, nothing more
  expect_true("open=0 rc=0" %in% r$out)
})

test_that("a row that cannot be written warns and does not stop the run", {
  skip_if_no_phases_lib()
  r <- run_phases(c(
    'PHASES_TSV="$PHASES_TSV.d/none/p.tsv"',
    "phase_begin model dispatcher", "phase_end model dispatcher 1 ok",
    "echo survived"
  ))
  expect_null(r$status)
  expect_true("survived" %in% r$out)
  expect_true(any(grepl("WARN: could not write the model row", r$out, fixed = TRUE)))
})

test_that("closing open phases leaves alone one a subshell already wrote", {
  skip_if_no_phases_lib()
  # The driver waits on legs one after another, so a leg can end and write its
  # row while the parent still holds it open. A kill then must not add a second,
  # failed row for it; a leg with no row yet is closed failed.
  r <- run_phases(c(
    "phase_begin model dispatcher", "phase_begin model job2",
    "( phase_end model job2 3 ok quiet ) & wait",
    "phases_close_open"
  ))
  expect_equal(nrow(r$rows), 2L)
  expect_equal(r$rows$status[r$rows$host == "job2"], "ok")
  expect_equal(r$rows$status[r$rows$host == "dispatcher"], "failed")
})

test_that("a date that fails costs the row its times, never the run", {
  skip_if_no_phases_lib()
  r <- run_phases(c(
    "phase_begin model dispatcher",
    'date() { return 1; }',
    "phase_end model dispatcher 2 ok",
    "phase_begin views", "phase_end views '' '' ok",
    "echo survived"
  ))
  expect_null(r$status)
  expect_true("survived" %in% r$out)
  expect_equal(r$rows$start_utc, c("2026-10-24T00:01:00Z", ""))
  expect_equal(r$rows$end_utc, c("", ""))
  expect_equal(r$rows$minutes, c("", ""))
  expect_equal(r$rows$status, c("ok", "ok"))
})

test_that("phases_report marks itself printed, so the EXIT trap does not print it twice", {
  skip_if_no_phases_lib()
  r <- run_phases(c('echo "before=$PHASES_REPORTED"', "phases_report",
                    'echo "after=$PHASES_REPORTED"'))
  expect_true(all(c("before=0", "after=1") %in% r$out))
})

# The driver's wrappers, which the dispatcher-only acceptance run cannot reach
# for a cypher. The exit status each one re-raises is what host_wait records,
# and so what decides whether a host may be burned (link#347).
test_that("each model and prep leg re-raises its own exit status after writing its row", {
  drv_path <- testthat::test_path("..", "..", "data-raw", "study_area_run.sh")
  testthat::skip_if_not(file.exists(drv_path), "data-raw/study_area_run.sh absent")
  drv <- readLines(drv_path)
  # Two model legs (the local one and the ssh one), one prep leg.
  expect_length(grep("|| mrc=$?", drv, fixed = TRUE), 2L)
  expect_length(grep('^  exit "\\$mrc" \\) &$', drv), 2L)
  # errexit is off on the left of `||`, so the local leg's cd must fail by hand.
  expect_length(grep('  ( cd "$REPO_ROOT" || exit 1', drv, fixed = TRUE), 1L)
  expect_length(grep("|| prc=$?", drv, fixed = TRUE), 1L)
  expect_length(grep('exit "$prc" ) &', drv, fixed = TRUE), 1L)
  # quiet in a subshell, then forgotten and printed by the parent after its wait.
  expect_length(grep("echo failed)\" quiet", drv, fixed = TRUE), 2L)
  expect_length(grep('phase_end prep "$WS" "" "$pst" quiet', drv, fixed = TRUE), 1L)
  w_local <- grep("^wait \\$LOCAL_PID", drv)
  expect_length(w_local, 1L)
  expect_match(drv[w_local + 1L], "phase_forget model dispatcher; phase_print model dispatcher",
               fixed = TRUE)
  expect_length(grep('phase_forget model "$WS"; phase_print model "$WS"', drv, fixed = TRUE), 1L)
  # The trap closes open phases before the burn, and cannot be stopped by it.
  t <- grep("^on_exit\\(\\) \\{", drv)
  body <- drv[t:(t + which(drv[-seq_len(t)] == "}")[1])]
  expect_lt(grep("phases_close_open || true", body, fixed = TRUE),
            grep("burn_cyphers || rc=$?", body, fixed = TRUE))
})
