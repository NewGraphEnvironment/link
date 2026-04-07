# lnk_match_moti is a thin wrapper — test signature and delegation

test_that("match_moti matches with wider distance default", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_src")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_cross_src")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_out")
  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_src")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_cross_src")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_out")
  })

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_moti_src (
      chris_culvert_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_moti_src VALUES
      (901, 356570562, 1320)")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_cross_src (
      modelled_crossing_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_cross_src VALUES
      (601, 356570562, 1200)")

  # 120m apart — within 150m default but outside 100m
  lnk_match_moti(
    conn, crossings = "working.test_cross_src",
    moti = "working.test_moti_src",
    to = "working.test_moti_out", verbose = FALSE
  )

  result <- DBI::dbGetQuery(conn, "SELECT * FROM working.test_moti_out")
  expect_equal(nrow(result), 1L)
  expect_equal(result$distance_m, 120)
})

test_that("match_moti respects custom col_id_moti", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_custom")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_cross_custom")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_out2")
  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_custom")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_cross_custom")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_moti_out2")
  })

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_moti_custom (
      custom_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_moti_custom VALUES (801, 356570562, 1200)")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_cross_custom (
      modelled_crossing_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_cross_custom VALUES (601, 356570562, 1210)")

  lnk_match_moti(
    conn, crossings = "working.test_cross_custom",
    moti = "working.test_moti_custom",
    col_id_moti = "custom_id",
    to = "working.test_moti_out2", verbose = FALSE
  )

  result <- DBI::dbGetQuery(conn, "SELECT * FROM working.test_moti_out2")
  expect_equal(nrow(result), 1L)
  expect_equal(result$id_a, "801")
})
