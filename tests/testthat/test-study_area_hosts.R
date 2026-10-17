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

# The lib needs bash >= 4 (assoc arrays); macOS /bin/bash is 3.2.
hosts_bash <- function() {
  cands <- unique(c(
    "/opt/homebrew/bin/bash", "/usr/local/bin/bash",
    unname(Sys.which("bash"))
  ))
  for (b in cands[nzchar(cands) & file.exists(cands)]) {
    v <- suppressWarnings(system2(b, c("-c", shQuote("echo ${BASH_VERSINFO[0]}")),
      stdout = TRUE, stderr = FALSE
    ))
    n <- suppressWarnings(as.integer(v))
    if (length(n) == 1L && !is.na(n) && n >= 4L) {
      return(b)
    }
  }
  ""
}

# Absent lib (R CMD check, installed tests) skips. A present lib with no
# bash >= 4 FAILS: the driver needs bash >= 4 too, and nothing in CI runs
# these, so a silent skip would read as coverage.
skip_if_no_hosts_lib <- function() {
  testthat::skip_if_not(file.exists(hosts_lib()), "data-raw/study_area_hosts.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 4 found; the study_area_hosts.sh tests cannot run")
  }
}

# A scratch world: stub binaries, a mock cypher_down.sh, empty dirs for the
# tofu workspace and the logs.
hosts_world <- function(env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  for (sub in c("bin", "stub", "cypher", "tf", "logs")) {
    dir.create(file.path(d, sub))
  }
  stub <- function(name, body) {
    p <- file.path(d, "bin", name)
    writeLines(c("#!/bin/sh", body), p)
    Sys.chmod(p, "755")
  }
  # ssh: the host is the cypher@ argument. Records argv and stdin, so a test
  # can assert the remote route, and answers from that host's fixture: the
  # `_streams` one for a streams query, the plain one for a log query.
  stub("ssh", c(
    'host=""; for a in "$@"; do case "$a" in cypher@*) host="${a#cypher@}" ;; esac; done',
    sprintf('s="%s/stub/ssh_$host"', d),
    'printf "%s\\n" "$*" >> "$s.argv"',
    'in=$(cat); printf "%s\\n" "$in" >> "$s.stdin"',
    'case "$in" in *".streams WHERE"*) f="${s}_streams.out" ;; *) f="$s.out" ;; esac',
    '[ -f "$f" ] && cat "$f"',
    '[ -f "$s.rc" ] && exit "$(cat "$s.rc")"',
    "exit 0"
  ))
  stub("psql", c(
    "cat > /dev/null",
    sprintf(
      '[ -f "%s/stub/psql_local.out" ] && cat "%s/stub/psql_local.out"',
      d, d
    ),
    "exit 0"
  ))
  # tofu: `state list` prints that workspace's fixture (none = destroyed).
  stub("tofu", sprintf(
    '[ -f "%s/stub/tofu_$TF_WORKSPACE.out" ] && cat "%s/stub/tofu_$TF_WORKSPACE.out"; exit 0',
    d, d
  ))
  stub("doctl", sprintf(
    '[ -f "%s/stub/doctl.out" ] && cat "%s/stub/doctl.out"; exit 0',
    d, d
  ))
  down <- file.path(d, "cypher", "cypher_down.sh")
  writeLines(
    c("#!/bin/sh", sprintf('echo "$*" >> "%s/stub/burn_calls"', d)),
    down
  )
  Sys.chmod(down, "755")
  d
}

# What host_finished reads back from a host's database.
db_answer <- function(wsgs) c("__LNK_BEGIN__", wsgs, "__LNK_END__")

put <- function(world, name, lines) {
  writeLines(lines, file.path(world, "stub", name))
}

burn_calls <- function(world) {
  p <- file.path(world, "stub", "burn_calls")
  if (file.exists(p)) readLines(p) else character(0)
}

kept_tsv <- function(world) {
  p <- file.path(world, "logs", "T0_kept_hosts.tsv")
  if (!file.exists(p)) {
    return(NULL)
  }
  utils::read.delim(p,
    quote = "", na.strings = character(),
    comment.char = "", stringsAsFactors = FALSE
  )
}

