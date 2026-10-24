# data-raw/study_area_hosts.sh: what each host finished, and which hosts the
# driver may burn (link#347). The lib is bash, so each test runs it in a bash
# process with stubs on PATH for ssh, psql, tofu and doctl, and a mock
# cypher_down.sh that records its calls instead of destroying anything.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the lib is absent and
# these skip; devtools::test() from the source tree runs them.

# LNK_TEST_HOSTS_LIB points the tests at a mutant copy (proving they fail).
hosts_lib <- function() {
  p <- Sys.getenv(
    "LNK_TEST_HOSTS_LIB",
    testthat::test_path("..", "..", "data-raw", "study_area_hosts.sh")
  )
  normalizePath(p, mustWork = FALSE)
}

# Absent lib (R CMD check, installed tests) skips. A present lib with no
# bash >= 5.1 FAILS: the driver needs bash >= 5.1 too, and nothing in CI runs
# these, so a silent skip would read as coverage.
skip_if_no_hosts_lib <- function() {
  testthat::skip_if_not(file.exists(hosts_lib()), "data-raw/study_area_hosts.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 5.1 found; the study_area_hosts.sh tests cannot run")
  }
}

# Run `body` after sourcing the lib with the driver's globals set. Returns the
# combined output and the exit status.
run_hosts <- function(world, body, cyphers = c("a", "b"), keep = 0L,
                      cyphers_up = 1L) {
  script <- file.path(world, "run.sh")
  writeLines(c(
    "set -euo pipefail",
    sprintf("source %s", shQuote(hosts_lib())),
    "SCHEMA=fresh_test; RUN_UID=T0-0000; TS=T0",
    sprintf(
      "LOG_DIR=%s; CYPHER_DIR=%s; CYPHER_TF=%s",
      shQuote(file.path(world, "logs")), shQuote(file.path(world, "cypher")),
      shQuote(file.path(world, "tf"))
    ),
    sprintf("KEEP_CYPHERS=%d; CYPHERS_UP=%d", keep, cyphers_up),
    sprintf("HOST_ARR=(%s); CY_WS_ARR=(%s)", paste(cyphers, collapse = " "),
            paste(cyphers, collapse = " ")),
    'for ws in "${HOST_ARR[@]}"; do CY_IP[$ws]="ip-$ws"; HOST_SSH[$ws]="cypher@ip-$ws"; HOST_RUN_RC[$ws]=0; done',
    body
  ), script)
  out <- withr::with_envvar(
    c(PATH = paste(file.path(world, "bin"), Sys.getenv("PATH"), sep = ":")),
    suppressWarnings(system2(hosts_bash(), script, stdout = TRUE, stderr = TRUE))
  )
  list(
    out = paste(out, collapse = "\n"),
    status = attr(out, "status") %||% 0L
  )
}

# The line R actually wrote in run 20261017_004619-3f4c713b: a warning flushed
# without a newline, then the marker.
midline <- function(wsg, what = "done in 4.6 min (persist=fresh_default)") {
  sprintf(
    "8: In st_read.DBIObject(conn, query = query) :[wsg_run_one] %s %s",
    wsg, what
  )
}

test_that("a host whose every done marker is mid-line is complete", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  writeLines(midline(c("FIRE", "KITR", "UPET")), file.path(w, "logs", "run_a.log"))
  put(w, "ssh_ip-a.out", db_answer(c("FIRE", "KITR", "UPET")))
  r <- run_hosts(w, c(
    sprintf(
      "host_account a cypher@ip-a %s FIRE,KITR,UPET && echo RC=0 || echo RC=$?",
      shQuote(file.path(w, "logs", "run_a.log"))
    ),
    'echo "STATE=${ACC_STATE[a]} FIN=${ACC_FINISHED[a]}"'
  ))
  expect_match(r$out, "RC=0")
  expect_match(r$out, "STATE=known FIN=FIRE,KITR,UPET", fixed = TRUE)
  expect_match(r$out, "3/3 WSGs accounted for", fixed = TRUE)
})

test_that("the mid-line fixture defeats the old anchored match", {
  # Keeps the fixture honest: if the line stops being one an anchored match
  # misses, the test above stops testing #347.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  log <- file.path(w, "logs", "run_a.log")
  writeLines(midline(c("FIRE", "KITR")), log)
  anchored <- system2("sed", c(
    "-nE",
    shQuote("s/^\\[wsg_run_one\\] ([A-Z]{4}) .*(done|SKIP).*/\\1/p"), shQuote(log)
  ),
  stdout = TRUE
  )
  expect_length(anchored, 0L)
  r <- run_hosts(w, sprintf("host_log_reported %s done | paste -sd, -", shQuote(log)))
  expect_equal(r$out, "FIRE,KITR")
})

