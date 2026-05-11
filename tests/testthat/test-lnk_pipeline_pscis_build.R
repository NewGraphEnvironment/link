test_that(".lnk_pipeline_pscis_build emits the five-step SQL chain", {
  conn <- structure(list(), class = "DBIConnection")
  m_exec <- mockery::mock(1L, cycle = TRUE)
  # Probe for xref staging returns "present" so Step 5 runs too.
  m_query <- mockery::mock(data.frame(present = TRUE), cycle = TRUE)
  m_quote_id <- mockery::mock(DBI::SQL("\"x\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'x'"), cycle = TRUE)
  m_pick <- mockery::mock(invisible(NULL))

  with_mocked_bindings(
    dbExecute = m_exec,
    dbGetQuery = m_query,
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    .package = "DBI",
    {
      with_mocked_bindings(
        frs_candidates_pick = m_pick,
        .package = "fresh",
        {
          link:::.lnk_pipeline_pscis_build(
            conn = conn, aoi = "ADMS", schema = "working_adms"
          )
        }
      )
    }
  )

  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")

  # Step 1: multi-stream snap → pscis_stream_candidates (built by
  # lnk_points_snap which calls dbExecute under the hood).
  expect_match(sql, "CREATE TABLE working_adms\\.pscis_stream_candidates")

  # Step 2: enrich + score → pscis_streams_150m. Verify the verbatim
  # bcfp name_score + width_order_score CASE markers + the modelled
  # LEFT JOIN inline.
  expect_match(sql, "CREATE TABLE working_adms\\.pscis_streams_150m AS")
  expect_match(sql, "name_score")
  expect_match(sql, "width_order_score")
  expect_match(sql,
               "replace\\(UPPER\\(a\\.stream_name\\), ' CR\\.', ' CREEK'\\)")
  expect_match(sql, "modelled_xing_dist_instream")

  # Step 3: b-side dedup UPDATE + close-enough reset.
  expect_match(sql, "WITH dups AS")
  expect_match(sql, "multiple_match_ind = TRUE")
  expect_match(sql,
               "SET multiple_match_ind = NULL\\s+WHERE multiple_match_ind IS TRUE")

  # Step 4: frs_candidates_pick called once.
  mockery::expect_called(m_pick, 1)
  pick_args <- mockery::mock_args(m_pick)[[1]]
  expect_equal(pick_args$table_in,  "working_adms.pscis_streams_150m")
  expect_equal(pick_args$table_to,  "working_adms.pscis_picked")
  expect_equal(pick_args$col_key,   "stream_crossing_id")
  expect_match(pick_args$exp_filter,
               "name_score != -100 AND width_order_score != -100")
  expect_true(any(grepl("name_score DESC", pick_args$order_by)))

  # Step 4b: AOI filter → <schema>.pscis.
  expect_match(sql, "CREATE TABLE working_adms\\.pscis AS")
  expect_match(sql, "FROM working_adms\\.pscis_picked")

  # Step 4c: DBSCAN 5m cluster dedup.
  expect_match(sql, "ST_ClusterDBSCAN\\(geom_snapped, 5, 1\\)")
  expect_match(sql, "DISTINCT ON \\(cid\\)")

  # Step 4d: UNIQUE(blk,drm) dedup.
  expect_match(sql,
               "DISTINCT ON \\(blue_line_key, downstream_route_measure\\)")

  # Step 5: xref UPDATE + INSERT (two-branch UNION ALL).
  expect_match(sql,
               "DELETE FROM working_adms\\.pscis\\s+WHERE stream_crossing_id IN")
  expect_match(sql, "INSERT INTO working_adms\\.pscis")
  expect_match(sql, "UNION ALL")
  expect_match(sql, "x\\.modelled_crossing_id IS NOT NULL")
  expect_match(sql, "x\\.linear_feature_id IS NOT NULL")
})

test_that(".lnk_pipeline_pscis_build skips Step 5 when xref staging table absent", {
  conn <- structure(list(), class = "DBIConnection")
  m_exec <- mockery::mock(1L, cycle = TRUE)
  # Probe returns zero rows → no xref staging table.
  m_query <- mockery::mock(data.frame(present = FALSE), cycle = TRUE)
  m_quote_id <- mockery::mock(DBI::SQL("\"x\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'x'"), cycle = TRUE)

  with_mocked_bindings(
    dbExecute = m_exec,
    dbGetQuery = m_query,
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    .package = "DBI",
    {
      with_mocked_bindings(
        frs_candidates_pick = mockery::mock(invisible(NULL)),
        .package = "fresh",
        {
          link:::.lnk_pipeline_pscis_build(
            conn = conn, aoi = "ADMS", schema = "working_adms"
          )
        }
      )
    }
  )
  sql <- paste(vapply(mockery::mock_args(m_exec),
                      function(a) a[[2]], character(1)),
               collapse = "\n")

  # Step 5 SQL markers must NOT appear.
  expect_no_match(sql,
                  "DELETE FROM working_adms\\.pscis\\s+WHERE stream_crossing_id IN")
  expect_no_match(sql, "INSERT INTO working_adms\\.pscis")
})

test_that(".lnk_pipeline_pscis_build stages xref from `loaded` when provided", {
  conn <- structure(list(), class = "DBIConnection")
  xref_df <- data.frame(
    stream_crossing_id   = c(1L, 2L),
    modelled_crossing_id = c(10L, NA_integer_),
    linear_feature_id    = c(NA_real_, 200),
    watershed_group_code = c("ADMS", "ADMS"),
    stringsAsFactors = FALSE
  )
  m_exec <- mockery::mock(1L, cycle = TRUE)
  m_query <- mockery::mock(data.frame(present = TRUE), cycle = TRUE)
  m_quote_id <- mockery::mock(DBI::SQL("\"x\""), cycle = TRUE)
  m_quote_str <- mockery::mock(DBI::SQL("'x'"), cycle = TRUE)
  m_write <- mockery::mock(invisible(NULL))

  with_mocked_bindings(
    dbExecute = m_exec,
    dbGetQuery = m_query,
    dbQuoteIdentifier = m_quote_id,
    dbQuoteString = m_quote_str,
    dbWriteTable = m_write,
    .package = "DBI",
    {
      with_mocked_bindings(
        frs_candidates_pick = mockery::mock(invisible(NULL)),
        .package = "fresh",
        {
          link:::.lnk_pipeline_pscis_build(
            conn = conn, aoi = "ADMS", schema = "working_adms",
            loaded = list(pscis_modelledcrossings_streams_xref = xref_df)
          )
        }
      )
    }
  )
  mockery::expect_called(m_write, 1)
  write_args <- mockery::mock_args(m_write)[[1]]
  expect_equal(write_args[[3]], xref_df)
})

test_that(".lnk_pipeline_pscis_build validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(link:::.lnk_pipeline_pscis_build("nope", "ADMS", "s"))
  expect_error(link:::.lnk_pipeline_pscis_build(conn, "", "s"))
  expect_error(link:::.lnk_pipeline_pscis_build(conn, "ADMS", ""))
  expect_error(link:::.lnk_pipeline_pscis_build(conn, "ADMS", "s",
                                                snap_tolerance = -1))
  expect_error(link:::.lnk_pipeline_pscis_build(conn, "ADMS", "s",
                                                snap_num_features = 0))
})
