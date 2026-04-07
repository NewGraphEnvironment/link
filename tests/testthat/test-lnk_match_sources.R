# Helpers
setup_match_tables <- function(conn) {
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_src_a")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_src_b")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_src_c")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_matched")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_src_a (
      id_a integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_src_a VALUES
      (101, 356570562, 1200), (102, 356570562, 2450),
      (103, 356308001, 500), (104, 356308001, 3200)")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_src_b (
      id_b integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_src_b VALUES
      (201, 356570562, 1210), (202, 356570562, 2500),
      (203, 356308001, 9000)")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_src_c (
      id_c integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_src_c VALUES
      (301, 356570562, 1205), (302, 356308001, 510)")
}

teardown_match_tables <- function(conn) {
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_src_a")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_src_b")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_src_c")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_matched")
}

spec_ab <- list(
  list(table = "working.test_src_a", col_id = "id_a"),
  list(table = "working.test_src_b", col_id = "id_b")
)
spec_abc <- list(
  list(table = "working.test_src_a", col_id = "id_a"),
  list(table = "working.test_src_b", col_id = "id_b"),
  list(table = "working.test_src_c", col_id = "id_c")
)
out_tbl <- "working.test_matched"

# --- Input validation ---

test_that("match_sources errors on fewer than 2 sources", {
  expect_error(
    lnk_match_sources(NULL, sources = list(list(table = "t", col_id = "x"))),
    "at least 2"
  )
})

test_that("match_sources errors on missing table in spec", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_match_sources(conn, sources = list(
      list(col_id = "x"),
      list(table = "working.test_src_b", col_id = "id_b")
    )),
    "missing.*table"
  )
})

test_that("match_sources errors on missing col_id in spec", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_match_sources(conn, sources = list(
      list(table = "working.test_src_a"),
      list(table = "working.test_src_b", col_id = "id_b")
    )),
    "missing.*col_id"
  )
})

test_that("match_sources errors on nonexistent source table", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_match_sources(conn, sources = list(
      list(table = "working.nonexistent", col_id = "x"),
      list(table = "working.test_src_b", col_id = "id_b")
    )),
    "not found"
  )
})

test_that("match_sources errors on bad distance", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  expect_error(
    lnk_match_sources(
      conn, sources = spec_ab, distance = -10, to = out_tbl
    ),
    "positive finite"
  )
  expect_error(
    lnk_match_sources(
      conn, sources = spec_ab, distance = Inf, to = out_tbl
    ),
    "positive finite"
  )
})

# --- Two-source matching ---

test_that("match_sources finds pairs within distance", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  lnk_match_sources(
    conn, sources = spec_ab, distance = 100,
    to = out_tbl, verbose = FALSE
  )
  result <- DBI::dbGetQuery(conn, paste("SELECT * FROM", out_tbl))
  # 101-201: |1200-1210|=10m, 102-202: |2450-2500|=50m
  expect_equal(nrow(result), 2L)
  expect_true(all(result$distance_m <= 100))
})

test_that("match_sources respects distance threshold", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  lnk_match_sources(
    conn, sources = spec_ab, distance = 15,
    to = out_tbl, verbose = FALSE
  )
  result <- DBI::dbGetQuery(conn, paste("SELECT * FROM", out_tbl))
  expect_equal(nrow(result), 1L)
  expect_equal(result$id_a, "101")
  expect_equal(result$id_b, "201")
})

test_that("match_sources output has correct columns", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  lnk_match_sources(
    conn, sources = spec_ab, to = out_tbl, verbose = FALSE
  )
  cols <- .lnk_table_columns(conn, out_tbl)
  expect_equal(cols, c("source_a", "id_a", "source_b", "id_b", "distance_m"))
})

# --- Deduplication (closest match wins) ---

test_that("match_sources keeps only closest match per source A record", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_dedup_a")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_dedup_b")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_dedup_out")
  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_dedup_a")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_dedup_b")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_dedup_out")
  })

  # Source A: one crossing
  DBI::dbExecute(conn, "
    CREATE TABLE working.test_dedup_a (
      id_a integer, blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_dedup_a VALUES (1, 100, 500)")

  # Source B: two crossings near A, one closer
  DBI::dbExecute(conn, "
    CREATE TABLE working.test_dedup_b (
      id_b integer, blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_dedup_b VALUES
      (10, 100, 510), (11, 100, 580)")

  dedup_srcs <- list(
    list(table = "working.test_dedup_a", col_id = "id_a"),
    list(table = "working.test_dedup_b", col_id = "id_b")
  )
  lnk_match_sources(
    conn, sources = dedup_srcs, distance = 100,
    to = "working.test_dedup_out", verbose = FALSE
  )
  sql <- "SELECT * FROM working.test_dedup_out"
  result <- DBI::dbGetQuery(conn, sql)

  # Only 1 match (closest: id_b=10 at 10m), not 2
  expect_equal(nrow(result), 1L)
  expect_equal(result$id_b, "10")
  expect_equal(result$distance_m, 10)
})

# --- Three-source matching ---

test_that("match_sources handles three-way pairwise matching", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  lnk_match_sources(
    conn, sources = spec_abc, distance = 100,
    to = out_tbl, verbose = FALSE
  )
  result <- DBI::dbGetQuery(conn, paste("SELECT * FROM", out_tbl))
  # A-B: 2, A-C: 2, B-C: 1 = 5 total
  expect_equal(nrow(result), 5L)
})

# --- Verbose output ---

test_that("match_sources verbose reports counts", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  expect_message(
    lnk_match_sources(
      conn, sources = spec_ab, to = out_tbl, verbose = TRUE
    ),
    "Matched 2 pairs"
  )
})

# --- Where filter ---

test_that("match_sources applies where filter", {
  conn <- skip_if_no_db()
  setup_match_tables(conn)
  on.exit(teardown_match_tables(conn))

  srcs <- list(
    list(table = "working.test_src_a", col_id = "id_a",
         where = "blue_line_key = 356570562"),
    list(table = "working.test_src_b", col_id = "id_b")
  )
  lnk_match_sources(
    conn, sources = srcs, distance = 100,
    to = out_tbl, verbose = FALSE
  )
  result <- DBI::dbGetQuery(conn, paste("SELECT * FROM", out_tbl))
  expect_equal(nrow(result), 2L)
})
