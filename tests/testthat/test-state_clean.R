# data-raw/state_clean.sh --tables= (link#181). Every command that touches a
# process or a database (psql, ssh, ps, kill, pkill, xargs, snapshot) is a stub
# on PATH, so no test kills a real process or drops a real table.
# data-raw/ is .Rbuildignore'd: absent under R CMD check, these skip.

sc_script <- function() {
  p <- normalizePath(testthat::test_path("..", "..", "data-raw", "state_clean.sh"),
                     mustWork = FALSE)
  testthat::skip_if_not(file.exists(p), "data-raw/state_clean.sh absent")
  testthat::skip_if_not(nzchar(hosts_bash()), "no bash >= 5.1 found")
  p
}

sc_run <- function(args, ps_out = "", psql_rc = 0L, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  bin <- file.path(d, "bin"); dir.create(bin)
  stub <- function(name, body) {
    writeLines(c("#!/bin/sh", body), file.path(bin, name))
    Sys.chmod(file.path(bin, name), "755")
  }
  rec <- file.path(d, "calls.log")
  stub("psql", c(sprintf('echo "psql $*" >> %s', rec), sprintf('cat >> %s', rec),
                 sprintf("exit %d", psql_rc)))
  stub("ssh", c(sprintf('echo "ssh $*" >> %s', rec), sprintf('cat >> %s', rec), "exit 0"))
  stub("ps", c(sprintf('printf "%%s\\n" "%s"', ps_out)))
  for (n in c("kill", "pkill", "xargs", "tofu")) stub(n, sprintf('echo "%s $*" >> %s', n, rec))
  out <- suppressWarnings(system2(
    hosts_bash(), c(shQuote(sc_script()), shQuote(unlist(strsplit(args, " ", fixed = TRUE)))), stdout = TRUE, stderr = TRUE,
    env = c(sprintf("PATH=%s:%s", bin, Sys.getenv("PATH")))))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L,
       calls = if (file.exists(rec)) readLines(rec) else character())
}
`%||%` <- function(a, b) if (is.null(a)) b else a

test_that("--tables= drops each listed table on the local host only, and kills nothing", {
  r <- sc_run("--tables=fresh_default.streams_parent,fresh.scratch_a")
  expect_equal(r$status, 0L)
  sql <- paste(r$calls, collapse = "\n")
  expect_match(sql, "DROP TABLE IF EXISTS fresh_default.streams_parent CASCADE;", fixed = TRUE)
  expect_match(sql, "DROP TABLE IF EXISTS fresh.scratch_a CASCADE;", fixed = TRUE)
  expect_false(any(grepl("^(kill|pkill|xargs|ssh|tofu) ", r$calls)))
  expect_match(r$out, "SKIPPED (--tables= kills nothing)", fixed = TRUE)
})

test_that("--tables= refuses an empty value and an entry that is not schema.table", {
  e <- sc_run("--tables=")
  expect_gt(e$status, 0L); expect_match(e$out, "requires at least one")
  for (bad in c("streams", "a.b.c", "Fresh.t", "fresh.t;drop", "fresh.t'x")) {
    r <- sc_run(paste0("--tables=", bad))
    expect_gt(r$status, 0L, label = bad)
    expect_match(r$out, "not schema.table", info = bad)
    expect_length(r$calls, 0L)
  }
})

test_that("--tables= refuses while a study_area_run.sh is live", {
  r <- sc_run("--tables=fresh.t", ps_out = "501 123 1 0 9:00AM ttys001 bash study_area_run.sh --config=x")
  expect_gt(r$status, 0L)
  expect_match(r$out, "study_area_run.sh is live")
  expect_length(r$calls, 0L)
})

test_that("--tables= reaches another host only when it is named", {
  r <- sc_run("--tables=fresh.t --hosts=somehost")
  expect_equal(r$status, 0L)
  expect_true(any(grepl("^ssh somehost docker exec", r$calls)))
  r2 <- sc_run("--hosts=somehost")
  expect_gt(r2$status, 0L)
})

test_that("--tables= combines with --schemas=", {
  r <- sc_run("--schemas=fresh_x --tables=fresh.t --skip-m1 --skip-cy")
  expect_equal(r$status, 0L)
  sql <- paste(r$calls, collapse = "\n")
  expect_match(sql, "DROP SCHEMA", fixed = TRUE)
  expect_match(sql, "DROP TABLE IF EXISTS fresh.t CASCADE;", fixed = TRUE)
})

test_that("a failed drop fails the run, for --tables= and --schemas=", {
  for (a in c("--tables=fresh.t", "--schemas=fresh_x --skip-m1 --skip-cy")) {
    r <- sc_run(a, psql_rc = 1L)
    expect_gt(r$status, 0L, label = a)
    expect_match(r$out, "drop FAILED", info = a)
    expect_no_match(r$out, "schemas dropped", info = a)
  }
})
