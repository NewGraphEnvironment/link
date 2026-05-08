test_that("lnk_points_snap builds expected SQL with default args", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(
    DBI::SQL('"geom"'), DBI::SQL('"geom"'), DBI::SQL('"geom"'),
    DBI::SQL('"geom"'), DBI::SQL('"geom"'),
    cycle = TRUE
  )
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      result <- lnk_points_snap(conn,
                                table_in = "whse_fish.pscis_assessment_svw",
                                table_out = "fresh.pscis_assessment_snapped")
    }
  )
  expect_equal(result, "fresh.pscis_assessment_snapped")
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_match(sql, "DROP TABLE IF EXISTS fresh\\.pscis_assessment_snapped")
  expect_match(sql, "CREATE TABLE fresh\\.pscis_assessment_snapped")
  expect_match(sql, "FROM whse_fish\\.pscis_assessment_svw pts")
  expect_match(sql, "wscode_ltree != '999'")
  expect_match(sql, "edge_type NOT IN \\(1425\\)")
  expect_match(sql, "ST_DWithin\\(s\\.geom, ST_GeometryN\\(pts\\.")
  expect_match(sql, "100\\.0+") # snap_tolerance
})

test_that("lnk_points_snap accepts vector exclude_edge_types", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL('"geom"'), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_points_snap(conn, "x.in", "y.out",
                      exclude_edge_types = c(1410L, 1425L))
    }
  )
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_match(sql, "edge_type NOT IN \\(1410, 1425\\)")
})

test_that("lnk_points_snap omits exclude_edge_types when integer(0)", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL('"geom"'), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_points_snap(conn, "x.in", "y.out",
                      exclude_edge_types = integer(0))
    }
  )
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_no_match(sql, "edge_type NOT IN")
})

test_that("lnk_points_snap honours blue_line_key_col + stream_order_min", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL('"blue_line_key"'),
                            DBI::SQL('"geom"'), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_points_snap(conn, "x.in", "y.out",
                      blue_line_key_col = "blue_line_key",
                      stream_order_min = 3)
    }
  )
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_match(sql, "s\\.blue_line_key = pts\\.")
  expect_match(sql, "s\\.stream_order >= 3")
})

test_that("lnk_points_snap validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_points_snap("not a conn", "a.b", "c.d"))
  expect_error(lnk_points_snap(conn, "", "c.d"))
  expect_error(lnk_points_snap(conn, "a.b", ""))
  expect_error(lnk_points_snap(conn, "a.b", "c.d", snap_tolerance = -1))
  expect_error(lnk_points_snap(conn, "a.b", "c.d", snap_tolerance = c(1, 2)))
})
