setup_habitat_tables <- function(conn) {
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_hab_cross")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_hab_hab")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_hab_cross (
      modelled_crossing_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric
    )")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_hab_cross VALUES
      (1, 100, 1000),
      (2, 100, 5000),
      (3, 200, 500)")

  # Habitat segments: blk 100 has spawning and rearing segments
  DBI::dbExecute(conn, "
    CREATE TABLE working.test_hab_hab (
      blue_line_key bigint,
      downstream_route_measure numeric,
      length_metre numeric,
      spawning boolean,
      rearing boolean
    )")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_hab_hab VALUES
      (100, 1200, 500, true, false),
      (100, 2000, 1000, true, true),
      (100, 4000, 800, false, true),
      (100, 5500, 300, true, false),
      (100, 6000, 200, false, true),
      (200, 100, 2000, true, true),
      (200, 600, 1500, true, false)")
}

teardown_habitat_tables <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_hab_cross")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_hab_hab")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_hab_copy")
}

cross_tbl <- "working.test_hab_cross"
hab_tbl <- "working.test_hab_hab"

# --- Input validation ---

test_that("habitat_upstream errors on missing tables", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_aggregate(conn, "working.nonexistent", hab_tbl),
    "not found"
  )
})

test_that("habitat_upstream errors on bad cols_sum", {
  conn <- skip_if_no_db()
  setup_habitat_tables(conn)
  on.exit(teardown_habitat_tables(conn))

  expect_error(
    lnk_aggregate(conn, cross_tbl, hab_tbl, cols_sum = c("x")),
    "named character"
  )
})

# --- Habitat rollup ---

test_that("habitat_upstream computes upstream sums", {
  conn <- skip_if_no_db()
  setup_habitat_tables(conn)
  on.exit(teardown_habitat_tables(conn))

  lnk_aggregate(conn, cross_tbl, hab_tbl, verbose = FALSE)

  r <- DBI::dbGetQuery(conn, paste(
    "SELECT * FROM", cross_tbl, "ORDER BY modelled_crossing_id"
  ))

  # Crossing 1 (blk 100, meas 1000): upstream segments at 1200, 2000, 4000, 5500, 6000
  # spawning: 500 + 1000 + 300 = 1800m = 1.8km
  # rearing: 1000 + 800 + 200 = 2000m = 2.0km
  expect_equal(r$spawning_km[1], 1.8)
  expect_equal(r$rearing_km[1], 2.0)

  # Crossing 2 (blk 100, meas 5000): upstream at 5500, 6000
  # spawning: 300m = 0.3km
  # rearing: 200m = 0.2km
  expect_equal(r$spawning_km[2], 0.3)
  expect_equal(r$rearing_km[2], 0.2)

  # Crossing 3 (blk 200, meas 500): upstream at 600
  # spawning: 1500m = 1.5km
  # rearing: 0km (only spawning at 600)
  expect_equal(r$spawning_km[3], 1.5)
  expect_equal(r$rearing_km[3], 0)
})

test_that("habitat_upstream writes to new table", {
  conn <- skip_if_no_db()
  setup_habitat_tables(conn)
  on.exit(teardown_habitat_tables(conn))

  result <- lnk_aggregate(
    conn, cross_tbl, hab_tbl,
    to = "working.test_hab_copy", verbose = FALSE
  )
  expect_equal(result, "working.test_hab_copy")

  orig_cols <- .lnk_table_columns(conn, cross_tbl)
  expect_false("spawning_km" %in% orig_cols)

  copy_cols <- .lnk_table_columns(conn, "working.test_hab_copy")
  expect_true("spawning_km" %in% copy_cols)
})

test_that("habitat_upstream verbose reports stats", {
  conn <- skip_if_no_db()
  setup_habitat_tables(conn)
  on.exit(teardown_habitat_tables(conn))

  expect_message(
    lnk_aggregate(conn, cross_tbl, hab_tbl, verbose = TRUE),
    "spawning_km"
  )
})