test_that("a mid-line SKIP is accounted for and kept out of the bucket", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  log <- file.path(w, "logs", "run_a.log")
  writeLines(
    c(midline("ADMS"), midline("ZZZZ", "SKIP — no modeled species in this AOI")),
    log
  )
  put(w, "ssh_ip-a.out", db_answer("ADMS"))
  r <- run_hosts(w, c(
    sprintf("host_account a cypher@ip-a %s ADMS,ZZZZ && echo RC=0 || echo RC=$?", shQuote(log)),
    'echo "FIN=${ACC_FINISHED[a]} SKIP=${ACC_SKIP[a]}"'
  ))
  expect_match(r$out, "RC=0")
  expect_match(r$out, "FIN=ADMS SKIP=ZZZZ", fixed = TRUE)
})

test_that("a group not finished in the database is reported missing", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  log <- file.path(w, "logs", "run_a.log")
  # The log claims all three; the database is what counts.
  writeLines(sprintf("[wsg_run_one] %s done in 1 min", c("AAAA", "BBBB", "CCCC")), log)
  put(w, "ssh_ip-a.out", db_answer(c("AAAA", "BBBB")))
  r <- run_hosts(w, sprintf(
    "host_account a cypher@ip-a %s AAAA,BBBB,CCCC && echo RC=0 || echo RC=$?", shQuote(log)
  ))
  expect_match(r$out, "RC=1")
  expect_match(r$out, "not finished: CCCC", fixed = TRUE)
  expect_match(r$out, "done in the log, not closed in the database (consolidated anyway): CCCC", fixed = TRUE)
})

test_that("a database that does not answer is unknown, never complete", {
  skip_if_no_hosts_lib()
  cases <- list(
    truncated = c("__LNK_BEGIN__", "AAAA"),
    nothing = character(0),
    error_text = c("__LNK_BEGIN__", "ERROR:  relation does not exist", "__LNK_END__")
  )
  for (nm in names(cases)) {
    w <- hosts_world()
    put(w, "ssh_ip-a.out", cases[[nm]])
    put(w, "ssh_ip-a.rc", "0") # ssh over the tailnet can exit 0 regardless
    r <- run_hosts(w, c(
      "host_account a cypher@ip-a /nonexistent AAAA && echo RC=0 || echo RC=$?",
      'echo "STATE=${ACC_STATE[a]} FIN=[${ACC_FINISHED[a]}]"'
    ))
    expect_match(r$out, "RC=1", info = nm)
    expect_match(r$out, "STATE=unknown FIN=[]", fixed = TRUE, info = nm)
  }
})

test_that("a persist with no log table yet has finished nothing, knowably", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "host_account a cypher@ip-a /nonexistent AAAA || true",
    'echo "STATE=${ACC_STATE[a]}"'
  ))
  expect_match(r$out, "STATE=known", fixed = TRUE)
})

# Account for, then release, cyphers a and b after a (mock) consolidate.
account_release <- function(bucket = "") {
  c(
    "for ws in a b; do HOST_HOLD[$ws]=1;",
    sprintf('host_account $ws cypher@ip-$ws /nonexistent "%s" > /dev/null || true; done', bucket),
    sprintf('for ws in a b; do host_release $ws "%s"; done', bucket)
  )
}

test_that("a host with streams rows left after consolidate is not burned", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(c("XXXX", "YYYY")))
  put(w, "ssh_ip-a_streams.out", db_answer(character(0)))
  put(w, "ssh_ip-b.out", db_answer(c("PPPP", "QQQQ")))
  put(w, "ssh_ip-b_streams.out", db_answer("QQQQ")) # consolidate missed it
  put(w, "ssh_ip-b_mc.out", db_answer("QQQQ"))
  r <- run_hosts(w, c(
    account_release(),
    "burn_cyphers",
    "burn_cyphers", # idempotent: the EXIT trap calls it again
    'echo "KEPT_N=$KEPT_N"'
  ))
  expect_equal(burn_calls(w), "--workspace a")
  expect_match(r$out, "finished groups left after consolidate — KEEPING it (groups: QQQQ)",
    fixed = TRUE
  )
  expect_match(r$out, "HOSTS KEPT (1)", fixed = TRUE)
  expect_match(r$out, "KEPT_N=1", fixed = TRUE)
  k <- kept_tsv(w)
  expect_equal(k$workspace, "b")
  expect_equal(k$droplet, "cypher-b")
  expect_equal(k$groups, "QQQQ")
  expect_equal(k$groups_measured, "yes")
  expect_equal(k$run_uid, "T0-0000")
  expect_equal(k$schema, "fresh_test")
  expect_match(k$ip_command, "TF_WORKSPACE=b tofu output -raw droplet_ip", fixed = TRUE)
  expect_match(k$burn_command, "cypher_down.sh --workspace b", fixed = TRUE)
})

