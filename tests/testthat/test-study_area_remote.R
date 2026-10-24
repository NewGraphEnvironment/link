# data-raw/study_area_remote.sh: how the driver runs a command on a remote
# host and judges it by what the remote shell prints, never by ssh's exit
# status (link#376). Some ssh servers exit 0 whatever the remote command
# returned (Tailscale SSH to macOS does), so each test runs the lib in a bash
# process with a stub ssh on PATH that runs the remote command locally and
# then exits with a fixed status.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the lib is absent and
# these skip; devtools::test() from the source tree runs them.

# LNK_TEST_REMOTE_LIB points the tests at a mutant copy (proving they fail).
remote_lib <- function() {
  p <- Sys.getenv(
    "LNK_TEST_REMOTE_LIB",
    testthat::test_path("..", "..", "data-raw", "study_area_remote.sh")
  )
  normalizePath(p, mustWork = FALSE)
}

skip_if_no_remote_lib <- function() {
  testthat::skip_if_not(file.exists(remote_lib()), "data-raw/study_area_remote.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 5.1 found; the study_area_remote.sh tests cannot run")
  }
}

# A stub ssh: records its argv, runs the remote command (its last argument)
# with sh unless told not to, then exits with `exit_with`, whatever the
# command returned.
remote_world <- function(exit_with = 0L, run = TRUE, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(d, "bin"))
  writeLines(c(
    "#!/bin/sh",
    sprintf('printf "%%s\\n" "$*" >> "%s/argv"', d),
    'for a in "$@"; do last="$a"; done',
    if (run) 'sh -c "$last"' else ":",
    sprintf("exit %d", exit_with)
  ), file.path(d, "bin", "ssh"))
  Sys.chmod(file.path(d, "bin", "ssh"), "755")
  d
}

run_remote <- function(world, body) {
  script <- file.path(world, "run.sh")
  writeLines(c(
    "set -euo pipefail",
    sprintf("source %s", shQuote(remote_lib())),
    sprintf("W=%s", shQuote(world)),
    body
  ), script)
  out <- withr::with_envvar(
    c(PATH = paste(file.path(world, "bin"), Sys.getenv("PATH"), sep = ":")),
    suppressWarnings(system2(hosts_bash(), script, stdout = TRUE, stderr = TRUE))
  )
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

test_that("a remote command's failure is read from what it printed", {
  skip_if_no_remote_lib()
  w <- remote_world() # ssh exits 0, as Tailscale SSH to macOS does
  r <- run_remote(w, c(
    'remote_run h "echo partial; exit 3" "$W/o" "$W/e" && echo RC=0 || echo RC=$?',
    'remote_out "$W/o"'
  ))
  expect_match(r$out, "RC=3", fixed = TRUE)
  expect_match(r$out, "partial", fixed = TRUE)
  expect_no_match(r$out, "__LNK_RC__", fixed = TRUE)
})

test_that("a status the remote shell never printed is a failure", {
  skip_if_no_remote_lib()
  w <- remote_world(run = FALSE)
  r <- run_remote(w, 'remote_run h true "$W/o" "$W/e" && echo RC=0 || echo RC=$?')
  expect_match(r$out, "RC=255", fixed = TRUE)
})

test_that("ssh's own failure wins over anything printed", {
  skip_if_no_remote_lib()
  w <- remote_world(exit_with = 255L)
  r <- run_remote(w, 'remote_run h true "$W/o" "$W/e" && echo RC=0 || echo RC=$?')
  expect_match(r$out, "RC=255", fixed = TRUE)
})

test_that("output without a final newline keeps the row and still reads the status", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(
    "remote_run h \"printf 'a\\tb'\" \"$W/o\" /dev/null && echo RC=0 || echo RC=$?",
    'remote_out "$W/o" | od -c | head -1'
  ))
  expect_match(r$out, "RC=0", fixed = TRUE)
  expect_match(r$out, "a  \\t   b", fixed = TRUE)
})

test_that("a run of the remote command goes through ssh in batch mode", {
  skip_if_no_remote_lib()
  w <- remote_world()
  run_remote(w, 'remote_run "cypher@ip-a" true "$W/o" "$W/e" || true')
  argv <- readLines(file.path(w, "argv"))
  expect_match(argv, "-o BatchMode=yes", fixed = TRUE)
  expect_match(argv, "cypher@ip-a", fixed = TRUE)
})

