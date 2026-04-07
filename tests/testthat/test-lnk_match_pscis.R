# lnk_match_pscis is a wrapper — test the xref logic and defaults

test_that("match_pscis errors on missing xref CSV", {
  conn <- skip_if_no_db()
  expect_error(
    lnk_match_pscis(
      conn, xref_csv = "/nonexistent/xref.csv",
      crossings = "working.test_src_a", pscis = "working.test_src_b"
    ),
    "not found"
  )
})

test_that("match_pscis errors on xref CSV with missing columns", {
  conn <- skip_if_no_db()
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("wrong_col,modelled_crossing_id\n1,2", tmp)

  expect_error(
    lnk_match_pscis(
      conn, xref_csv = tmp,
      crossings = "working.test_src_a", pscis = "working.test_src_b"
    ),
    "missing required columns.*stream_crossing_id"
  )
})

test_that("match_pscis with xref applies known matches first", {
  conn <- skip_if_no_db()
  DBI::dbExecute(conn, "CREATE SCHEMA IF NOT EXISTS working")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_pscis_src")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_model_src")
  DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_mp_out")
  on.exit({
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_pscis_src")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_model_src")
    DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.test_mp_out")
  })

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_pscis_src (
      stream_crossing_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_pscis_src VALUES
      (501, 356570562, 1200),
      (502, 356570562, 2450)")

  DBI::dbExecute(conn, "
    CREATE TABLE working.test_model_src (
      modelled_crossing_id integer PRIMARY KEY,
      blue_line_key bigint,
      downstream_route_measure numeric)")
  DBI::dbExecute(conn, "
    INSERT INTO working.test_model_src VALUES
      (601, 356570562, 1210),
      (602, 356570562, 2500)")

  # xref: manually match 501->601
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c(
    "stream_crossing_id,modelled_crossing_id",
    "501,601"
  ), tmp)

  lnk_match_pscis(
    conn, crossings = "working.test_model_src",
    pscis = "working.test_pscis_src", xref_csv = tmp,
    to = "working.test_mp_out", verbose = FALSE
  )

  result <- DBI::dbGetQuery(conn, "
    SELECT * FROM working.test_mp_out ORDER BY id_a")

  # xref: 501->601 (distance 0)
  # spatial: 502->602 (50m)
  # 501 and 601 excluded from spatial since they're in xref
  expect_equal(nrow(result), 2L)
  xref_row <- result[result$distance_m == 0, ]
  expect_equal(xref_row$id_a, "501")
  expect_equal(xref_row$id_b, "601")
})