test_that("the release probe asks about every group the host ran or finished", {
  # Not only what consolidate took: a group the host finished outside its
  # bucket, or one its log names, must also be gone before it is burned.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  writeLines(midline("LOGD"), file.path(w, "logs", "run_a.log"))
  put(w, "ssh_ip-a.out", db_answer(c("DBFN")))
  put(w, "ssh_ip-a_streams.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    sprintf(
      "host_account a cypher@ip-a %s BUCK > /dev/null || true",
      shQuote(file.path(w, "logs", "run_a.log"))
    ),
    'echo "BUCKET=$(host_consolidate_bucket a)"',
    "host_release a BUCK"
  ), cyphers = "a")
  expect_match(r$out, "BUCKET=DBFN,LOGD", fixed = TRUE)
  stdin <- readLines(file.path(w, "stub", "ssh_ip-a.stdin"))
  sel <- grep("FROM fresh_test.streams", stdin, value = TRUE)
  expect_length(sel, 1L)
  expect_match(sel, "IN ('BUCK','DBFN','LOGD')", fixed = TRUE)
})

test_that("a lost run_uid still consolidates and holds by the log", {
  # LNK_RUN_UID not reaching a host leaves every log row with run_uid NULL,
  # so the database finds nothing. The log's done markers keep the groups in
  # the bucket, and rows left behind keep the host.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  log <- file.path(w, "logs", "run_a.log")
  writeLines(midline(c("AAAA", "BBBB")), log)
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  put(w, "ssh_ip-a_streams.out", db_answer(c("AAAA", "BBBB")))
  put(w, "ssh_ip-a_mc.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    sprintf("host_account a cypher@ip-a %s AAAA,BBBB > /dev/null || true", shQuote(log)),
    'echo "BUCKET=$(host_consolidate_bucket a)"',
    "host_release a AAAA,BBBB", "burn_cyphers"
  ), cyphers = "a")
  expect_match(r$out, "BUCKET=AAAA,BBBB", fixed = TRUE)
  expect_length(burn_calls(w), 0L)
  expect_equal(kept_tsv(w)$groups, "AAAA,BBBB")
})

test_that("a dispatch session that exited non-zero keeps the host", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_streams.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_RUN_RC[a]=255",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_match(k$reason, "dispatch session exited 255", fixed = TRUE)
  # Its work WAS consolidated and deleted from the host. The file must say
  # nothing is left, not list AAAA: consolidating AAAA again would delete the
  # dispatcher's copy first and copy nothing back.
  expect_equal(k$groups, "")
  # A dropped session may still be building there, so it is not settled.
  expect_equal(k$groups_measured, "unsettled")
  expect_match(r$out, "finished when probed: nothing", fixed = TRUE)
})

test_that("a missing streams table after consolidate is unknown, not empty", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_streams.out", c("__LNK_BEGIN__", "__LNK_NOTABLE__", "__LNK_END__"))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_match(k$reason, "did not answer after consolidate", fixed = TRUE)
  expect_equal(k$groups_measured, "no")
})

test_that("a missing log table is a host that has closed nothing", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", c("__LNK_BEGIN__", "__LNK_NOTABLE__", "__LNK_END__"))
  r <- run_hosts(w, c(
    "host_finished cypher@ip-a && echo RC=0 || echo RC=$?"
  ), cyphers = "a")
  expect_equal(r$out, "RC=0")
})

test_that("--keep-cyphers does not hide a host held for cause", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_streams.out", db_answer(character(0)))
  put(w, "ssh_ip-b.out", db_answer("BBBB"))
  put(w, "ssh_ip-b_streams.out", db_answer("BBBB"))
  put(w, "ssh_ip-b_mc.out", db_answer("BBBB"))
  r <- run_hosts(w, c(
    account_release(),
    "burn_cyphers",
    'echo "KEPT_N=$KEPT_N CAUSE=$KEPT_CAUSE_N"'
  ), keep = 1L)
  expect_length(burn_calls(w), 0L)
  expect_match(r$out, "KEPT_N=2 CAUSE=1", fixed = TRUE)
  k <- kept_tsv(w)
  expect_equal(k$reason[k$workspace == "a"], "--keep-cyphers")
  expect_equal(
    k$reason[k$workspace == "b"],
    "finished groups left after consolidate; --keep-cyphers"
  )
})

test_that("an unknown finished set is left out of consolidate and keeps the host", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  writeLines(midline("AAAA"), file.path(w, "logs", "run_a.log"))
  put(w, "ssh_ip-a.out", character(0))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    sprintf(
      "host_account a cypher@ip-a %s AAAA > /dev/null || true",
      shQuote(file.path(w, "logs", "run_a.log"))
    ),
    'echo "BUCKET=[$(host_consolidate_bucket a)]"',
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_match(r$out, "BUCKET=[]", fixed = TRUE)
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_match(k$reason, "unknown", fixed = TRUE)
  expect_equal(k$groups, "AAAA")
})

