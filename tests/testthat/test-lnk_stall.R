# The stall sampler (link#487): while a group's statement runs past a
# threshold, a second connection records what its backend, its parallel
# workers and its blockers are doing, as tagged lines in the group's log.

test_that("a row is one line: tagged, tab-separated, no tab or newline inside a field", {
  df <- data.frame(
    sampled_utc = "2026-11-14T00:00:00Z", role = "leader", pid = 101L,
    leader_pid = NA_integer_, blocks_pid = NA_integer_, state = "active",
    wait_event_type = "Lock", wait_event = "relation",
    query_start = "2026-11-13T23:40:00Z",
    query = paste0("CREATE TEMP TABLE t AS\n\tSELECT ", strrep("x", 300)),
    n_active = 7L, stringsAsFactors = FALSE
  )
  out <- .lnk_stall_lines(df, "SANJ", load = c(2.5, 1.25, 1), header = TRUE)
  expect_length(out, 2L)
  expect_true(all(startsWith(out, "[wsg_stall] SANJ\t")))
  hdr <- strsplit(sub("^\\[wsg_stall\\] SANJ\t", "", out[1]), "\t", fixed = TRUE)[[1]]
  expect_identical(hdr, .lnk_stall_cols)
  row <- strsplit(sub("^\\[wsg_stall\\] SANJ\t", "", out[2]), "\t", fixed = TRUE)[[1]]
  expect_length(row, length(.lnk_stall_cols))
  names(row) <- .lnk_stall_cols
  expect_identical(row[["wsg"]], "SANJ")
  # NA reads as an empty field, never "NA".
  expect_identical(row[["leader_pid"]], "")
  expect_identical(row[["load1"]], "2.5")
  expect_false(grepl("[\t\n\r]", row[["query"]]))
  expect_lte(nchar(row[["query"]]), 200L)
  expect_true(startsWith(row[["query"]], "CREATE TEMP TABLE t AS SELECT x"))
  # A blocker's query cannot read as a log marker the driver greps for.
  df$query <- "SELECT '[wsg_run_one] ABCD done in 1 min', '__LNK_LEG_END__'"
  q <- .lnk_stall_lines(df, "SANJ", load = c(1, 1, 1))
  expect_false(grepl("[wsg_run_one]", q, fixed = TRUE))
  expect_false(grepl("__LNK_LEG_END__", q, fixed = TRUE))
  # No header asked for, none written.
  expect_length(.lnk_stall_lines(df, "SANJ", load = c(1, 1, 1)), 1L)
})

test_that("the load average parses from Linux and macOS, and is NA when unreadable", {
  expect_identical(.lnk_loadavg_parse("0.52 0.58 0.59 1/389 12345"), c(0.52, 0.58, 0.59))
  expect_identical(.lnk_loadavg_parse("{ 2.10 1.98 1.85 }"), c(2.1, 1.98, 1.85))
  expect_identical(.lnk_loadavg_parse(character(0)), rep(NA_real_, 3))
  expect_identical(.lnk_loadavg_parse("garbage"), rep(NA_real_, 3))
  expect_length(.lnk_loadavg(), 3L)
})

# A session in another process, so this one can watch it: RPostgres blocks in
# dbSendQuery until the statement returns. Found by its application_name.
stall_session <- function(sql, conn, env = parent.frame()) {
  tag <- sprintf("lnk_test_stall_%d_%d", Sys.getpid(), sample.int(1e6, 1L))
  code <- sprintf(
    paste(
      "c <- DBI::dbConnect(RPostgres::Postgres(), dbname = 'fwapg', host = 'localhost',",
      "port = 5432L, user = 'postgres', password = 'postgres', application_name = '%s');",
      "DBI::dbExecute(c, \"SET statement_timeout = '60s'\");",
      "try(DBI::dbExecute(c, %s), silent = TRUE)"
    ),
    tag, deparse(sql)
  )
  end_sql <- sprintf(
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = '%s'", tag
  )
  withr::defer(try(DBI::dbGetQuery(conn, end_sql), silent = TRUE), envir = env)
  system2(file.path(R.home("bin"), "Rscript"), c("-e", shQuote(code)),
          wait = FALSE, stdout = FALSE, stderr = FALSE)
  for (i in seq_len(100)) {
    p <- DBI::dbGetQuery(conn, sprintf(
      "SELECT pid FROM pg_stat_activity WHERE application_name = '%s' AND state = 'active'", tag
    ))$pid
    if (length(p) == 1L) return(p)
    Sys.sleep(0.2)
  }
  testthat::fail("the stalled session never started")
}

skip_if_not_local_db <- function(conn) {
  info <- DBI::dbGetInfo(conn)
  testthat::skip_if(!identical(as.character(info$port), "5432") ||
                      !info$host %in% c("localhost", "127.0.0.1"),
                    "the stalled session connects to the local docker fwapg")
}

test_that("a pg_sleep stall gives a leader row waiting on PgSleep, only past the threshold", {
  conn <- skip_if_no_db()
  skip_if_not_local_db(conn)
  pid <- stall_session("SELECT pg_sleep(30) -- link#487 test", conn)
  Sys.sleep(2.5)
  s <- .lnk_stall_snapshot(conn, pid, after_s = 2)
  lead <- s[s$role == "leader", ]
  expect_identical(nrow(lead), 1L)
  expect_identical(lead$pid, pid)
  expect_identical(lead$wait_event, "PgSleep")
  expect_match(lead$query, "pg_sleep(30)", fixed = TRUE)
  expect_true(is.integer(s$n_active))
  expect_gte(s$n_active[1], 1L)
  # Under the threshold: nothing.
  expect_identical(nrow(.lnk_stall_snapshot(conn, pid, after_s = 600)), 0L)
})

