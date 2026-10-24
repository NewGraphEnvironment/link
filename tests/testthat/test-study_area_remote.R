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
    # `ssh -G <target>` reads the config: answer from G_<target> if present.
    sprintf('[ "$1" = "-G" ] && { [ -f "%s/G_$2" ] && cat "%s/G_$2"; exit 0; }', d, d),
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

# -- A persistent worker (link#376) ------------------------------------------

worker_globals <- c(
  "SCHEMA=s; CONFIG=c; RUN_UID=u; RUN_LABEL=; STATEMENT_TIMEOUT_MIN=30; RUN_SHA=abc123",
  "declare -A HOST_SSH HOST_KIND; HOST_SSH[worker1]=wk; HOST_KIND[worker1]=worker",
  "HOST_SSH[a]=cypher@ip-a"
)

test_that("a worker runs from the driver's own clone, by load_all", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(worker_globals,
                       'echo "W=$(remote_leg_cmd worker1 AAAA)"',
                       'echo "C=$(remote_leg_cmd a AAAA)"',
                       'echo "WCD=$(.remote_cd worker1)"; echo "CCD=$(.remote_cd a)"'))
  lines <- strsplit(r$out, "\n")[[1]]
  wl <- sub("^W=", "", grep("^W=", lines, value = TRUE))
  cl <- sub("^C=", "", grep("^C=", lines, value = TRUE))
  expect_match(wl, "^cd ~/Projects/repo/link_worker && export LNK_LOAD=loadall && ")
  expect_match(cl, "^cd ~/Projects/repo/link && export LNK_SCHEMA")
  expect_no_match(cl, "LNK_LOAD", fixed = TRUE)
  expect_match(r$out, "WCD=cd ~/Projects/repo/link_worker && export LNK_LOAD=loadall", fixed = TRUE)
  expect_match(r$out, "CCD=cd ~/Projects/repo/link$")
})

test_that("a worker's leg runs no group once its clone's HEAD has moved", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(worker_globals, "remote_leg_cmd worker1 'AAAA BBBB'"))
  cmd <- r$out
  expect_match(cmd, "[ \"$(git rev-parse HEAD)\" = 'abc123' ] || { echo \"[WARN] worker WSG $w not run: HEAD moved off abc123\"; continue; };",
               fixed = TRUE)
  # Run the loop part with a HEAD that is not the run's: no group runs.
  d <- withr::local_tempdir()
  system2("git", c("-C", d, "init", "-q"))
  system2("git", c("-C", d, "-c", "user.email=t@t", "-c", "user.name=t",
                   "commit", "-q", "--allow-empty", "-m", "x"))
  loop <- sub("^.*&& \\{", "{", cmd)
  loop <- gsub("Rscript data-raw/wsg_run_one.R $w 'c'", "echo RAN $w", loop, fixed = TRUE)
  out <- suppressWarnings(system2("sh", c("-c", shQuote(paste("cd", shQuote(d), "&&", loop))),
                                  stdout = TRUE, stderr = TRUE))
  expect_false(any(grepl("^RAN", out)))
  expect_length(grep("not run: HEAD moved", out, fixed = TRUE), 2L)
  expect_true(any(grepl("__LNK_LEG_END__", out, fixed = TRUE)))
})

test_that("the stall hook crosses ssh only as one group code", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(worker_globals, "LNK_TEST_STALL_WSG=ADMS",
                       'remote_leg_cmd a AAAA'))
  expect_match(r$out, "export LNK_TEST_STALL_WSG='ADMS' && ", fixed = TRUE)
  r <- run_remote(w, c(worker_globals, 'remote_leg_cmd a AAAA'))
  expect_no_match(r$out, "LNK_TEST_STALL_WSG", fixed = TRUE)
  for (bad in c("\"A'; rm -rf x\"", "$'ABCD\\n'\"'\"'; rm -rf x'")) {
    r <- run_remote(w, c(worker_globals, paste0("LNK_TEST_STALL_WSG=", bad),
                         'remote_leg_cmd a AAAA && echo RC=0 || echo RC=$?'))
    expect_match(r$out, "RC=1", fixed = TRUE, info = bad)
    expect_no_match(r$out, "rm -rf", fixed = TRUE)
  }
})

test_that("worker prep's environment carries the run, and refuses an origin it cannot quote", {
  skip_if_no_remote_lib()
  w <- remote_world()
  r <- run_remote(w, c(
    "LINK_BRANCH=b; CONFIG=default; SCHEMA=fresh_x; WET_LOAD=",
    "ORIGIN_URL=https://github.com/NewGraphEnvironment/link.git",
    'worker_prep_env worker1'))
  expect_identical(r$out, paste(
    "WORKER_PREP_BRANCH='b' WORKER_PREP_ORIGIN='https://github.com/NewGraphEnvironment/link.git'",
    "WORKER_PREP_CONFIG='default' WORKER_PREP_SCHEMA='fresh_x' WORKER_PREP_WET_LOAD=''"))
  r <- run_remote(w, c("ORIGIN_URL=\"https://x/y'z\"",
                       'worker_prep_env worker1 && echo RC=0 || echo RC=$?'))
  expect_match(r$out, "RC=1", fixed = TRUE)
})