test_that("a database that stops answering after consolidate keeps the host", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  # no _streams fixture: the release probe gets nothing back
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  expect_match(kept_tsv(w)$reason, "did not answer after consolidate", fixed = TRUE)
})

test_that("the probe goes through docker exec on the host and asks for this run", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  run_hosts(w, "host_finished cypher@ip-a > /dev/null", cyphers = "a")
  argv <- readLines(file.path(w, "stub", "ssh_ip-a.argv"))
  expect_match(argv, "cypher@ip-a docker exec -i fresh-db psql -U postgres -d fwapg",
    fixed = TRUE
  )
  stdin <- paste(readLines(file.path(w, "stub", "ssh_ip-a.stdin")), collapse = "\n")
  expect_match(stdin, "FROM fresh_test.log WHERE run_uid = 'T0-0000' AND date_end IS NOT NULL",
    fixed = TRUE
  )
  expect_match(stdin, "to_regclass('fresh_test.log')", fixed = TRUE)
})

test_that("a burn that does not complete is retried and listed as kept", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "tofu_a.out", "digitalocean_droplet.cypher")
  r <- run_hosts(w, c("burn_cyphers", "burn_cyphers"), cyphers = "a")
  expect_equal(burn_calls(w), c("--workspace a", "--workspace a"))
  expect_match(r$out, "BURN INCOMPLETE", fixed = TRUE)
  expect_match(kept_tsv(w)$reason, "burn did not complete (1 tofu resources left)",
    fixed = TRUE
  )
})

test_that("an abort after dispatch keeps every held host", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c(
    "trap burn_cyphers EXIT",
    "for ws in a b; do HOST_HOLD[$ws]=1; done",
    "exit 3"
  ))
  expect_equal(r$status, 3L)
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_equal(k$workspace, c("a", "b"))
  expect_match(k$reason, "run stopped before consolidate released it", fixed = TRUE)
})

test_that("an abort before dispatch burns every host, as before", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c("trap burn_cyphers EXIT", "exit 1"))
  expect_equal(sort(burn_calls(w)), c("--workspace a", "--workspace b"))
  expect_null(kept_tsv(w))
  expect_match(r$out, "burn clean", fixed = TRUE)
})

test_that("--keep-cyphers keeps every host and records it", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, "burn_cyphers", keep = 1L)
  expect_length(burn_calls(w), 0L)
  expect_equal(kept_tsv(w)$reason, c("--keep-cyphers", "--keep-cyphers"))
})

test_that("a burned droplet doctl still lists fails the burn check", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "doctl.out", c("cypher-a", "something-else"))
  r <- run_hosts(w, "burn_cyphers", cyphers = "a")
  expect_match(r$out, "doctl still shows cypher-a", fixed = TRUE)
  expect_match(r$out, "BURN INCOMPLETE", fixed = TRUE)
})

test_that("droplet names follow the tofu workspace slug", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c("host_droplet_name default", "host_droplet_name job_1"))
  expect_equal(r$out, "cypher\ncypher-job-1")
})

test_that("pre-flight fails on a cypher already up in this run's workspaces", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c(
    "hosts_preflight_droplets $'cypher-a\\ncypher-job-9\\ncypher\\nweb-1' && echo RC=0 || echo RC=$?",
    "hosts_preflight_droplets $'web-1' && echo RC=0 || echo RC=$?"
  ))
  lines <- strsplit(r$out, "\n")[[1]]
  expect_equal(grep("^RC=", lines, value = TRUE), c("RC=1", "RC=0"))
  expect_match(r$out, "droplet cypher-a (workspace a) is already up", fixed = TRUE)
  expect_match(r$out, "cypher_down.sh --workspace a", fixed = TRUE)
  expect_match(r$out, "WARN: droplet cypher-job-9 is up", fixed = TRUE)
  expect_false(grepl("web-1", r$out, fixed = TRUE))
  # The long-lived default droplet is not a run's host.
  expect_false(grepl("droplet cypher is up", r$out, fixed = TRUE))
})

test_that("a failed group's partial rows neither hold the host nor get recovered", {
  # lnk_pipeline_run() pre-persists streams before access exists, so a group
  # that fails after it leaves streams rows and no mapping-code rows.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  log <- file.path(w, "logs", "run_a.log")
  writeLines(midline("AAAA"), log)
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_streams.out", db_answer("BBBB"))
  put(w, "ssh_ip-a_mc.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    sprintf("host_account a cypher@ip-a %s AAAA,BBBB > /dev/null || true", shQuote(log)),
    'echo "BUCKET=$(host_consolidate_bucket a)"',
    "host_release a AAAA,BBBB", "burn_cyphers"
  ), cyphers = "a")
  expect_match(r$out, "BUCKET=AAAA", fixed = TRUE)
  expect_equal(burn_calls(w), "--workspace a")
  expect_match(r$out,
    "partial groups left there (failed builds, not consolidated; rebuild them): BBBB",
    fixed = TRUE
  )
  expect_null(kept_tsv(w))
})

