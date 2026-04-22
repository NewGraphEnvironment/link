# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_load rejects invalid aoi", {
  cfg <- lnk_config("bcfishpass")

  expect_error(
    lnk_pipeline_load("mock-conn", aoi = NULL, cfg = cfg, schema = "working"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "", cfg = cfg, schema = "working"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = c("BULK", "ADMS"),
                       cfg = cfg, schema = "working"),
    "aoi must be a single non-empty string"
  )
})

test_that("lnk_pipeline_load rejects non-lnk_config cfg", {
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "BULK",
                       cfg = list(name = "bcfishpass"),
                       schema = "working"),
    "cfg must be an lnk_config object"
  )
})

test_that("lnk_pipeline_load rejects invalid schema", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "BULK", cfg = cfg,
                       schema = "bad;name"),
    "schema"
  )
})

# -- apply_fixes SQL shape (mocked) -----------------------------------------

test_that(".lnk_pipeline_apply_fixes generates PASSABLE update SQL", {
  # Minimal stub — one fix row for the target AOI
  cfg_stub <- structure(list(
    overrides = list(
      modelled_fixes = data.frame(
        watershed_group_code = "BULK",
        modelled_crossing_id = 123L,
        structure = "NONE",
        stringsAsFactors = FALSE
      )
    )
  ), class = c("lnk_config", "list"))

  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  # dbWriteTable lives in DBI — mock it to a no-op for this shape test
  local_mocked_bindings(
    dbWriteTable = function(...) invisible(NULL),
    .package = "DBI"
  )

  .lnk_pipeline_apply_fixes("mock-conn", aoi = "BULK", cfg = cfg_stub,
                             schema = "working_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "UPDATE working_bulk.crossings")
  expect_match(joined, "SET barrier_status = 'PASSABLE'")
  expect_match(joined, "FROM working_bulk.crossing_fixes")
  expect_match(joined, "structure IN \\('NONE', 'OBS'\\)")
})

test_that(".lnk_pipeline_apply_fixes is a no-op when no fixes match AOI", {
  cfg_stub <- structure(list(
    overrides = list(
      modelled_fixes = data.frame(
        watershed_group_code = "ADMS",      # different WSG
        modelled_crossing_id = 123L,
        structure = "NONE",
        stringsAsFactors = FALSE
      )
    )
  ), class = c("lnk_config", "list"))

  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbWriteTable = function(...) {
      stop("dbWriteTable should not be called when no rows match")
    },
    .package = "DBI"
  )

  .lnk_pipeline_apply_fixes("mock-conn", aoi = "BULK", cfg = cfg_stub,
                             schema = "working_bulk")

  expect_length(captured, 0L)
})

test_that(".lnk_pipeline_apply_fixes is a no-op when no fixes in config", {
  cfg_stub <- structure(list(
    overrides = list()   # no modelled_fixes at all
  ), class = c("lnk_config", "list"))

  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  .lnk_pipeline_apply_fixes("mock-conn", aoi = "BULK", cfg = cfg_stub,
                             schema = "working_bulk")

  expect_length(captured, 0L)
})

# -- apply_pscis branching --------------------------------------------------

test_that(".lnk_pipeline_apply_pscis is a no-op when no PSCIS fixes match", {
  cfg_stub <- structure(list(
    overrides = list(
      pscis_barrier_status = data.frame(
        watershed_group_code = "ADMS",      # different WSG
        stream_crossing_id = 456L,
        user_barrier_status = "BARRIER",
        stringsAsFactors = FALSE
      )
    )
  ), class = c("lnk_config", "list"))

  override_calls <- 0L
  local_mocked_bindings(
    lnk_override = function(...) {
      override_calls <<- override_calls + 1L
      invisible(NULL)
    }
  )

  .lnk_pipeline_apply_pscis("mock-conn", aoi = "BULK", cfg = cfg_stub,
                              schema = "working_bulk")

  expect_equal(override_calls, 0L)
})
