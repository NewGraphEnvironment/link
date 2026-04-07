# Table names used across tests
cross_tbl <- "working.test_crossings"
over_tbl <- "working.test_overrides"

setup_apply_tables <- function(conn) {
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", cross_tbl))
  DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", over_tbl))

  DBI::dbExecute(conn, paste0("
    CREATE TABLE ", cross_tbl, " (
      modelled_crossing_id integer PRIMARY KEY,
      barrier_result_code text,
      outlet_drop numeric
    )"))
  DBI::dbExecute(conn, paste0("
    INSERT INTO ", cross_tbl, " VALUES
      (1001, 'BARRIER', 0.8),
      (1002, 'BARRIER', 0.1),
      (1003, 'PASSABLE', 0.0),
      (1004, 'BARRIER', 0.35),
      (1005, 'BARRIER', 1.2)"))

  DBI::dbExecute(conn, paste0("
    CREATE TABLE ", over_tbl, " (
      modelled_crossing_id integer,
      barrier_result_code text,
      reviewer text,
      review_date text,
      source text
    )"))
  DBI::dbExecute(conn, paste0("
    INSERT INTO ", over_tbl, " VALUES
      (1001, 'PASSABLE', 'J. Smith', '2025-08-15', 'imagery review'),
      (1003, 'NONE', 'A. Irvine', '2025-09-20', 'field visit')"))
}

teardown_apply_tables <- function(conn) {
  DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", cross_tbl))
  DBI::dbExecute(conn, paste("DROP TABLE IF EXISTS", over_tbl))
}

get_crossing <- function(conn, id) {
  sql <- paste0(
    "SELECT barrier_result_code FROM ", cross_tbl,
    " WHERE modelled_crossing_id = ", id
  )
  DBI::dbGetQuery(conn, sql)$barrier_result_code
}

# --- Tests ---

test_that("override_apply errors on missing crossings table", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_override_apply(conn, "working.nonexistent", over_tbl),
    "not found"
  )
})

test_that("override_apply errors on missing overrides table", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_apply_stub")
  DBI::dbExecute(conn, "CREATE TABLE working.test_apply_stub (x int)")
  on.exit(DBI::dbExecute(conn, "DROP TABLE working.test_apply_stub"))

  expect_error(
    lnk_override_apply(conn, "working.test_apply_stub", "working.no"),
    "not found"
  )
})

test_that("override_apply auto-detects columns and updates", {
  conn <- skip_if_no_db()
  setup_apply_tables(conn)
  on.exit(teardown_apply_tables(conn))

  result <- lnk_override_apply(
    conn, crossings = cross_tbl, overrides = over_tbl, verbose = FALSE
  )

  expect_equal(result$n_updated, 2L)
  expect_equal(result$cols_updated, "barrier_result_code")
  expect_equal(get_crossing(conn, 1001), "PASSABLE")
  expect_equal(get_crossing(conn, 1003), "NONE")
  expect_equal(get_crossing(conn, 1002), "BARRIER")
})

test_that("override_apply excludes provenance columns from auto-detect", {
  conn <- skip_if_no_db()
  setup_apply_tables(conn)
  on.exit(teardown_apply_tables(conn))

  result <- lnk_override_apply(
    conn, crossings = cross_tbl, overrides = over_tbl, verbose = FALSE
  )
  expect_false("reviewer" %in% result$cols_updated)
  expect_false("review_date" %in% result$cols_updated)
  expect_false("source" %in% result$cols_updated)
})

test_that("override_apply with explicit cols_update", {
  conn <- skip_if_no_db()
  setup_apply_tables(conn)
  on.exit(teardown_apply_tables(conn))

  result <- lnk_override_apply(
    conn, crossings = cross_tbl, overrides = over_tbl,
    cols_update = c("barrier_result_code"), verbose = FALSE
  )
  expect_equal(result$cols_updated, "barrier_result_code")
})

test_that("override_apply errors on col_id missing from table", {
  conn <- skip_if_no_db()
  setup_apply_tables(conn)
  on.exit(teardown_apply_tables(conn))

  expect_error(
    lnk_override_apply(
      conn, crossings = cross_tbl, overrides = over_tbl,
      col_id = "nonexistent_id"
    ),
    "not found"
  )
})

test_that("override_apply is idempotent", {
  conn <- skip_if_no_db()
  setup_apply_tables(conn)
  on.exit(teardown_apply_tables(conn))

  lnk_override_apply(
    conn, cross_tbl, over_tbl, verbose = FALSE
  )
  result2 <- lnk_override_apply(
    conn, cross_tbl, over_tbl, verbose = FALSE
  )
  expect_equal(result2$n_updated, 2L)
  expect_equal(get_crossing(conn, 1001), "PASSABLE")
})

test_that("override_apply reports zero when no overlapping columns", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_cross_noop")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_over_noop")
  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_cross_noop")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_over_noop")
  })

  DBI::dbExecute(conn, "CREATE TABLE working.test_cross_noop (
    modelled_crossing_id int, col_a text)")
  DBI::dbExecute(conn, "CREATE TABLE working.test_over_noop (
    modelled_crossing_id int, col_b text)")

  result <- lnk_override_apply(
    conn, crossings = "working.test_cross_noop",
    overrides = "working.test_over_noop", verbose = FALSE
  )
  expect_equal(result$n_updated, 0L)
  expect_length(result$cols_updated, 0)
})

test_that("override_apply verbose output includes counts", {
  conn <- skip_if_no_db()
  setup_apply_tables(conn)
  on.exit(teardown_apply_tables(conn))

  expect_message(
    lnk_override_apply(conn, cross_tbl, over_tbl, verbose = TRUE),
    "Updated 2 of 5 crossings"
  )
})