test_that("mapping-code rows mark a group finished when run_uid and log both fail", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  put(w, "ssh_ip-a_streams.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_PRE_STATE[a]=known",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_equal(k$groups, "AAAA")
  expect_equal(k$groups_partial, "")
})

test_that("an aborted run's report says its groups may still be building", {
  # A killed driver runs its EXIT trap while the ssh session it started keeps
  # building on the host, so nothing unfinished there may be called partial.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a_streams.out", db_answer(c("AAAA", "BBBB")))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  r <- run_hosts(w, c(
    "trap burn_cyphers EXIT",
    "HOST_HOLD[a]=1; HOST_BUCKET[a]=AAAA,BBBB; HOST_PRE_STATE[a]=known; unset 'HOST_RUN_RC[a]'",
    "exit 1"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_equal(k$groups, "AAAA")
  expect_equal(k$groups_partial, "BBBB")
  expect_equal(k$groups_measured, "unsettled")
  expect_match(r$out, "NOT finished when probed (may still be building): BBBB", fixed = TRUE)
  expect_false(grepl("partial, do NOT consolidate", r$out, fixed = TRUE))
  # The recompute never ran on this path.
  expect_match(r$out, "recompute did NOT run", fixed = TRUE)
})

test_that("a settled host's report names partial groups, and the recompute that ran", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a_streams.out", db_answer(c("AAAA", "BBBB")))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_BUCKET[a]=AAAA,BBBB; HOST_PRE_STATE[a]=known; RECOMPUTE_RAN=1",
    "burn_cyphers"
  ), cyphers = "a")
  k <- kept_tsv(w)
  expect_equal(k$groups_measured, "yes")
  expect_match(r$out, "partial, do NOT consolidate: BBBB", fixed = TRUE)
  expect_match(r$out, "recompute ran WITHOUT these groups", fixed = TRUE)
  expect_match(r$out, "wsg_recompute_one.R", fixed = TRUE)
})

test_that("mapping-code rows from the image do not count as finished", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  # Before dispatch the host already holds AAAA (warm image).
  put(w, "ssh_ip-a_streams.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_BUCKET[a]=AAAA; host_baseline a",
    'echo "PRE=${HOST_PRE[a]} STATE=${HOST_PRE_STATE[a]}"',
    "HOST_HOLD[a]=1",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA"
  ), cyphers = "a")
  expect_match(r$out, "PRE=AAAA STATE=known", fixed = TRUE)
  expect_match(r$out, "rows before dispatch (from its image) for: AAAA", fixed = TRUE)
  # Nothing this run finished it, and it had rows before: unknown provenance,
  # which holds the host and is never called partial.
  expect_match(r$out, "unknown provenance", fixed = TRUE)
  expect_false(grepl("partial groups left there", r$out, fixed = TRUE))
})

test_that("with no baseline, mapping-code rows are not a finish signal", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_BUCKET[a]=AAAA; host_baseline a", # no _streams fixture: probe fails
    'echo "STATE=${HOST_PRE_STATE[a]}"'
  ), cyphers = "a")
  expect_match(r$out, "STATE=unknown", fixed = TRUE)
  expect_match(r$out, "mapping-code rows will not count as finished", fixed = TRUE)
})

test_that("a missing mapping-code table is unknown, not partial", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  put(w, "ssh_ip-a_streams.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_mc.out", c("__LNK_BEGIN__", "__LNK_NOTABLE__", "__LNK_END__"))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  expect_match(kept_tsv(w)$reason, "did not answer after consolidate", fixed = TRUE)
})

test_that("with no baseline, mapping-code rows hold the host but are not recovered", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  put(w, "ssh_ip-a_streams.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_PRE_STATE[a]=unknown",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  k <- kept_tsv(w)
  expect_match(k$reason, "unknown provenance", fixed = TRUE)
  expect_equal(k$groups, "")
  expect_equal(k$groups_partial, "")
  expect_equal(k$groups_unknown, "AAAA")
})

test_that("a driver killed while waiting on a host sees that host unsettled", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a_streams.out", db_answer("BBBB"))
  put(w, "ssh_ip-a_mc.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "unset 'HOST_RUN_RC[a]'; HOST_HOLD[a]=1; HOST_BUCKET[a]=BBBB; HOST_PRE_STATE[a]=known",
    "trap 'burn_cyphers; echo \"RC=[${HOST_RUN_RC[a]:-unset}]\"' EXIT",
    "sleep 30 & child=$!",
    "( sleep 1; kill -TERM $$ ) &",
    'host_wait a "$child"'
  ), cyphers = "a")
  expect_match(r$out, "RC=[unset]", fixed = TRUE)
  expect_equal(kept_tsv(w)$groups_measured, "unsettled")
  expect_false(grepl("partial, do NOT consolidate", r$out, fixed = TRUE))
})