test_that("a lock stall names the blocking session's pid and query", {
  conn <- skip_if_no_db()
  skip_if_not_local_db(conn)
  sc <- sprintf("lnk_test_stall_%d", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", sc))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.t AS SELECT 1 AS x", sc))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc)))
  locker <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                           port = 5432L, user = "postgres", password = "postgres")
  withr::defer(try(DBI::dbDisconnect(locker), silent = TRUE))
  locker_pid <- DBI::dbGetQuery(locker, "SELECT pg_backend_pid() AS p")$p
  DBI::dbBegin(locker)
  DBI::dbExecute(locker, sprintf("LOCK TABLE %s.t IN ACCESS EXCLUSIVE MODE", sc))
  withr::defer(try(DBI::dbRollback(locker), silent = TRUE), priority = "first")
  pid <- stall_session(sprintf("SELECT count(*) FROM %s.t", sc), conn)
  Sys.sleep(1.5)
  s <- .lnk_stall_snapshot(conn, pid, after_s = 1)
  lead <- s[s$role == "leader", ]
  expect_identical(lead$wait_event_type, "Lock")
  blk <- s[s$role == "blocker", ]
  expect_identical(blk$pid, locker_pid)
  expect_identical(blk$blocks_pid, pid)
  expect_match(blk$query, "LOCK TABLE", fixed = TRUE)
})

test_that("the watch ends when its group's process or backend is gone, and never raises", {
  conn <- skip_if_no_db()
  skip_if_not_local_db(conn)
  dead <- as.integer(system2("sh", c("-c", shQuote("echo $$")), stdout = TRUE))
  r <- .lnk_stall_watch(conn, pid = 1L, parent_pid = dead, wsg = "TEST", poll_s = 0.1)
  expect_identical(r, "parent_gone")
  gone <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                         port = 5432L, user = "postgres", password = "postgres")
  gone_pid <- DBI::dbGetQuery(gone, "SELECT pg_backend_pid() AS p")$p
  DBI::dbDisconnect(gone)
  Sys.sleep(0.5)
  mk <- tempfile()
  r <- .lnk_stall_watch(conn, pid = gone_pid, parent_pid = Sys.getpid(), wsg = "TEST",
                        every_s = 0.1, poll_s = 0.1, marker = mk)
  expect_identical(r, "backend_gone")
  # No row written, no marker.
  expect_false(file.exists(mk))
  closed <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                           port = 5432L, user = "postgres", password = "postgres")
  DBI::dbDisconnect(closed)
  watch_closed <- function() {
    .lnk_stall_watch(closed, pid = 1L, parent_pid = Sys.getpid(), wsg = "TEST",
                     every_s = 0.1, poll_s = 0.1)
  }
  expect_no_error(out <- capture.output(r <- watch_closed()))
  expect_identical(r, "error")
  expect_length(out, 1L)
  expect_match(out, "^\\[wsg_stall_error\\] TEST ")
})

test_that("the watch checks at least twice inside the threshold and the window to the bound", {
  conn <- skip_if_no_db()
  skip_if_not_local_db(conn)
  # A backend that is gone ends the watch at its first check; time that check.
  gone <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                         port = 5432L, user = "postgres", password = "postgres")
  gone_pid <- DBI::dbGetQuery(gone, "SELECT pg_backend_pid() AS p")$p
  DBI::dbDisconnect(gone)
  first_check <- function(...) {
    t0 <- Sys.time()
    .lnk_stall_watch(conn, pid = gone_pid, parent_pid = Sys.getpid(), wsg = "TEST",
                     poll_s = 0.1, ...)
    as.numeric(difftime(Sys.time(), t0, units = "secs"))
  }
  # Threshold 4 s: a check every 2 s, not every 60.
  expect_lt(first_check(after_s = 4, every_s = 60), 3.5)
  # Threshold 600 s, bound 606 s: the 6 s window gets a check every 3 s.
  expect_lt(first_check(after_s = 600, every_s = 60, bound_s = 606), 4.5)
})

test_that("the watch writes the header once, then a row per backend per check", {
  conn <- skip_if_no_db()
  skip_if_not_local_db(conn)
  pid <- stall_session("SELECT pg_sleep(30) -- link#487 watch", conn)
  # The parent is a process that ends after a few checks.
  parent <- system2("sh", c("-c", shQuote("sleep 4 >/dev/null 2>&1 & echo $!")), stdout = TRUE)
  mk <- tempfile()
  out <- capture.output(
    r <- .lnk_stall_watch(conn, pid = pid, parent_pid = as.integer(parent), wsg = "TEST",
                          after_s = 0, every_s = 1, poll_s = 0.2, marker = mk)
  )
  expect_true(file.exists(mk))
  expect_identical(r, "parent_gone")
  expect_identical(sum(grepl("^\\[wsg_stall\\] TEST\tsampled_utc\t", out)), 1L)
  expect_gte(sum(grepl("^\\[wsg_stall\\] TEST\t[0-9]{4}-", out)), 2L)
  expect_true(all(grepl("PgSleep", out[-1], fixed = TRUE)))
})
