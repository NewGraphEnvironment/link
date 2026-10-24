# .lnk_timeout_statement(): which statement a statement_timeout cancelled
# (link#371). fresh executes SQL with a bare DBI::dbExecute(), so the cancel's
# error carries no SQL; the frames still on the stack in a calling handler do.

timeout_msg <- "Failed to fetch row : ERROR:  canceling statement due to statement timeout"

# Raise `msg` from inside a frame holding the SQL as `nm`, and return what the
# helper finds from a calling handler, as wsg_run_one.R calls it.
probe <- function(sql, nm = "statement", msg = timeout_msg) {
  inner <- function() {
    assign(nm, sql)
    stop(msg, call. = FALSE)
  }
  found <- "<handler not reached>"
  try(withCallingHandlers(inner(), error = function(e) {
    found <<- .lnk_timeout_statement(e, sys.frames())
  }), silent = TRUE)
  found
}

test_that("a timeout names the statement held as `statement` or `sql`, squished", {
  sql <- "\n  CREATE TEMP TABLE pg_temp.frs_near_river_walk AS\n    SELECT 1\n"
  expected <- "CREATE TEMP TABLE pg_temp.frs_near_river_walk AS SELECT 1"
  expect_identical(probe(sql), expected)
  expect_identical(probe(sql, nm = "sql"), expected)
})

test_that("a long statement is cut to the width, and says so", {
  s <- probe(paste("SELECT", strrep("x", 500)))
  expect_identical(nchar(s), 160L)
  expect_match(s, "\\.\\.\\.$")
})

test_that("any other error is not a timeout", {
  expect_null(probe("SELECT 1", msg = "relation \"x\" does not exist"))
  expect_null(probe("SELECT 1", msg = "canceling statement due to lock timeout"))
})

test_that("a timeout with no SQL on the stack still says it was a timeout", {
  e <- simpleError(timeout_msg)
  expect_identical(.lnk_timeout_statement(e, list(new.env())), "<statement not found>")
})

test_that("a real statement_timeout through RPostgres names the statement", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "SET statement_timeout = '200ms'")
  withr::defer(try(DBI::dbExecute(conn, "RESET statement_timeout"), silent = TRUE))
  found <- "<handler not reached>"
  res <- try(withCallingHandlers(
    DBI::dbExecute(conn, "SELECT pg_sleep(5) -- link#371 probe"),
    error = function(e) found <<- .lnk_timeout_statement(e, sys.frames())
  ), silent = TRUE)
  expect_s3_class(res, "try-error")
  expect_identical(found, "SELECT pg_sleep(5) -- link#371 probe")
  # The connection survives a cancel: the next statement runs.
  expect_identical(DBI::dbGetQuery(conn, "SELECT 1 AS x")$x, 1L)
})