test_that("host_wait records the session's own status", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c(
    "( exit 7 ) & p=$!",
    'host_wait a "$p" || true',
    "( exit 0 ) & q=$!",
    'host_wait b "$q"',
    'echo "A=${HOST_RUN_RC[a]} B=${HOST_RUN_RC[b]}"'
  ))
  expect_match(r$out, "A=7 B=0", fixed = TRUE)
})

test_that("a report from the trap reads this run's finish signals itself", {
  # The trap can fire after a host's session ended 0 but before accounting:
  # a group rebuilt over an image's rows must still read as finished.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  writeLines(midline("AAAA"), file.path(w, "logs", "T0_run_a.log"))
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_streams.out", db_answer(c("AAAA", "BBBB")))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_BUCKET[a]=AAAA,BBBB; HOST_PRE_STATE[a]=known; HOST_PRE[a]=AAAA",
    "burn_cyphers"
  ), cyphers = "a")
  k <- kept_tsv(w)
  expect_equal(k$groups, "AAAA")
  expect_equal(k$groups_partial, "BBBB")
})

test_that("the baseline counts an image's mapping-code rows too", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a_streams.out", db_answer(character(0)))
  put(w, "ssh_ip-a_mc.out", db_answer("AAAA"))
  r <- run_hosts(w, c(
    "HOST_BUCKET[a]=AAAA; host_baseline a",
    'echo "PRE=${HOST_PRE[a]}"'
  ), cyphers = "a")
  expect_match(r$out, "PRE=AAAA", fixed = TRUE)
})

test_that("a driver killed during one host's consolidate sees that host unsettled, the other settled", {
  # Consolidate copies one host at a time since link#369, so CONSOLIDATING
  # names it; a host already done is measured as it stands.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  for (h in c("a", "b")) {
    put(w, sprintf("ssh_ip-%s.out", h), db_answer(toupper(strrep(h, 4))))
    put(w, sprintf("ssh_ip-%s_streams.out", h), db_answer(toupper(strrep(h, 4))))
    put(w, sprintf("ssh_ip-%s_mc.out", h), db_answer(toupper(strrep(h, 4))))
  }
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_BUCKET[a]=AAAA; HOST_PRE_STATE[a]=known",
    "HOST_HOLD[b]=1; HOST_BUCKET[b]=BBBB; HOST_PRE_STATE[b]=known",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_account b cypher@ip-b /nonexistent BBBB > /dev/null || true",
    "trap burn_cyphers EXIT",
    "( sleep 1; kill -TERM $$ ) &",
    "CONSOLIDATING=a",
    "sleep 30",
    "CONSOLIDATING="
  ))
  k <- kept_tsv(w)
  expect_identical(k$workspace, c("a", "b"))
  expect_identical(k$groups_measured, c("unsettled", "yes"))
  expect_match(r$out, "consolidate was still running against it", fixed = TRUE)
})

test_that("an unknown group's reason names the rule that made it unknown", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer(character(0)))
  put(w, "ssh_ip-a_streams.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_mc.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    "HOST_HOLD[a]=1; HOST_PRE_STATE[a]=known; HOST_PRE[a]=AAAA",
    "host_account a cypher@ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  k <- kept_tsv(w)
  expect_match(k$reason, "rows from before dispatch, no finish signal of this run",
    fixed = TRUE
  )
  expect_false(grepl("no baseline", r$out, fixed = TRUE))
})

test_that("a host whose consolidate failed keeps it, and says so, while its groups are left there", {
  # link#358: the driver carries on after a refused source and calls
  # host_release on every host. The measured state still decides.
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  put(w, "ssh_ip-a_streams.out", db_answer(character(0)))
  put(w, "ssh_ip-b.out", db_answer("BBBB"))
  put(w, "ssh_ip-b_streams.out", db_answer("BBBB"))
  put(w, "ssh_ip-b_mc.out", db_answer("BBBB"))
  r <- run_hosts(w, c(
    "HOST_CONS_FAIL[a]=copy_empty; HOST_CONS_FAIL[b]=dest_log_newer",
    account_release(),
    "burn_cyphers"
  ))
  # a failed too, but nothing it finished is left there: nothing to lose.
  expect_equal(burn_calls(w), "--workspace a")
  k <- kept_tsv(w)
  expect_equal(k$workspace, "b")
  expect_match(k$reason, "consolidate failed at stage dest_log_newer", fixed = TRUE)
  expect_equal(k$groups, "BBBB")
})

