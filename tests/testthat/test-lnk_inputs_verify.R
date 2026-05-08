test_that("lnk_inputs_verify returns invisible NULL when all tables exist", {
  conn <- structure(list(), class = "DBIConnection")
  fake_result <- data.frame(
    schema_name = c("whse_fish", "cabd"),
    table_name = c("pscis_assessment_svw", "dams"),
    exists = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  )
  m_query <- mockery::mock(fake_result)
  m_quote <- mockery::mock(DBI::SQL("'q'"), cycle = TRUE)
  with_mocked_bindings(
    dbGetQuery = m_query,
    dbQuoteString = m_quote,
    .package = "DBI",
    {
      result <- lnk_inputs_verify(conn,
                                  c("whse_fish.pscis_assessment_svw", "cabd.dams"))
    }
  )
  expect_null(result)
  mockery::expect_called(m_query, 1)
})

test_that("lnk_inputs_verify fails loud listing missing tables", {
  conn <- structure(list(), class = "DBIConnection")
  fake_result <- data.frame(
    schema_name = c("whse_fish", "cabd", "fresh"),
    table_name = c("pscis_assessment_svw", "dams", "modelled_stream_crossings"),
    exists = c(TRUE, FALSE, FALSE),
    stringsAsFactors = FALSE
  )
  m_query <- mockery::mock(fake_result)
  m_quote <- mockery::mock(DBI::SQL("'q'"), cycle = TRUE)
  with_mocked_bindings(
    dbGetQuery = m_query,
    dbQuoteString = m_quote,
    .package = "DBI",
    {
      expect_error(
        lnk_inputs_verify(conn, c(
          "whse_fish.pscis_assessment_svw",
          "cabd.dams",
          "fresh.modelled_stream_crossings"
        )),
        "cabd\\.dams"
      )
    }
  )
})

test_that("lnk_inputs_verify rejects malformed schema.table strings", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(
    lnk_inputs_verify(conn, c("no_dot_here")),
    "expected '<schema>\\.<table>' format"
  )
  expect_error(
    lnk_inputs_verify(conn, c("schema.")),
    "expected '<schema>\\.<table>' format"
  )
  expect_error(
    lnk_inputs_verify(conn, c(".table")),
    "expected '<schema>\\.<table>' format"
  )
})

test_that("lnk_inputs_verify validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_inputs_verify(conn, character(0)))
  expect_error(lnk_inputs_verify(conn, NA_character_))
  expect_error(lnk_inputs_verify("not a conn", "schema.table"))
})
