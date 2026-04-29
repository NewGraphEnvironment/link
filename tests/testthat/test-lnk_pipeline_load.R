# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_load rejects invalid aoi", {
  cfg <- lnk_config("bcfishpass")
  loaded <- list()

  expect_error(
    lnk_pipeline_load("mock-conn", aoi = NULL, cfg = cfg, loaded = loaded,
                       schema = "working"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "", cfg = cfg, loaded = loaded,
                       schema = "working"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = c("BULK", "ADMS"),
                       cfg = cfg, loaded = loaded, schema = "working"),
    "aoi must be a single non-empty string"
  )
})

test_that("lnk_pipeline_load rejects non-lnk_config cfg", {
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "BULK",
                       cfg = list(name = "bcfishpass"), loaded = list(),
                       schema = "working"),
    "cfg must be an lnk_config object"
  )
})

test_that("lnk_pipeline_load rejects non-list loaded", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "BULK", cfg = cfg,
                       loaded = "not-a-list", schema = "working"),
    "loaded must be a named list"
  )
})

test_that("lnk_pipeline_load rejects invalid schema", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_load("mock-conn", aoi = "BULK", cfg = cfg,
                       loaded = list(), schema = "bad;name"),
    "schema"
  )
})

# -- apply_fixes SQL shape (mocked) -----------------------------------------

test_that(".lnk_pipeline_apply_fixes generates PASSABLE update SQL", {
  loaded_stub <- list(
    user_modelled_crossing_fixes = data.frame(
      watershed_group_code = "BULK",
      modelled_crossing_id = 123L,
      structure = "NONE",
      stringsAsFactors = FALSE
    )
  )

  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbWriteTable = function(...) invisible(NULL),
    .package = "DBI"
  )

  .lnk_pipeline_apply_fixes("mock-conn", aoi = "BULK", loaded = loaded_stub,
                             schema = "working_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "UPDATE working_bulk.crossings")
  expect_match(joined, "SET barrier_status = 'PASSABLE'")
  expect_match(joined, "FROM working_bulk.crossing_fixes")
  expect_match(joined, "structure IN \\('NONE', 'OBS'\\)")
})

test_that(".lnk_pipeline_apply_fixes is a no-op when no fixes match AOI", {
  loaded_stub <- list(
    user_modelled_crossing_fixes = data.frame(
      watershed_group_code = "ADMS",      # different WSG
      modelled_crossing_id = 123L,
      structure = "NONE",
      stringsAsFactors = FALSE
    )
  )

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

  .lnk_pipeline_apply_fixes("mock-conn", aoi = "BULK", loaded = loaded_stub,
                             schema = "working_bulk")

  expect_length(captured, 0L)
})

test_that(".lnk_pipeline_apply_fixes is a no-op when no fixes loaded", {
  loaded_stub <- list()

  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  .lnk_pipeline_apply_fixes("mock-conn", aoi = "BULK", loaded = loaded_stub,
                             schema = "working_bulk")

  expect_length(captured, 0L)
})

# -- apply_pscis branching --------------------------------------------------

test_that(".lnk_pipeline_apply_pscis is a no-op when no PSCIS fixes match", {
  loaded_stub <- list(
    user_pscis_barrier_status = data.frame(
      watershed_group_code = "ADMS",      # different WSG
      stream_crossing_id = 456L,
      user_barrier_status = "BARRIER",
      stringsAsFactors = FALSE
    )
  )

  override_calls <- 0L
  local_mocked_bindings(
    lnk_override = function(...) {
      override_calls <<- override_calls + 1L
      invisible(NULL)
    }
  )

  .lnk_pipeline_apply_pscis("mock-conn", aoi = "BULK", loaded = loaded_stub,
                              schema = "working_bulk")

  expect_equal(override_calls, 0L)
})