# -- Persistent workers (link#376) -------------------------------------------
# A worker is reached by its own ssh target and is never spun or burned. It is
# held from dispatch like a cloud host, and a held worker is reported kept
# whether or not the run spun any cyphers.

# Worker `worker1` at target `wk` beside the run's cyphers, if any.
worker_setup <- function(held = 1L) {
  c(
    "HOST_ARR+=(worker1); HOST_KIND[worker1]=worker; HOST_SSH[worker1]=wk",
    "HOST_RUN_RC[worker1]=0; HOST_BUCKET[worker1]=WWWW; WORKERS_UP=1",
    if (!is.na(held)) sprintf("HOST_HOLD[worker1]=%d", held)
  )
}

test_that("a held worker is reported kept on a run with no cyphers", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_wk.out", db_answer("WWWW"))
  put(w, "ssh_wk_streams.out", db_answer("WWWW")) # consolidate missed it
  put(w, "ssh_wk_mc.out", db_answer("WWWW"))
  r <- run_hosts(w, c(
    worker_setup(),
    "host_account worker1 wk /nonexistent WWWW > /dev/null || true",
    "host_release worker1 WWWW",
    "burn_cyphers",
    'echo "KEPT_N=$KEPT_N CAUSE=$KEPT_CAUSE_N"'
  ), cyphers = character(0), cyphers_up = 0L)
  expect_length(burn_calls(w), 0L)
  expect_match(r$out, "KEPT_N=1 CAUSE=1", fixed = TRUE)
  k <- kept_tsv(w)
  expect_identical(k$workspace, "worker1")
  expect_identical(k$droplet, "-")
  expect_identical(k$groups, "WWWW")
  expect_match(k$burn_command, "^none")
  # Its target is the operator's; no address and no tofu command for it.
  expect_no_match(k$ip_command, "tofu", fixed = TRUE)
  expect_no_match(paste(readLines(file.path(w, "logs", "T0_kept_hosts.tsv")), collapse = "\n"),
                  "\\bwk\\b")
  expect_no_match(r$out, "cypher_down.sh --workspace worker1", fixed = TRUE)
})

test_that("a released worker is neither burned nor listed as kept", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_wk.out", db_answer("WWWW"))
  put(w, "ssh_wk_streams.out", db_answer(character(0)))
  r <- run_hosts(w, c(
    worker_setup(),
    "host_account worker1 wk /nonexistent WWWW > /dev/null || true",
    "host_release worker1 WWWW",
    "burn_cyphers", "burn_cyphers",
    'echo "KEPT_N=$KEPT_N HOLD=${HOST_HOLD[worker1]} BURNED=${CY_BURNED[worker1]:-unset}"'
  ), cyphers = character(0), cyphers_up = 0L, keep = 1L)
  expect_length(burn_calls(w), 0L)
  expect_null(kept_tsv(w))
  # --keep-cyphers is about cloud hosts; it does not keep a worker.
  expect_match(r$out, "KEPT_N=0 HOLD=0 BURNED=unset", fixed = TRUE)
  expect_match(r$out, "may be released", fixed = TRUE)
})

test_that("the trap before dispatch burns the cyphers and leaves a worker alone", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c(worker_setup(held = NA), "burn_cyphers"), cyphers = "b")
  expect_identical(burn_calls(w), "--workspace b")
  expect_null(kept_tsv(w))
})

test_that("beside cyphers, only the cyphers are burned and a held worker is kept", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c(worker_setup(), "burn_cyphers"), cyphers = "b")
  expect_identical(burn_calls(w), "--workspace b")
  k <- kept_tsv(w)
  expect_identical(k$workspace, "worker1")
  expect_match(k$reason, "run stopped before consolidate released it", fixed = TRUE)
})

# A released worker's partial groups (failed builds whose pre-persist left
# rows) are dropped from its persist tables, so the next run's prior-rows
# check finds it clean. Its log rows stay: the open row is the only record of
# the failure.
drop_setup <- function(pre_state = "known", pre = "") {
  c(
    worker_setup(),
    sprintf("HOST_PRE_STATE[worker1]=%s; HOST_PRE[worker1]=%s", pre_state, pre),
    "host_account worker1 wk /nonexistent WWWW,PPPP > /dev/null || true",
    "host_release worker1 WWWW,PPPP",
    "host_drop_partials worker1 && echo DROP_RC=0 || echo DROP_RC=$?"
  )
}

