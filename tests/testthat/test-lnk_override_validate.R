# Helper: create crossings + overrides with known orphans and duplicates
setup_validate_tables <- function(conn) {
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_cross")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_over")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_val_cross (
      modelled_crossing_id integer PRIMARY KEY,
      barrier_result_code text
    )")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_val_cross VALUES
      (1001, 'BARRIER'), (1002, 'BARRIER'), (1003, 'PASSABLE'),
      (1004, 'BARRIER'), (1005, 'BARRIER')")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_val_over (
      modelled_crossing_id integer,
      barrier_result_code text
    )")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_val_over VALUES
      (1001, 'PASSABLE'),
      (1001, 'NONE'),
      (1002, 'PASSABLE'),
      (9999, 'BARRIER')")
}

teardown_validate_tables <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_cross")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_over")
}

over_tbl <- "working.test_val_over"
cross_tbl <- "working.test_val_cross"

# --- Tests ---

test_that("override_validate finds orphans", {
  conn <- skip_if_no_db()
  setup_validate_tables(conn)
  on.exit(teardown_validate_tables(conn))

  result <- lnk_override_validate(
    conn, overrides = over_tbl, crossings = cross_tbl, verbose = FALSE
  )
  expect_equal(result$orphans, 9999L)
})

test_that("override_validate finds duplicates", {
  conn <- skip_if_no_db()
  setup_validate_tables(conn)
  on.exit(teardown_validate_tables(conn))

  result <- lnk_override_validate(
    conn, overrides = over_tbl, crossings = cross_tbl, verbose = FALSE
  )
  expect_equal(result$duplicates, 1001L)
})

test_that("override_validate counts correctly", {
  conn <- skip_if_no_db()
  setup_validate_tables(conn)
  on.exit(teardown_validate_tables(conn))

  result <- lnk_override_validate(
    conn, overrides = over_tbl, crossings = cross_tbl, verbose = FALSE
  )
  expect_equal(result$total_count, 4L)
  expect_equal(result$valid_count, 3L)
})

test_that("override_validate clean data has no orphans or duplicates", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_clean_c")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_clean_o")
  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_clean_c")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_val_clean_o")
  })

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_val_clean_c (
      modelled_crossing_id integer PRIMARY KEY, x text)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_val_clean_c VALUES (1, 'a'), (2, 'b')")
  DBI::dbExecute(conn, "
    CREATE TABLE working.test_val_clean_o (
      modelled_crossing_id integer, x text)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_val_clean_o VALUES (1, 'c'), (2, 'd')")

  result <- lnk_override_validate(
    conn,
    overrides = "working.test_val_clean_o",
    crossings = "working.test_val_clean_c",
    verbose = FALSE
  )

  expect_length(result$orphans, 0)
  expect_length(result$duplicates, 0)
  expect_equal(result$valid_count, 2L)
  expect_equal(result$total_count, 2L)
})

test_that("override_validate errors on missing tables", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_override_validate(conn, "working.nonexistent", cross_tbl),
    "not found"
  )
})

test_that("override_validate verbose output includes counts", {
  conn <- skip_if_no_db()
  setup_validate_tables(conn)
  on.exit(teardown_validate_tables(conn))

  expect_message(
    lnk_override_validate(
      conn, overrides = over_tbl, crossings = cross_tbl, verbose = TRUE
    ),
    "Total overrides:.*4"
  )
})

test_that("override_validate verbose flags orphans", {
  conn <- skip_if_no_db()
  setup_validate_tables(conn)
  on.exit(teardown_validate_tables(conn))

  expect_message(
    lnk_override_validate(
      conn, overrides = over_tbl, crossings = cross_tbl, verbose = TRUE
    ),
    "Orphans:.*1.*not found"
  )
})

test_that("override_validate verbose flags duplicates", {
  conn <- skip_if_no_db()
  setup_validate_tables(conn)
  on.exit(teardown_validate_tables(conn))

  expect_message(
    lnk_override_validate(
      conn, overrides = over_tbl, crossings = cross_tbl, verbose = TRUE
    ),
    "Duplicates:.*1.*multiple"
  )
})
