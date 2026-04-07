setup_score_table <- function(conn) {
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_score")
  DBI::dbExecute(conn, "
    CREATE TABLE working.test_score (
      modelled_crossing_id integer PRIMARY KEY,
      barrier_result_code text,
      outlet_drop numeric,
      culvert_slope numeric,
      culvert_length_m numeric
    )")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_score VALUES
      (1, 'BARRIER', 0.8,  0.02, 15),
      (2, 'BARRIER', 0.1,  0.08, 30),
      (3, 'PASSABLE', 0.0, 0.01, 12),
      (4, 'BARRIER', 0.35, 0.04, 20),
      (5, 'BARRIER', 1.2,  0.03, 25),
      (6, 'POTENTIAL', 0.25, 0.02, 18),
      (7, 'BARRIER', 0.6,  0.06, 35),
      (8, 'PASSABLE', 0.05, 0.01, 10)")
}

tbl_score <- "working.test_score"

teardown_score <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_score")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_score_copy")
}

get_severity <- function(conn, id) {
  sql <- paste0("SELECT severity FROM ", tbl_score,
                " WHERE modelled_crossing_id = ", id)
  DBI::dbGetQuery(conn, sql)$severity
}

# --- Input validation ---

test_that("score_severity errors on missing table", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_score_severity(conn, "working.nonexistent"),
    "not found"
  )
})

# --- Default threshold scoring ---

test_that("score_severity classifies with default thresholds", {
  conn <- skip_if_no_db()
  setup_score_table(conn)
  on.exit(teardown_score(conn))

  lnk_score_severity(conn, tbl_score, verbose = FALSE)

  # High: outlet_drop >= 0.6 OR slope*length >= 120
  # ID 1: drop=0.8 -> high
  expect_equal(get_severity(conn, 1), "high")
  # ID 5: drop=1.2 -> high
  expect_equal(get_severity(conn, 5), "high")
  # ID 7: drop=0.6, slope*length=0.06*35=2.1 -> high (drop triggers)
  expect_equal(get_severity(conn, 7), "high")
  # ID 2: drop=0.1, slope*length=0.08*30=2.4 -> low (neither triggers)
  # Wait — 2.4 < 60, drop 0.1 < 0.3 -> low
  expect_equal(get_severity(conn, 2), "low")

  # Moderate: outlet_drop >= 0.3 OR slope*length >= 60
  # ID 4: drop=0.35 -> moderate
  expect_equal(get_severity(conn, 4), "moderate")

  # Low: everything else
  # ID 3: drop=0.0 -> low
  expect_equal(get_severity(conn, 3), "low")
  # ID 6: drop=0.25 -> low
  expect_equal(get_severity(conn, 6), "low")
  # ID 8: drop=0.05 -> low
  expect_equal(get_severity(conn, 8), "low")
})

# --- Custom thresholds ---

test_that("score_severity respects custom thresholds", {
  conn <- skip_if_no_db()
  setup_score_table(conn)
  on.exit(teardown_score(conn))

  # Raise high threshold — fewer high severity
  th <- lnk_thresholds(high = list(outlet_drop = 1.0))
  lnk_score_severity(conn, tbl_score, thresholds = th, verbose = FALSE)

  # ID 1: drop=0.8 -> no longer high (threshold is 1.0)
  # But slope_length default is 120, slope*length=0.02*15=0.3 -> not high
  # So ID 1 is moderate (drop 0.8 >= 0.3)
  expect_equal(get_severity(conn, 1), "moderate")
  # ID 5: drop=1.2 -> still high
  expect_equal(get_severity(conn, 5), "high")
})

# --- Output to new table ---

test_that("score_severity writes to new table when to is specified", {
  conn <- skip_if_no_db()
  setup_score_table(conn)
  on.exit(teardown_score(conn))

  result <- lnk_score_severity(
    conn, tbl_score, to = "working.test_score_copy", verbose = FALSE
  )
  expect_equal(result, "working.test_score_copy")

  # Original unchanged (no severity column)
  orig_cols <- .lnk_table_columns(conn, tbl_score)
  expect_false("severity" %in% orig_cols)

  # Copy has severity
  copy_cols <- .lnk_table_columns(conn, "working.test_score_copy")
  expect_true("severity" %in% copy_cols)
})

# --- Verbose output ---

test_that("score_severity verbose shows distribution", {
  conn <- skip_if_no_db()
  setup_score_table(conn)
  on.exit(teardown_score(conn))

  expect_message(
    lnk_score_severity(conn, tbl_score, verbose = TRUE),
    "high"
  )
})

# --- NULL handling ---

test_that("score_severity handles NULL measurements gracefully", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_score_null")
  on.exit(DBI::dbExecute(
    conn, "DROP TABLE IF EXISTS working.test_score_null"
  ))

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_score_null (
      modelled_crossing_id integer,
      outlet_drop numeric,
      culvert_slope numeric,
      culvert_length_m numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_score_null VALUES
      (1, NULL, NULL, NULL),
      (2, 0.8, NULL, NULL)")

  lnk_score_severity(
    conn, "working.test_score_null", verbose = FALSE
  )

  sql <- "SELECT * FROM working.test_score_null ORDER BY modelled_crossing_id"
  r <- DBI::dbGetQuery(conn, sql)
  # ID 1: all NULL -> low (nothing triggers high or moderate)
  expect_equal(r$severity[1], "low")
  # ID 2: drop=0.8 -> high
  expect_equal(r$severity[2], "high")
})

# --- Column remapping ---

test_that("score_severity works with remapped column names", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_score_remap")
  on.exit(DBI::dbExecute(
    conn, "DROP TABLE IF EXISTS working.test_score_remap"
  ))

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_score_remap (
      id integer,
      perch_height numeric,
      pipe_gradient numeric,
      pipe_length_m numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_score_remap VALUES (1, 0.8, 0.01, 10)")

  lnk_score_severity(
    conn, "working.test_score_remap",
    col_drop = "perch_height",
    col_slope = "pipe_gradient",
    col_length = "pipe_length_m",
    verbose = FALSE
  )

  r <- DBI::dbGetQuery(conn, "SELECT severity FROM working.test_score_remap")
  expect_equal(r$severity, "high")
})
