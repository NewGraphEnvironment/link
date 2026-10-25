# data-raw/study_area_legs.sh: each cloud host is consolidated and burned when
# its own leg ends, while the other legs keep modelling (link#369). The lib is
# bash, so each test runs it in a bash process with real background "legs"
# (sleeps of different lengths), the stub hosts of helper-study_area_hosts.R,
# a stub consolidate that records when it ran, and a mock cypher_down.sh that
# records when it burned.
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the libs are absent and
# these skip; devtools::test() from the source tree runs them.

# LNK_TEST_LEGS_LIB points the tests at a mutant copy of study_area_legs.sh
# (proving they fail).
legs_libs <- function() {
  p <- vapply(c("study_area_hosts.sh", "study_area_finish.sh", "study_area_phases.sh",
                "study_area_legs.sh"), function(f) {
    normalizePath(testthat::test_path("..", "..", "data-raw", f), mustWork = FALSE)
  }, character(1))
  alt <- Sys.getenv("LNK_TEST_LEGS_LIB")
  if (nzchar(alt)) p[["study_area_legs.sh"]] <- normalizePath(alt, mustWork = FALSE)
  p
}

skip_if_no_legs_lib <- function() {
  testthat::skip_if_not(all(file.exists(legs_libs())), "data-raw/study_area_*.sh absent")
  if (!nzchar(hosts_bash())) {
    testthat::fail("no bash >= 5.1 found; the study_area_legs.sh tests cannot run")
  }
}

now_cmd <- "perl -MTime::HiRes=time -e 'printf \"%.3f\\n\", time'"

# The stub world, plus: a consolidate stub (CONSOLIDATE_RSCRIPT) that reads the
# host and outcome path from the R program, behaves as stub/cons_<host>.mode
# says (ok, refuse:<stage>, die, ok_exit1), and on ok and ok_exit1 empties the
# host's streams answer (consolidate deletes what it copied at the source;
# ok_exit1 is R dying after that cleanup); and a
# cypher_down.sh that also records the time of each burn.
legs_world <- function(env = parent.frame()) {
  d <- hosts_world(env)
  st <- file.path(d, "stub")
  cons <- file.path(d, "bin", "cons_stub")
  writeLines(c(
    "#!/bin/bash",
    'prog="$2"',
    "host=$(printf '%s\\n' \"$prog\" | sed -n \"s/.*host = 'cypher@\\([^']*\\)'.*/\\1/p\" | head -1)",
    "tsv=$(printf '%s\\n' \"$prog\" | sed -n \"s/.*write.table(out, '\\([^']*\\)'.*/\\1/p\" | head -1)",
    sprintf('st=%s', shQuote(st)),
    sprintf('echo "$(%s) start $host" >> "$st/cons_calls"', now_cmd),
    'printf "%s\\n" "$prog" > "$st/cons_prog_$host"',
    '[ -f "$st/cons_$host.sleep" ] && sleep "$(cat "$st/cons_$host.sleep")"',
    'mode=ok; [ -f "$st/cons_$host.mode" ] && mode=$(cat "$st/cons_$host.mode")',
    "hdr='host\\tok\\tstage\\tgroups\\n'",
    "rc=0",
    'case "$mode" in',
    '  ok) printf "${hdr}cypher@%s\\tTRUE\\tcomplete\\t\\n" "$host" > "$tsv"',
    '      printf "__LNK_BEGIN__\\n__LNK_END__\\n" > "$st/ssh_${host}_streams.out" ;;',
    '  refuse:*) printf "${hdr}cypher@%s\\tFALSE\\t%s\\tAAAA\\n" "$host" "${mode#refuse:}" > "$tsv"; rc=1 ;;',
    '  die) rc=1 ;;',
    '  ok_exit1) printf "${hdr}cypher@%s\\tTRUE\\tcomplete\\t\\n" "$host" > "$tsv"',
    '      printf "__LNK_BEGIN__\\n__LNK_END__\\n" > "$st/ssh_${host}_streams.out"; rc=1 ;;',
    'esac',
    sprintf('echo "$(%s) end $host" >> "$st/cons_calls"', now_cmd),
    'exit "$rc"'
  ), cons)
  Sys.chmod(cons, "755")
  writeLines(c(
    "#!/bin/sh",
    sprintf('echo "$*" >> "%s/burn_calls"', st),
    sprintf('echo "$(%s) $*" >> "%s/burn_times"', now_cmd, st)
  ), file.path(d, "cypher", "cypher_down.sh"))
  d
}

