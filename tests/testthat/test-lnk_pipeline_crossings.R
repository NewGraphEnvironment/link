test_that("lnk_pipeline_crossings composes the five steps in order", {
  conn <- structure(list(), class = "DBIConnection")

  m_verify <- mockery::mock(invisible(NULL))
  m_snap <- mockery::mock(invisible("schema.pscis_assessment_snapped"))
  m_union <- mockery::mock(invisible(NULL))
  m_overrides <- mockery::mock(invisible(NULL))
  m_emit <- mockery::mock(invisible(NULL))

  with_mocked_bindings(
    lnk_inputs_verify = m_verify,
    lnk_points_snap = m_snap,
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
  mockery::expect_called(m_snap, 1)
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

  # lnk_points_snap is called on whse_fish.pscis_assessment_svw with the
  # default 100 m tolerance.
  snap_args <- mockery::mock_args(m_snap)[[1]]
  expect_equal(snap_args$table_in, "whse_fish.pscis_assessment_svw")
  expect_equal(snap_args$table_out, "working_adms.pscis_assessment_snapped")
  expect_equal(snap_args$snap_tolerance, 100)
})

test_that("lnk_pipeline_crossings threads custom snap_tolerance through", {
  conn <- structure(list(), class = "DBIConnection")

  m_verify <- mockery::mock(invisible(NULL))
  m_snap <- mockery::mock(invisible(NULL))
  m_union <- mockery::mock(invisible(NULL))
  m_overrides <- mockery::mock(invisible(NULL))
  m_emit <- mockery::mock(invisible(NULL))

  with_mocked_bindings(
    lnk_inputs_verify = m_verify,
    lnk_points_snap = m_snap,
    .lnk_crossings_union = m_union,
    .lnk_crossings_apply_overrides = m_overrides,
    lnk_barriers_emit = m_emit,
    {
      lnk_pipeline_crossings(
        conn = conn, aoi = "ADMS", cfg = list(), loaded = list(),
        schema = "s", snap_tolerance = 200
      )
    }
  )

  expect_equal(mockery::mock_args(m_snap)[[1]]$snap_tolerance, 200)
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
