# The line rule on a fixture network (#374, #465). AAAA holds the main stem
# (code 100, line 1); BBBB touches the main stem upstream of AAAA and holds the
# tributary 100.200 (line 2); CCCC holds 100.200.300 (line 3); DDDD a separate
# drainage (400). EEEE holds only an unassigned 999 code on line 1, which the
# rule leaves out.
local_deps_fixture <- function(conn, rows, env = parent.frame()) {
  tbl <- "pg_temp.lnk_test_deps_net"
  DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS %s", tbl)),
               envir = env)
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s (watershed_group_code varchar(4), blue_line_key integer,
                      wscode_ltree ltree)", tbl))
  DBI::dbExecute(conn, sprintf("INSERT INTO %s VALUES %s", tbl, rows))
  tbl
}

test_that("the line rule lists every group on a line of the reader's codes", {
  conn <- skip_if_no_db()
  tbl <- local_deps_fixture(conn, paste(
    "('AAAA', 1, '100'), ('BBBB', 1, '100'), ('BBBB', 2, '100.200'),",
    "('CCCC', 3, '100.200.300'), ('DDDD', 4, '400'),",
    "('EEEE', 1, '999.100'), (NULL, 1, '100'), ('DDDD', 5, NULL)"))
  got <- link:::.lnk_wsg_deps_line(conn, fwa = tbl)
  expect_identical(got, data.frame(
    wsg = c("AAAA", "BBBB", "CCCC", "CCCC"),
    dep = c("BBBB", "AAAA", "AAAA", "BBBB"),
    stringsAsFactors = FALSE))
  # the temp tables it builds are gone
  left <- DBI::dbGetQuery(conn,
    "SELECT relname FROM pg_class WHERE relname LIKE 'lnk_deps_%'
       AND relpersistence = 't'")
  expect_equal(nrow(left), 0L)
})

test_that("the line rule refuses an FWA table that gives no pairs", {
  conn <- skip_if_no_db()
  tbl <- local_deps_fixture(conn,
    "('AAAA', 1, '999.1'), ('BBBB', 1, '999.1'), ('CCCC', 2, '400')")
  expect_error(link:::.lnk_wsg_deps_line(conn, fwa = tbl),
               "no line-rule dependency pairs")
})

test_that("the line rule refuses a table name it would interpolate unsafely", {
  expect_error(link:::.lnk_wsg_deps_line(fake_conn(), fwa = "x; DROP"),
               "disallowed characters")
})