# A host that finished `wsgs` and still holds them before consolidate.
legs_host <- function(world, h, wsgs) {
  put(world, sprintf("ssh_ip-%s.out", h), db_answer(wsgs))
  put(world, sprintf("ssh_ip-%s_streams.out", h), db_answer(wsgs))
  put(world, sprintf("ssh_ip-%s_mc.out", h), db_answer(wsgs))
}

# Run `body` with all four libs sourced and the driver's globals set. `legs`
# names each cypher's leg length in seconds; `disp` the dispatcher's. Each leg
# appends "<time> leg_end <who>" to stub/events as it ends.
run_legs <- function(world, body, legs = c(a = 1), disp = 2, buckets = NULL,
                     disp_bucket = "ZZZZ", leg_tail = list()) {
  cy <- names(legs)
  if (is.null(buckets)) buckets <- stats::setNames(toupper(strrep(cy, 4)), cy)
  st <- file.path(world, "stub")
  leg <- function(who, secs) {
    tail <- leg_tail[[who]] %||% ":"
    sprintf("( sleep %s; %s; echo \"$(%s) leg_end %s\" >> %s/events ) &",
            secs, tail, now_cmd, who, shQuote(st))
  }
  script <- file.path(world, "run.sh")
  writeLines(c(
    "set -euo pipefail",
    sprintf("source %s", shQuote(legs_libs())),
    "SCHEMA=fresh_test; RUN_UID=T0-0000; TS=T0",
    sprintf("LOG_DIR=%s; CYPHER_DIR=%s; CYPHER_TF=%s; REPO_ROOT=%s",
            shQuote(file.path(world, "logs")), shQuote(file.path(world, "cypher")),
            shQuote(file.path(world, "tf")), shQuote(world)),
    "KEEP_CYPHERS=0; CYPHERS_UP=1; COMPLETE_FAIL=0; CONS_FAILED=''; CONS_EXCLUDED=''",
    sprintf("CONSOLIDATE_RSCRIPT=%s", shQuote(file.path(world, "bin", "cons_stub"))),
    'CONS_STATE="$LOG_DIR/T0_consolidate_state.tsv"; RUN_WSGS_TSV="$LOG_DIR/T0_run_wsgs.tsv"',
    'phases_init "$LOG_DIR/T0_phases.tsv"',
    sprintf("DISP_BUCKET=%s", disp_bucket),
    sprintf("HOST_ARR=(%s)", paste(cy, collapse = " ")),
    sprintf(paste0('CY_IP[%s]="ip-%s"; HOST_SSH[%s]="cypher@ip-%s"; HOST_HOLD[%s]=1; ',
                   "HOST_BUCKET[%s]=%s; HOST_PRE_STATE[%s]=known"),
            cy, cy, cy, cy, cy, cy, buckets[cy], cy),
    leg("dispatcher", disp), "LOCAL_PID=$!",
    unlist(lapply(cy, function(h) c(leg(h, legs[[h]]), sprintf("HOST_LEG_PID[%s]=$!", h)))),
    body
  ), script)
  out <- withr::with_envvar(
    c(PATH = paste(file.path(world, "bin"), Sys.getenv("PATH"), sep = ":")),
    # A loop that never ends (a pid re-returned forever) fails, not hangs.
    suppressWarnings(system2(hosts_bash(), script, stdout = TRUE, stderr = TRUE,
                             timeout = 60))
  )
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

# "<time> <what> <who>" lines -> data frame.
events <- function(world, file) {
  p <- file.path(world, "stub", file)
  if (!file.exists(p)) return(data.frame(t = numeric(0), what = character(0), who = character(0)))
  x <- strsplit(readLines(p), " ")
  data.frame(t = as.numeric(vapply(x, `[`, "", 1)),
             what = vapply(x, `[`, "", 2),
             who = vapply(x, function(v) v[length(v)], ""))
}
when <- function(df, what, who) df$t[df$what == what & df$who == who]

test_that("a host that ends early is consolidated and burned while a longer leg still models", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  legs_host(w, "b", "BBBB")
  r <- run_legs(w, "legs_wait", legs = c(a = 0.5, b = 5), disp = 3)
  expect_equal(r$status, 0L, info = r$out)
  ev <- events(w, "events")
  burns <- events(w, "burn_times")
  expect_equal(sort(burns$who), c("a", "b"))
  # The point of #369: a is gone before either longer leg has ended.
  expect_lt(when(burns, "--workspace", "a"), when(ev, "leg_end", "dispatcher"))
  expect_lt(when(burns, "--workspace", "a"), when(ev, "leg_end", "b"))
  cons <- events(w, "cons_calls")
  expect_identical(cons$who[cons$what == "start"], c("ip-a", "ip-b"))
  expect_null(kept_tsv(w))
  st <- utils::read.delim(file.path(w, "logs", "T0_consolidate_state.tsv"), colClasses = "character")
  expect_identical(paste(st$workspace, st$wsg, st$state), c("a AAAA ok", "b BBBB ok"))
  expect_true(all(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$", st$state_utc)))
  ph <- utils::read.delim(file.path(w, "logs", "T0_phases.tsv"), colClasses = "character")
  for (p in c("account", "consolidate", "burn")) {
    expect_identical(sort(ph$host[ph$phase == p]), c("a", "b"), info = p)
  }
  expect_true(all(ph$status[ph$phase %in% c("account", "consolidate", "burn")] == "ok"))
})

test_that("legs that end during another host's copy are each consolidated once", {
  # wait -n -p returns an already-returned job again (bash 5.3), so a loop
  # over every pid would consolidate a host twice.
  skip_if_no_legs_lib()
  w <- legs_world()
  for (h in c("a", "b", "c")) legs_host(w, h, toupper(strrep(h, 4)))
  put(w, "cons_ip-a.sleep", "2")
  r <- run_legs(w, "legs_wait", legs = c(a = 0.3, b = 0.6, c = 0.9), disp = 0.1)
  expect_equal(r$status, 0L, info = r$out)
  cons <- events(w, "cons_calls")
  expect_identical(sort(cons$who[cons$what == "start"]), c("ip-a", "ip-b", "ip-c"))
  expect_identical(sort(burn_calls(w)), paste("--workspace", c("a", "b", "c")))
})

test_that("a cypher whose bucket overlaps the dispatcher's waits for the dispatcher leg", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  r <- run_legs(w, "legs_wait", legs = c(a = 0.3), disp = 2, disp_bucket = "AAAA,ZZZZ")
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "overlaps the dispatcher's (AAAA)", fixed = TRUE)
  ev <- events(w, "events")
  cons <- events(w, "cons_calls")
  expect_gt(when(cons, "start", "ip-a"), when(ev, "leg_end", "dispatcher"))
})