test_that("a worker's target is redacted whole and literally", {
  skip_if_no_remote_lib()
  w <- remote_world()
  f <- file.path(w, "T0_run_worker1.log")
  writeLines(c("ssh: connect to host m4.tail-x.ts.net port 22: refused",
               "m4.tail-x.ts.netX and am4.tail-x.ts.net stay; m4xtail-x.ts.net stays",
               "user@m4.tail-x.ts.net:22"), f)
  run_remote(w, c(
    "WK_TARGETS=(m4.tail-x.ts.net user@m4.tail-x.ts.net); WK_KEYS=(worker1 worker2)",
    sprintf("remote_redact_targets %s", shQuote(f))))
  expect_identical(readLines(f), c(
    "ssh: connect to host <worker1> port 22: refused",
    "m4.tail-x.ts.netX and am4.tail-x.ts.net stay; m4xtail-x.ts.net stays",
    "<worker2>:22"))
})

test_that("what ssh writes for a target is redacted too: its host part and its HostName", {
  skip_if_no_remote_lib()
  w <- remote_world()
  # An alias from ssh's config, which ssh's errors name by its HostName.
  writeLines(c("user airvine", "hostname box.tail-y.ts.net", "port 22"), file.path(w, "G_wk"))
  f <- file.path(w, "T0_reach_worker1.log")
  writeLines(c("ssh: connect to host box.tail-y.ts.net port 22: timed out",
               "ssh: Could not resolve hostname host9.example: nodename nor servname",
               "wk and ops@host9.example"), f)
  run_remote(w, c(
    "WK_TARGETS=(wk ops@host9.example); WK_KEYS=(worker1 worker2)",
    sprintf("remote_redact_targets %s", shQuote(f))))
  expect_identical(readLines(f), c(
    "ssh: connect to host <worker1> port 22: timed out",
    "ssh: Could not resolve hostname <worker2>: nodename nor servname",
    "<worker1> and <worker2>"))
})

# -- The driver's own refusals, before anything runs (link#376) ---------------

run_driver <- function(...) {
  drv <- normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_run.sh"),
                       mustWork = FALSE)
  testthat::skip_if_not(file.exists(drv), "data-raw/study_area_run.sh absent")
  out <- suppressWarnings(system2(hosts_bash(), c(shQuote(drv), ...),
                                  stdout = TRUE, stderr = TRUE))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

test_that("the driver refuses a worker target it cannot pass safely", {
  skip_if_no_remote_lib()
  # An embedded newline whose first line fits: a line-wise check passes it.
  for (bad in c("-oProxyCommand=x", "local", "a'b", "a b", "a;b", "", "good\nx'; touch y; '")) {
    r <- run_driver(shQuote(paste0("--workers=", bad, ",ok")), "--focal=A", "--focal=B", "--focal=C")
    expect_equal(r$status, 1L, info = bad)
    expect_match(r$out, "--workers= takes ssh targets", fixed = TRUE, info = bad)
  }
  r <- run_driver("--workers=wk,wk", "--focal=A", "--focal=B", "--focal=C")
  expect_equal(r$status, 1L)
  expect_match(r$out, "names worker 2 twice", fixed = TRUE)
  r <- run_driver("--workers=wk", "--cy-workspaces=worker1", "--focal=A", "--focal=B", "--focal=C")
  expect_equal(r$status, 1L)
  expect_match(r$out, "may not name 'worker1'", fixed = TRUE)
})

test_that("the driver counts one --focal per worker, and refuses workers when finishing a run", {
  skip_if_no_remote_lib()
  r <- run_driver("--workers=wk", "--cy-workspaces=job1", "--focal=A", "--focal=B")
  expect_equal(r$status, 1L)
  expect_match(r$out, "need exactly 3 --focal flags (1 dispatcher + 1 workers + 1 cyphers, in that order); got 2",
               fixed = TRUE)
  r <- run_driver("--recompute-only", "--run-uid=20261024_000000-abcd1234", "--workers=wk")
  expect_equal(r$status, 1L)
  expect_match(r$out, "--recompute-only takes no --focal, --cy-workspaces, --workers", fixed = TRUE)
})

test_that("the driver refuses a stall hook that is not one group code", {
  skip_if_no_remote_lib()
  for (bad in c("AB; rm", "ABCD\n'$(id)'")) {
    r <- withr::with_envvar(c(LNK_TEST_STALL_WSG = bad),
                            run_driver("--workers=wk", "--focal=A", "--focal=B"))
    expect_equal(r$status, 1L, info = bad)
    expect_match(r$out, "LNK_TEST_STALL_WSG must be one four-letter group code", fixed = TRUE)
  }
})

test_that("the driver refuses a branch name a remote command could not carry", {
  skip_if_no_remote_lib()
  drv <- normalizePath(testthat::test_path("..", "..", "data-raw", "study_area_run.sh"), mustWork = FALSE)
  lines <- readLines(drv)
  at <- grep('^LINK_BRANCH="\\$\\(git -C "\\$REPO_ROOT" branch --show-current\\)"$', lines)
  expect_length(at, 1L)
  near <- lines[at + 1:8]
  # Only when a remote host is sent it, and on the whole value.
  expect_true(any(grepl('if [ "$N_HOSTS" -gt 0 ] && ! [[ "$LINK_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]]; then',
                        near, fixed = TRUE)))
})
