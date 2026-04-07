test_that("break_source returns correct spec with label_col", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs")
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs"))

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_bs (
      id integer, severity text)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_bs VALUES (1, 'high'), (2, 'low')")

  spec <- lnk_break_source(conn, "working.test_bs")

  expect_equal(spec$table, "working.test_bs")
  expect_equal(spec$label_col, "severity")
  expect_equal(spec$label_map, c(high = "blocked", moderate = "potential"))
  expect_null(spec$label)
  expect_null(spec$where)
})

test_that("break_source returns correct spec with static label", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs2")
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs2"))

  DBI::dbExecute(conn, "CREATE TABLE working.test_bs2 (id integer)")
  DBI::dbExecute(conn, "INSERT INTO working.test_bs2 VALUES (1)")

  spec <- lnk_break_source(
    conn, "working.test_bs2", label = "potential", label_col = NULL
  )
  expect_equal(spec$label, "potential")
  expect_null(spec$label_col)
})

test_that("break_source errors on both label and label_col", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs3")
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs3"))
  DBI::dbExecute(conn, "CREATE TABLE working.test_bs3 (id int, severity text)")

  expect_error(
    lnk_break_source(
      conn, "working.test_bs3", label = "x", label_col = "severity"
    ),
    "not both"
  )
})

test_that("break_source errors on missing label_col", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs4")
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs4"))
  DBI::dbExecute(conn, "CREATE TABLE working.test_bs4 (id integer)")

  expect_error(
    lnk_break_source(conn, "working.test_bs4"),
    "not found.*lnk_score_severity"
  )
})

test_that("break_source includes where in spec", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs5")
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs5"))
  DBI::dbExecute(conn, "CREATE TABLE working.test_bs5 (id int, severity text)")

  spec <- lnk_break_source(
    conn, "working.test_bs5", where = "id > 5"
  )
  expect_equal(spec$where, "id > 5")
})

test_that("break_source custom label_map", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs6")
  on.exit(DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_bs6"))
  DBI::dbExecute(conn, "CREATE TABLE working.test_bs6 (id int, severity text)")

  spec <- lnk_break_source(
    conn, "working.test_bs6", label_map = c(high = "blocked")
  )
  expect_equal(spec$label_map, c(high = "blocked"))
})

test_that("break_source errors on missing table", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_break_source(conn, "working.nonexistent"),
    "not found"
  )
})