test_that("a refused source is kept and listed with its burn command; the other host is burned", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  legs_host(w, "b", "BBBB")
  put(w, "cons_ip-b.mode", "refuse:dest_log_newer")
  r <- run_legs(w, c("legs_wait", 'echo "FAILED=[$CONS_FAILED] EXCL=[$CONS_EXCLUDED]"'),
                legs = c(a = 0.3, b = 0.6), disp = 0.1)
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(burn_calls(w), "--workspace a")
  k <- kept_tsv(w)
  expect_identical(k$workspace, "b")
  expect_match(k$reason, "consolidate failed at stage dest_log_newer", fixed = TRUE)
  expect_identical(k$groups, "BBBB")
  expect_match(k$burn_command, "cypher_down.sh --workspace b", fixed = TRUE)
  expect_match(r$out, "FAILED=[b] EXCL=[BBBB]", fixed = TRUE)
  st <- utils::read.delim(file.path(w, "logs", "T0_consolidate_state.tsv"), colClasses = "character")
  expect_identical(st$state[st$workspace == "b"], "failed:dest_log_newer")
})

test_that("a consolidate with no outcome keeps its host and its groups in_flight, and the run goes on", {
  skip_if_no_legs_lib()
  for (mode in c("die", "ok_exit1")) {
    w <- legs_world()
    legs_host(w, "a", "AAAA")
    legs_host(w, "b", "BBBB")
    put(w, "cons_ip-a.mode", mode)
    r <- run_legs(w, c("legs_wait", 'echo "FAILED=[$CONS_FAILED] EXCL=[$CONS_EXCLUDED] HOLD=[${HOST_HOLD[a]}]"'),
                  legs = c(a = 0.3, b = 0.6), disp = 0.1)
    expect_equal(r$status, 0L, info = r$out)
    # b, after a, is still consolidated and burned.
    expect_identical(burn_calls(w), "--workspace b", info = mode)
    expect_match(r$out, "FAILED=[a] EXCL=[AAAA] HOLD=[1]", fixed = TRUE, info = mode)
    k <- kept_tsv(w)
    expect_identical(k$workspace, "a", info = mode)
    expect_match(k$reason, "no outcome", fixed = TRUE, info = mode)
    st <- utils::read.delim(file.path(w, "logs", "T0_consolidate_state.tsv"), colClasses = "character")
    expect_identical(paste(st$workspace, st$state), c("a in_flight", "b ok"), info = mode)
  }
})

