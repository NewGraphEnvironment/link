# Extracted from test-study_area_phases.R:263

# prequel ----------------------------------------------------------------------
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
    testthat::fail("no bash >= 5.1 found; the study_area_phases.sh tests cannot run")
  }
}
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

# test -------------------------------------------------------------------------
drv_path <- testthat::test_path("..", "..", "data-raw", "study_area_run.sh")
testthat::skip_if_not(file.exists(drv_path), "data-raw/study_area_run.sh absent")
drv <- readLines(drv_path)
expect_length(grep("|| mrc=$?", drv, fixed = TRUE), 2L)
expect_length(grep('^  exit "\\$mrc" \\) >> "\\$LOG_DIR/\\$\\{TS\\}_run_[^"]+\\.log" 2>&1 &$', drv), 2L)
expect_length(grep('  ( cd "$REPO_ROOT" || exit 1', drv, fixed = TRUE), 1L)