# -- The modelling leg ------------------------------------------------------

test_that("a leg that reached the end of its loop says so, and only then", {
  skip_if_no_remote_lib()
  w <- remote_world()
  log <- file.path(w, "leg.log")
  # Ended: the marker, even mid-line after a warning flushed without a newline.
  writeLines(c("[wsg_run_one] AAAA done", "Warning message:__LNK_LEG_END__"), log)
  r <- run_remote(w, sprintf(
    "remote_leg_status 0 %s && echo RC=0 || echo RC=$?", shQuote(log)))
  expect_match(r$out, "RC=0", fixed = TRUE)
  # ssh exited 0, but the loop never reached its end (killed, or the session
  # dropped on a server that reports 0 regardless).
  writeLines("[wsg_run_one] AAAA done", log)
  r <- run_remote(w, sprintf(
    "remote_leg_status 0 %s && echo RC=0 || echo RC=$?", shQuote(log)))
  expect_match(r$out, "RC=1", fixed = TRUE)
  # ssh's own failure wins.
  writeLines("__LNK_LEG_END__", log)
  r <- run_remote(w, sprintf(
    "remote_leg_status 255 %s && echo RC=0 || echo RC=$?", shQuote(log)))
  expect_match(r$out, "RC=255", fixed = TRUE)
  # An unreadable log is not an ended leg.
  r <- run_remote(w, "remote_leg_status 0 /nonexistent && echo RC=0 || echo RC=$?")
  expect_match(r$out, "RC=1", fixed = TRUE)
})

test_that("the leg command prints its end marker only after the loop, and not after a failed cd", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(
    "SCHEMA=s; CONFIG=c; RUN_UID=u; RUN_LABEL=; STATEMENT_TIMEOUT_MIN=30",
    "declare -A HOST_SSH HOST_KIND; HOST_SSH[a]=cypher@ip-a",
    'remote_leg_cmd a "AAAA BBBB"'
  ))
  cmd <- r$out
  expect_match(cmd, "__LNK_LEG_END__", fixed = TRUE)
  # The marker is inside the braces the cd guards.
  expect_match(cmd, "&& { for w in AAAA BBBB; do ", fixed = TRUE)
  expect_match(cmd, "; done; echo __LNK_LEG_END__; }$")
  # Run it with a cd that fails: no marker.
  out <- suppressWarnings(system2("sh", c("-c", shQuote(sub("cd ~/Projects/repo/link",
                                            "cd /nonexistent_lnk_dir", cmd, fixed = TRUE))),
                 stdout = TRUE, stderr = TRUE))
  expect_false(any(grepl("__LNK_LEG_END__", out, fixed = TRUE)))
})

test_that("the leg command exports the run's identity and bound", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(
    "SCHEMA=fresh_x; CONFIG=default; RUN_UID=T0-1; RUN_LABEL=lab; STATEMENT_TIMEOUT_MIN=45",
    "FWAPG_GIT_SHA=f1; BCFISHOBS_GIT_SHA=b1; LNK_BCFP_MODEL_VERSION=v1",
    "declare -A HOST_SSH HOST_KIND; HOST_SSH[a]=cypher@ip-a",
    'remote_leg_cmd a "AAAA"'
  ))
  for (s in c("export LNK_SCHEMA='fresh_x'", "export LNK_GUARD_DOWNSTREAM=warn",
              "export LNK_HABITAT_GATE=0",
              "export PGOPTIONS='-c statement_timeout=45min'",
              "export LNK_STATEMENT_TIMEOUT_MIN='45'", "export FWAPG_GIT_SHA='f1'",
              "export BCFISHOBS_GIT_SHA='b1'", "export LNK_RUN_UID='T0-1'",
              "export LNK_RUN_LABEL='lab'", "export LNK_BCFP_MODEL_VERSION='v1'",
              "Rscript data-raw/wsg_run_one.R $w 'default'")) {
    expect_match(r$out, s, fixed = TRUE)
  }
})