test_that("a burn mid-run lists no host that is still modelling", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  legs_host(w, "b", "BBBB")
  put(w, "cons_ip-a.mode", "refuse:dest_log_newer")
  logs <- shQuote(file.path(w, "logs"))
  st <- shQuote(file.path(w, "stub"))
  # b's leg copies what the run had written by the time it ends.
  tail_b <- sprintf("cp %s/T0_kept_hosts.tsv %s/kept_mid.tsv; cp %s/T0_consolidate_state.tsv %s/state_mid.tsv",
                    logs, st, logs, st)
  r <- run_legs(w, "legs_wait", legs = c(a = 0.3, b = 3), disp = 0.1,
                leg_tail = list(b = tail_b))
  expect_equal(r$status, 0L, info = r$out)
  mid <- utils::read.delim(file.path(w, "stub", "kept_mid.tsv"), colClasses = "character")
  expect_identical(mid$workspace, "a")
  smid <- utils::read.delim(file.path(w, "stub", "state_mid.tsv"), colClasses = "character")
  expect_identical(unique(smid$workspace), "a")
  expect_false(grepl("cy[b] (cypher-b): run stopped before consolidate", r$out, fixed = TRUE))
})

test_that("a driver killed during one host's copy sees that host unsettled", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  legs_host(w, "b", "BBBB")
  put(w, "cons_ip-a.sleep", "6")
  r <- run_legs(w, c("trap 'burn_cyphers' EXIT", "( sleep 2; kill -TERM $$ ) &", "legs_wait"),
                legs = c(a = 0.2, b = 20), disp = 0.1)
  k <- kept_tsv(w)
  expect_identical(k$workspace, c("a", "b"))
  expect_identical(k$groups_measured, c("unsettled", "unsettled"))
  expect_match(r$out, "consolidate was still running against it", fixed = TRUE)
  expect_length(burn_calls(w), 0L)
})

test_that("a leg pid wait cannot report ends that leg, not the driver", {
  # wait -n -p unsets its variable on 127 (no listed pid is a child), which
  # under set -u killed the driver mid-legs (code-check round 1).
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "b", "BBBB")
  r <- run_legs(w, c("HOST_LEG_PID[a]=1", "legs_wait", 'echo "DONE RC_A=${HOST_RUN_RC[a]}"'),
                legs = c(a = 0.1, b = 0.5), disp = 0.2)
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "DONE RC_A=127", fixed = TRUE)
  expect_identical(burn_calls(w), "--workspace b")
})

test_that("a host deferred behind the dispatcher is not reported kept mid-run", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  legs_host(w, "b", "BBBB")
  put(w, "cons_ip-b.mode", "refuse:dest_log_newer")
  logs <- shQuote(file.path(w, "logs"))
  st <- shQuote(file.path(w, "stub"))
  tail_d <- sprintf("cp %s/T0_kept_hosts.tsv %s/kept_mid.tsv", logs, st)
  r <- run_legs(w, "legs_wait", legs = c(a = 0.2, b = 0.5), disp = 3,
                disp_bucket = "AAAA,ZZZZ", leg_tail = list(dispatcher = tail_d))
  expect_equal(r$status, 0L, info = r$out)
  # While the dispatcher modelled, only b (refused, finished) was kept; a
  # waited its turn and was then consolidated and burned.
  mid <- utils::read.delim(file.path(w, "stub", "kept_mid.tsv"), colClasses = "character")
  expect_identical(mid$workspace, "b")
  expect_identical(burn_calls(w), "--workspace a")
})

test_that("a host whose database did not answer is not consolidated and is kept", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "b", "BBBB")
  put(w, "ssh_ip-a.rc", "255")  # no output, no sentinels: unknown
  r <- run_legs(w, c("legs_wait", 'echo "CF=[$COMPLETE_FAIL]"'),
                legs = c(a = 0.3, b = 0.6), disp = 0.1)
  expect_equal(r$status, 0L, info = r$out)
  cons <- events(w, "cons_calls")
  expect_identical(cons$who[cons$what == "start"], "ip-b")
  expect_identical(kept_tsv(w)$workspace, "a")
  expect_match(r$out, "CF=[1]", fixed = TRUE)
})

