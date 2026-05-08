test_that("lnk_barriers_emit issues SQL containing all five table operations", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"working_adms\""))
  m_exec <- mockery::mock(1L)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      result <- lnk_barriers_emit(conn, schema = "working_adms")
    }
  )
  expect_null(result)
  sql <- mockery::mock_args(m_exec)[[1]][[2]]
  for (tbl in c("crossings_lookup", "barriers_anthropogenic",
                "barriers_pscis", "barriers_dams",
                "barriers_remediations")) {
    expect_match(sql, sprintf("DROP TABLE IF EXISTS .*\\.%s", tbl))
    expect_match(sql, sprintf("CREATE TABLE .*\\.%s AS", tbl))
  }
})

test_that("lnk_barriers_emit anthropogenic filter matches bcfp semantics", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"s\""))
  m_exec <- mockery::mock(1L)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_barriers_emit(conn, schema = "s")
    }
  )
  sql <- mockery::mock_args(m_exec)[[1]][[2]]
  expect_match(sql, "barrier_status IN \\('BARRIER', 'POTENTIAL'\\)")
  expect_match(sql, "blue_line_key = watershed_key")
})

test_that("lnk_barriers_emit pscis branch filters by crossing_source = 'PSCIS'", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"s\""))
  m_exec <- mockery::mock(1L)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_barriers_emit(conn, schema = "s")
    }
  )
  sql <- mockery::mock_args(m_exec)[[1]][[2]]
  expect_match(sql, "crossing_source = 'PSCIS'")
  expect_match(sql, "crossing_source = 'CABD'")
})

test_that("lnk_barriers_emit remediations branch is anthropogenic UNION REMEDIATED+PASSABLE", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"s\""))
  m_exec <- mockery::mock(1L)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_barriers_emit(conn, schema = "s")
    }
  )
  sql <- mockery::mock_args(m_exec)[[1]][[2]]
  expect_match(sql, "FROM .*\\.barriers_anthropogenic")
  expect_match(sql, "UNION ALL")
  expect_match(sql, "pscis_status = 'REMEDIATED'")
  expect_match(sql, "barrier_status = 'PASSABLE'")
})

test_that("lnk_barriers_emit validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_barriers_emit("not a conn", "s"))
  expect_error(lnk_barriers_emit(conn, ""))
  expect_error(lnk_barriers_emit(conn, c("a", "b")))
})
