test_that("lnk_pipeline_crossings composes the five steps in order", {
  conn <- structure(list(), class = "DBIConnection")

  m_verify <- mockery::mock(invisible(NULL))
  m_pscis_build <- mockery::mock(invisible(conn))
  m_union <- mockery::mock(invisible(NULL))
  m_overrides <- mockery::mock(invisible(NULL))
  m_emit <- mockery::mock(invisible(NULL))

  with_mocked_bindings(
    lnk_inputs_verify = m_verify,
    .lnk_pipeline_pscis_build = m_pscis_build,
    .lnk_crossings_union = m_union,
    .lnk_crossings_apply_overrides = m_overrides,
    lnk_barriers_emit = m_emit,
    {
      result <- lnk_pipeline_crossings(
        conn = conn,
        aoi = "ADMS",
        cfg = list(),
        loaded = list(),
        schema = "working_adms"
      )
    }
  )

  # Returns conn invisibly for piping.
  expect_identical(result, conn)

  # All five steps called exactly once.
  mockery::expect_called(m_verify, 1)
  mockery::expect_called(m_pscis_build, 1)
  mockery::expect_called(m_union, 1)
  mockery::expect_called(m_overrides, 1)
  mockery::expect_called(m_emit, 1)

  # lnk_inputs_verify gets the three required tables.
  required <- mockery::mock_args(m_verify)[[1]][[2]]
  expect_setequal(required, c(
    "whse_fish.pscis_assessment_svw",
    "fresh.modelled_stream_crossings",
    "working_adms.dams"
  ))

  # .lnk_pipeline_pscis_build receives aoi, schema, loaded, both source
  # tables, and clamps snap_tolerance to >= 150 (bcfp uses 150m).
  build_args <- mockery::mock_args(m_pscis_build)[[1]]
  expect_equal(build_args$aoi, "ADMS")
  expect_equal(build_args$schema, "working_adms")
  expect_equal(build_args$pscis_table, "whse_fish.pscis_assessment_svw")
  expect_equal(build_args$modelled_table, "fresh.modelled_stream_crossings")
  expect_equal(build_args$snap_tolerance, 150)  # max(100, 150)
})

test_that("lnk_pipeline_crossings clamps snap_tolerance to >= 150", {
  conn <- structure(list(), class = "DBIConnection")
  m_pscis_build <- mockery::mock(invisible(conn), cycle = TRUE)
  with_mocked_bindings(
    lnk_inputs_verify = mockery::mock(invisible(NULL), cycle = TRUE),
    .lnk_pipeline_pscis_build = m_pscis_build,
    .lnk_crossings_union = mockery::mock(invisible(NULL), cycle = TRUE),
    .lnk_crossings_apply_overrides = mockery::mock(invisible(NULL), cycle = TRUE),
    lnk_barriers_emit = mockery::mock(invisible(NULL), cycle = TRUE),
    {
      # Caller-passed 200 > 150 → 200 wins.
      lnk_pipeline_crossings(conn, "ADMS", list(), list(), "s",
                             snap_tolerance = 200)
      # Caller-passed 50 < 150 → 150 floor.
      lnk_pipeline_crossings(conn, "ADMS", list(), list(), "s",
                             snap_tolerance = 50)
    }
  )
  expect_equal(mockery::mock_args(m_pscis_build)[[1]]$snap_tolerance, 200)
  expect_equal(mockery::mock_args(m_pscis_build)[[2]]$snap_tolerance, 150)
})

test_that("lnk_pipeline_crossings validates argument shapes", {
  conn <- structure(list(), class = "DBIConnection")
  expect_error(lnk_pipeline_crossings("not a conn", "ADMS",
                                       list(), list(), "s"))
  expect_error(lnk_pipeline_crossings(conn, "", list(), list(), "s"))
  expect_error(lnk_pipeline_crossings(conn, "ADMS", list(), list(), ""))
  expect_error(lnk_pipeline_crossings(conn, "ADMS", list(), list(), "s",
                                       snap_tolerance = -1))
  expect_error(lnk_pipeline_crossings(conn, "ADMS", list(), list(), "s",
                                       snap_tolerance = c(1, 2)))
})