test_that("a released worker's partial groups are dropped from its persist tables only", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_wk.out", db_answer("WWWW"))
  put(w, "ssh_wk_streams.out", db_answer("PPPP"))
  put(w, "ssh_wk_mc.out", db_answer(character(0)))
  put(w, "ssh_wk_drop.out", c("__LNK_BEGIN__", "DELETE 4", "DELETE 2", "__LNK_END__"))
  r <- run_hosts(w, drop_setup(), cyphers = character(0), cyphers_up = 0L)
  expect_match(r$out, "DROP_RC=0", fixed = TRUE)
  expect_match(r$out, "dropped partial groups PPPP", fixed = TRUE)
  stdin <- paste(readLines(file.path(w, "stub", "ssh_wk.stdin")), collapse = "\n")
  expect_match(stdin, "{PPPP}", fixed = TRUE)
  expect_match(stdin, "!~ '^log(_|$)'", fixed = TRUE)
  expect_match(stdin, "table_schema = 'fresh_test'", fixed = TRUE)
  # The drop names the partial group only, never one it finished.
  drop <- grep("gexec", strsplit(stdin, "\n")[[1]], value = TRUE, fixed = TRUE)
  expect_length(drop, 1L)
  expect_no_match(drop, "WWWW", fixed = TRUE)
})

test_that("partial groups are not dropped where the worker's rows predate the run", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_wk.out", db_answer("WWWW"))
  put(w, "ssh_wk_streams.out", db_answer("PPPP"))
  put(w, "ssh_wk_mc.out", db_answer(character(0)))
  for (st in list(c("unknown", ""), c("known", "QQQQ"))) {
    unlink(file.path(w, "stub", "ssh_wk.stdin"))
    r <- run_hosts(w, drop_setup(st[1], st[2]), cyphers = character(0), cyphers_up = 0L)
    expect_match(r$out, "DROP_RC=0", fixed = TRUE)
    expect_match(r$out, "not dropping", fixed = TRUE)
    stdin <- paste(readLines(file.path(w, "stub", "ssh_wk.stdin")), collapse = "\n")
    expect_no_match(stdin, "gexec", fixed = TRUE)
  }
})

test_that("a drop the worker did not finish says it fails closed", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_wk.out", db_answer("WWWW"))
  put(w, "ssh_wk_streams.out", db_answer("PPPP"))
  put(w, "ssh_wk_mc.out", db_answer(character(0)))
  put(w, "ssh_wk_drop.out", c("__LNK_BEGIN__", "DELETE 4"))  # stopped mid-way
  r <- run_hosts(w, drop_setup(), cyphers = character(0), cyphers_up = 0L)
  expect_match(r$out, "DROP_RC=1", fixed = TRUE)
  expect_match(r$out, "next run refuses", fixed = TRUE)
})

test_that("a cloud host's partial groups are never dropped (it is burned)", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  r <- run_hosts(w, c("HOST_HOLD[a]=0; HOST_PARTIAL[a]=PPPP",
                      "host_drop_partials a && echo DROP_RC=0"), cyphers = "a")
  expect_match(r$out, "DROP_RC=0", fixed = TRUE)
  expect_false(file.exists(file.path(w, "stub", "ssh_ip-a.stdin")))
})

test_that("the partial drop's SQL deletes persist rows and keeps log rows (live)", {
  skip_if_no_hosts_lib()
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if(!identical(as.character(info$port), "5432") ||
            !info$host %in% c("localhost", "127.0.0.1"),
          "not the local docker fwapg the lib's local route reads")
  skip_if(!nzchar(Sys.which("psql")), "psql not on PATH")
  sc <- paste0("lnk_test_drop_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc)))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", sc))
  for (t in c("streams", "streams_habitat_bt", "log", "log_input")) {
    DBI::dbExecute(conn, sprintf("CREATE TABLE %s.%s (watershed_group_code text)", sc, t))
    DBI::dbExecute(conn, sprintf("INSERT INTO %s.%s VALUES ('PPPP'), ('WWWW')", sc, t))
  }
  w <- hosts_world()
  unlink(file.path(w, "bin", "psql")) # the real psql, through the local route
  r <- run_hosts(w, c(
    sprintf("SCHEMA=%s", sc),
    "HOST_ARR=(worker1); HOST_KIND[worker1]=worker; HOST_SSH[worker1]=local",
    "HOST_RUN_RC[worker1]=0; HOST_HOLD[worker1]=0; HOST_PARTIAL[worker1]=PPPP",
    "HOST_PRE_STATE[worker1]=known; HOST_PRE[worker1]=",
    "host_drop_partials worker1 && echo DROP_RC=0 || echo DROP_RC=$?"
  ), cyphers = character(0), cyphers_up = 0L)
  expect_match(r$out, "DROP_RC=0", fixed = TRUE)
  left <- function(t) DBI::dbGetQuery(conn, sprintf(
    "SELECT watershed_group_code FROM %s.%s ORDER BY 1", sc, t))$watershed_group_code
  expect_identical(left("streams"), "WWWW")
  expect_identical(left("streams_habitat_bt"), "WWWW")
  expect_identical(left("log"), c("PPPP", "WWWW"))
  expect_identical(left("log_input"), c("PPPP", "WWWW"))
})
