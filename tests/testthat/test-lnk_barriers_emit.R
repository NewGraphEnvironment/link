test_that("lnk_barriers_emit issues DROP + CREATE for all five tables", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"working_adms\""), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      result <- lnk_barriers_emit(conn, schema = "working_adms")
    }
  )
  expect_null(result)
  args <- mockery::mock_args(m_exec)
  # 10 calls: 5 DROPs + 5 CREATEs.
  expect_equal(length(args), 10L)
  all_sql <- paste(vapply(args, function(a) a[[2]], character(1)),
                   collapse = "\n")
  for (tbl in c("crossings_lookup", "barriers_anthropogenic",
                "barriers_pscis", "barriers_dams",
                "barriers_remediations")) {
    expect_match(all_sql, sprintf("DROP TABLE IF EXISTS .*\\.%s", tbl))
    expect_match(all_sql, sprintf("CREATE TABLE .*\\.%s AS", tbl))
  }
})

test_that("lnk_barriers_emit anthropogenic filter matches bcfp semantics", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_barriers_emit(conn, schema = "s")
    }
  )
  all_sql <- paste(vapply(mockery::mock_args(m_exec),
                          function(a) a[[2]], character(1)),
                   collapse = "\n")
  expect_match(all_sql, "barrier_status IN \\('BARRIER', 'POTENTIAL'\\)")
  expect_match(all_sql, "blue_line_key = watershed_key")
})

test_that("lnk_barriers_emit pscis branch filters by crossing_source = 'PSCIS'", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_barriers_emit(conn, schema = "s")
    }
  )
  all_sql <- paste(vapply(mockery::mock_args(m_exec),
                          function(a) a[[2]], character(1)),
                   collapse = "\n")
  expect_match(all_sql, "crossing_source = 'PSCIS'")
  expect_match(all_sql, "crossing_source = 'CABD'")
})

test_that("lnk_barriers_emit remediations branch is anthropogenic UNION REMEDIATED+PASSABLE", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote,
    dbExecute = m_exec,
    .package = "DBI",
    {
      lnk_barriers_emit(conn, schema = "s")
    }
  )
  all_sql <- paste(vapply(mockery::mock_args(m_exec),
                          function(a) a[[2]], character(1)),
                   collapse = "\n")
  expect_match(all_sql, "FROM .*\\.barriers_anthropogenic")
  expect_match(all_sql, "UNION ALL")
  expect_match(all_sql, "pscis_status = 'REMEDIATED'")
  expect_match(all_sql, "barrier_status = 'PASSABLE'")
})

test_that("lnk_barriers_emit validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_barriers_emit("not a conn", "s"))
  expect_error(lnk_barriers_emit(conn, ""))
  expect_error(lnk_barriers_emit(conn, c("a", "b")))
})