test_that("the consolidate program is what consolidate_outcomes reads", {
  # The lib's R program, run as the lib expands it, with schema_consolidate
  # replaced by a result of the shape it returns.
  skip_if_no_legs_lib()
  rscript <- Sys.which("Rscript")
  testthat::skip_if(!nzchar(rscript), "Rscript not on PATH")
  w <- legs_world()
  tsv <- file.path(w, "logs", "T0_consolidate_a.tsv")
  r <- run_legs(w, sprintf(".legs_consolidate_r \"list(host = 'cypher@ip-a')\" %s > %s/prog.R",
                           shQuote(tsv), shQuote(w)), legs = c(a = 0), disp = 0)
  expect_equal(r$status, 0L, info = r$out)
  prog <- readLines(file.path(w, "prog.R"))
  expect_true(any(grepl("backup = FALSE, verify = FALSE", prog, fixed = TRUE)))
  prog <- prog[!grepl("load_all|^source\\(", prog)]
  fake <- paste0("res <- list(sources = list('cypher@ip-a' = list(ok = FALSE, ",
                 "stage = 'dest_log_newer', rc = -1L, groups = c('CCCC', 'DDDD'))))")
  i <- grepl("^res <- schema_consolidate", prog)
  expect_equal(sum(i), 1L)
  prog[i] <- fake
  writeLines(prog, file.path(w, "prog.R"))
  rc <- suppressWarnings(system2(rscript, file.path(w, "prog.R"), stdout = FALSE, stderr = FALSE))
  expect_equal(rc, 1L)
  r <- run_legs(w, c("HOST_BUCKET_DONE[a]=CCCC,DDDD",
                     sprintf("consolidate_outcomes %s a", shQuote(tsv)),
                     'echo "FAILED=$CONS_FAILED STAGE=${HOST_CONS_FAIL[a]}"'),
                legs = c(a = 0), disp = 0)
  expect_match(r$out, "FAILED=a STAGE=dest_log_newer", fixed = TRUE)
})

test_that("a state record with link#358's four-column header is still read", {
  skip_if_no_legs_lib()
  w <- legs_world()
  p <- file.path(w, "logs", "old_state.tsv")
  writeLines(c("wsg\tworkspace\tstate\trun_uid", "AAAA\ta\tok\tT0-0000",
               "BBBB\tb\tin_flight\tT0-0000"), p)
  r <- run_legs(w, sprintf('echo "U=[$(run_unconsolidated_from_state %s)]"', shQuote(p)),
                legs = c(a = 0), disp = 0)
  expect_match(r$out, "U=[BBBB]", fixed = TRUE)
})

test_that("a dispatcher-only run waits for its one leg and consolidates nothing", {
  skip_if_no_legs_lib()
  w <- legs_world()
  r <- run_legs(w, c("legs_wait", 'echo "DISP_RC=[$DISP_RC]"'),
                legs = stats::setNames(numeric(0), character(0)), disp = 0.3)
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "DISP_RC=[0]", fixed = TRUE)
  expect_false(file.exists(file.path(w, "stub", "cons_calls")))
})

test_that("the dispatcher's accounting does not claim the groups copied in from a cypher", {
  # Run A (2026-10-24): accounted after the copies, the dispatcher's log named
  # the cyphers' groups, read as its own finished groups outside its bucket.
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  put(w, "psql_local.out", db_answer(c("AAAA", "ZZZZ")))
  r <- run_legs(w, c("legs_wait",
                     'host_account dispatcher local /nonexistent "$DISP_BUCKET"',
                     'echo "FIN=[${ACC_FINISHED[dispatcher]}]"'),
                legs = c(a = 0.2), disp = 0.5)
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "FIN=[ZZZZ]", fixed = TRUE)
  expect_false(grepl("outside its bucket", r$out, fixed = TRUE))
})

# -- A persistent worker beside a cloud host (link#376) ----------------------

test_that("a worker's leg is consolidated and released, never burned", {
  skip_if_no_legs_lib()
  w <- legs_world()
  legs_host(w, "a", "AAAA")
  legs_host(w, "b", "BBBB")
  r <- run_legs(w, c("HOST_KIND[b]=worker; WORKERS_UP=1", "legs_wait"),
                legs = c(a = 0.3, b = 0.6), disp = 0.1)
  expect_equal(r$status, 0L, info = r$out)
  expect_identical(burn_calls(w), "--workspace a")
  expect_null(kept_tsv(w))
  expect_match(r$out, "b: no finished group left on the host after consolidate — may be released",
               fixed = TRUE)
  expect_match(r$out, "=== b: leg ended (exit 0); account, consolidate, release ===", fixed = TRUE)
  ph <- utils::read.delim(file.path(w, "logs", "T0_phases.tsv"), colClasses = "character")
  expect_identical(ph$status[ph$phase == "burn" & ph$host == "b"], "skipped")
  expect_identical(ph$status[ph$phase == "consolidate" & ph$host == "b"], "ok")
  expect_identical(ph$status[ph$phase == "burn" & ph$host == "a"], "ok")
})
