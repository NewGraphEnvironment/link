test_that(".lnk_crossings_union builds the union SQL with PSCIS + CABD + modelled branches", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote_id <- mockery::mock(DBI::SQL("\"working_adms\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'ADMS'"), cycle = TRUE)
  m_query <- mockery::mock(data.frame(dummy = TRUE), cycle = TRUE)
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbGetQuery = m_query,
    dbExecute = m_exec,
    .package = "DBI",
    {
      result <- link:::.lnk_crossings_union(conn, schema = "working_adms", aoi = "ADMS")
    }
  )
  expect_null(result)
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_match(sql, "DROP TABLE IF EXISTS .*\\.crossings")
  expect_match(sql, "CREATE TABLE .*\\.crossings AS")
  expect_match(sql, "'PSCIS'::text")
  expect_match(sql, "'CABD'::text")
  expect_match(sql, "'MODELLED_CROSSINGS'::text")
  expect_match(sql, "'DAM'::text\\s+AS crossing_feature_type")
  expect_match(sql, "modelled_crossing_id::bigint \\+ 1000000000")
  # CABD + modelled branches use INNER JOIN to FWA so missing
  # linear_feature_id fails loud instead of silently dropping rows.
  expect_match(sql,
               "FROM .* d\\s+INNER JOIN whse_basemapping\\.fwa_stream_networks_sp fwa_d")
  expect_match(sql,
               "FROM .* m\\s+INNER JOIN whse_basemapping\\.fwa_stream_networks_sp fwa_m")
  # PSCIS branch reads from <schema>.pscis (post-#154); modelled-branch
  # xref exclusion sources from the same table.
  expect_match(sql, "FROM .*\\.pscis p")
  expect_match(sql, "modelled_crossing_id NOT IN")
  expect_match(sql, "FROM .*\\.pscis")
})

test_that(".lnk_crossings_union includes crossing_fixes filter when staging table present", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote_id <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'AOI'"), cycle = TRUE)
  # First call (table-presence probe) returns one row → table present.
  m_query <- mockery::mock(data.frame(x = 1L))
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbGetQuery = m_query,
    dbExecute = m_exec,
    .package = "DBI",
    {
      link:::.lnk_crossings_union(conn, "s", "AOI")
    }
  )
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_match(sql, "LEFT JOIN .*\\.crossing_fixes cf")
  expect_match(sql, "cf\\.structure IS NULL OR cf\\.structure = 'OBS'")
})

test_that(".lnk_crossings_union skips crossing_fixes filter when staging table missing", {
  conn <- structure(list(), class = "DBIConnection")
  m_quote_id <- mockery::mock(DBI::SQL("\"s\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'AOI'"), cycle = TRUE)
  # Zero-row data.frame → probe says table missing.
  m_query <- mockery::mock(data.frame(x = integer(0)))
  m_exec <- mockery::mock(1L, cycle = TRUE)
  with_mocked_bindings(
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbGetQuery = m_query,
    dbExecute = m_exec,
    .package = "DBI",
    {
      link:::.lnk_crossings_union(conn, "s", "AOI")
    }
  )
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")
  expect_no_match(sql, "LEFT JOIN .*\\.crossing_fixes cf")
  expect_no_match(sql, "cf\\.structure IS NULL")
})

test_that(".lnk_crossings_union validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(link:::.lnk_crossings_union("not a conn", "s", "AOI"))
  expect_error(link:::.lnk_crossings_union(conn, "", "AOI"))
  expect_error(link:::.lnk_crossings_union(conn, "s", ""))
  expect_error(link:::.lnk_crossings_union(conn, "s", c("A", "B")))
})