# Run `body` after sourcing the lib with the driver's globals set. Returns the
# combined output and the exit status.
run_hosts <- function(world, body, cyphers = c("a", "b"), keep = 0L,
                      cyphers_up = 1L) {
  script <- file.path(world, "run.sh")
  writeLines(c(
    "set -euo pipefail",
    sprintf("source %s", shQuote(hosts_lib())),
    "declare -A CY_IP CY_RUN_RC CY_HOLD CY_BURNED CY_UNCONS CY_WHY",
    "declare -A ACC_STATE ACC_FINISHED ACC_DONE_LOG ACC_SKIP",
    "SCHEMA=fresh_test; RUN_UID=T0-0000; TS=T0",
    sprintf(
      "LOG_DIR=%s; CYPHER_DIR=%s; CYPHER_TF=%s",
      shQuote(file.path(world, "logs")), shQuote(file.path(world, "cypher")),
      shQuote(file.path(world, "tf"))
    ),
    sprintf("KEEP_CYPHERS=%d; CYPHERS_UP=%d", keep, cyphers_up),
    sprintf("CY_WS_ARR=(%s)", paste(cyphers, collapse = " ")),
    'for ws in "${CY_WS_ARR[@]}"; do CY_IP[$ws]="ip-$ws"; CY_RUN_RC[$ws]=0; done',
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
      "host_account a ip-a %s FIRE,KITR,UPET && echo RC=0 || echo RC=$?",
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
    sprintf("host_account a ip-a %s ADMS,ZZZZ && echo RC=0 || echo RC=$?", shQuote(log)),
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
    "host_account a ip-a %s AAAA,BBBB,CCCC && echo RC=0 || echo RC=$?", shQuote(log)
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
      "host_account a ip-a /nonexistent AAAA && echo RC=0 || echo RC=$?",
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
    "host_account a ip-a /nonexistent AAAA || true",
    'echo "STATE=${ACC_STATE[a]}"'
  ))
  expect_match(r$out, "STATE=known", fixed = TRUE)
})

# Account for, then release, cyphers a and b after a (mock) consolidate.
account_release <- function(bucket = "") {
  c(
    "for ws in a b; do CY_HOLD[$ws]=1;",
    sprintf('host_account $ws ip-$ws /nonexistent "%s" > /dev/null || true; done', bucket),
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
  r <- run_hosts(w, c(
    account_release(),
    "burn_cyphers",
    "burn_cyphers", # idempotent: the EXIT trap calls it again
    'echo "KEPT_N=$KEPT_N"'
  ))
  expect_equal(burn_calls(w), "--workspace a")
  expect_match(r$out, "streams rows left after consolidate — KEEPING it (groups: QQQQ)",
    fixed = TRUE
  )
  expect_match(r$out, "HOSTS KEPT (1)", fixed = TRUE)
  expect_match(r$out, "KEPT_N=1", fixed = TRUE)
  k <- kept_tsv(w)
  expect_equal(k$workspace, "b")
  expect_equal(k$droplet, "cypher-b")
  expect_equal(k$groups, "QQQQ")
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
    "CY_HOLD[a]=1",
    sprintf(
      "host_account a ip-a %s BUCK > /dev/null || true",
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
  r <- run_hosts(w, c(
    "CY_HOLD[a]=1",
    sprintf("host_account a ip-a %s AAAA,BBBB > /dev/null || true", shQuote(log)),
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
    "CY_HOLD[a]=1; CY_RUN_RC[a]=255",
    "host_account a ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  expect_match(kept_tsv(w)$reason, "dispatch session exited 255", fixed = TRUE)
})

test_that("an unknown finished set is left out of consolidate and keeps the host", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  writeLines(midline("AAAA"), file.path(w, "logs", "run_a.log"))
  put(w, "ssh_ip-a.out", character(0))
  r <- run_hosts(w, c(
    "CY_HOLD[a]=1",
    sprintf(
      "host_account a ip-a %s AAAA > /dev/null || true",
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
    "CY_HOLD[a]=1",
    "host_account a ip-a /nonexistent AAAA > /dev/null || true",
    "host_release a AAAA", "burn_cyphers"
  ), cyphers = "a")
  expect_length(burn_calls(w), 0L)
  expect_match(kept_tsv(w)$reason, "did not answer after consolidate", fixed = TRUE)
})

test_that("the probe goes through docker exec on the host and asks for this run", {
  skip_if_no_hosts_lib()
  w <- hosts_world()
  put(w, "ssh_ip-a.out", db_answer("AAAA"))
  run_hosts(w, "host_finished ip-a > /dev/null", cyphers = "a")
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
    "for ws in a b; do CY_HOLD[$ws]=1; done",
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
