test_that(".lnk_crossings_apply_overrides applies both fixes when both tables exist", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote_id <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'s'"),
                               DBI::SQL("'pscis_fixes'"),
                               DBI::SQL("'s'"),
                               DBI::SQL("'crossing_fixes'"),
                               cycle = TRUE)
  m_query <- mockery::mock(
    data.frame(present = TRUE),
    data.frame(present = TRUE)
  )
  m_exec <- mockery::mock(1L, 1L)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbGetQuery = m_query,
    dbExecute = m_exec,
    .package = "DBI",
    {
      result <- link:::.lnk_crossings_apply_overrides(conn, "s")
    }
  )
  expect_null(result)
  expect_equal(length(mockery::mock_args(m_exec)), 2L)
  pscis_sql <- mockery::mock_args(m_exec)[[1]][[2]]
  expect_match(pscis_sql, "UPDATE .*\\.crossings c\\s+SET barrier_status = pf\\.barrier_status")
  expect_match(pscis_sql, "c\\.crossing_source = 'PSCIS'")

  modelled_sql <- mockery::mock_args(m_exec)[[2]][[2]]
  expect_match(modelled_sql, "UPDATE .*\\.crossings c\\s+SET barrier_status = 'PASSABLE'")
  expect_match(modelled_sql, "c\\.crossing_source = 'MODELLED_CROSSINGS'")
  expect_match(modelled_sql, "\\+ 1000000000")
  expect_match(modelled_sql, "structure IN \\('NONE', 'OBS'\\)")
})

test_that(".lnk_crossings_apply_overrides skips PSCIS update when pscis_fixes absent", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote_id <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'s'"), cycle = TRUE)
  m_query <- mockery::mock(
    data.frame(present = FALSE),
    data.frame(present = TRUE)
  )
  m_exec <- mockery::mock(1L)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbGetQuery = m_query,
    dbExecute = m_exec,
    .package = "DBI",
    {
      link:::.lnk_crossings_apply_overrides(conn, "s")
    }
  )
  expect_equal(length(mockery::mock_args(m_exec)), 1L)
  expect_match(mockery::mock_args(m_exec)[[1]][[2]],
               "c\\.crossing_source = 'MODELLED_CROSSINGS'")
})

test_that(".lnk_crossings_apply_overrides is a no-op when both fix tables absent", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote_id <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'s'"), cycle = TRUE)
  m_query <- mockery::mock(
    data.frame(present = FALSE),
    data.frame(present = FALSE)
  )
  m_exec <- mockery::mock()
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbGetQuery = m_query,
    dbExecute = m_exec,
    .package = "DBI",
    {
      result <- link:::.lnk_crossings_apply_overrides(conn, "s")
    }
  )
  expect_null(result)
  expect_equal(length(mockery::mock_args(m_exec)), 0L)
})

test_that(".lnk_crossings_apply_overrides validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(link:::.lnk_crossings_apply_overrides("not a conn", "s"))
  expect_error(link:::.lnk_crossings_apply_overrides(conn, ""))
  expect_error(link:::.lnk_crossings_apply_overrides(conn, c("a", "b")))
})
