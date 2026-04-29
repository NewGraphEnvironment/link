# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_break rejects invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_break("mock", aoi = NULL, cfg = cfg, loaded = list(),
                        schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_break("mock", aoi = "BULK", cfg = list(), loaded = list(),
                        schema = "w"),
    "cfg must be an lnk_config object"
  )
  expect_error(
    lnk_pipeline_break("mock", aoi = "BULK", cfg = cfg,
                        loaded = "not-a-list", schema = "w"),
    "loaded must be a named list"
  )
  expect_error(
    lnk_pipeline_break("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                        schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_break("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                        schema = "w", observations = "bad;name"),
    "observations"
  )
})

# -- observation species derivation ------------------------------------------

test_that(".lnk_pipeline_break_obs_species handles missing wsg_species_presence", {
  loaded_stub <- list(wsg_species_presence = NULL)
  expect_equal(.lnk_pipeline_break_obs_species(loaded_stub, "BULK"),
               character(0))
})

test_that(".lnk_pipeline_break_obs_species handles AOI not in table", {
  loaded_stub <- list(wsg_species_presence = data.frame(
    watershed_group_code = "ADMS",
    bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
    pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
    stringsAsFactors = FALSE
  ))
  expect_equal(.lnk_pipeline_break_obs_species(loaded_stub, "BULK"),
               character(0))
})

test_that(".lnk_pipeline_break_obs_species expands CT to CT/CCT/ACT/CT\\RB", {
  loaded_stub <- list(wsg_species_presence = data.frame(
    watershed_group_code = "ELKR",
    bt = "t", ch = "f", cm = "f", co = "f", ct = "t", dv = "f",
    pk = "f", rb = "f", sk = "f", st = "f", wct = "t",
    stringsAsFactors = FALSE
  ))
  out <- .lnk_pipeline_break_obs_species(loaded_stub, "ELKR")
  expect_true("BT" %in% out)
  expect_true("CT" %in% out)
  expect_true("CCT" %in% out)
  expect_true("ACT" %in% out)
  expect_true("CT/RB" %in% out)
  expect_true("WCT" %in% out)
  expect_false("CH" %in% out)
})

# -- break_obs SQL shape -----------------------------------------------------

test_that(".lnk_pipeline_break_obs writes AOI-scoped observations_breaks", {
  loaded_stub <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "BULK",
      bt = "t", ch = "t", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = NULL
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

  .lnk_pipeline_break_obs("mock", aoi = "BULK", loaded = loaded_stub,
                           schema = "w_bulk",
                           observations = "bcfishobs.observations")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w_bulk.observations_breaks")
  expect_match(joined, "FROM bcfishobs.observations o")
  expect_match(joined, "o.watershed_group_code = 'BULK'")
  expect_match(joined, "'BT', 'CH'")
  expect_no_match(joined, "obs_exclusions")
})

test_that(".lnk_pipeline_break_obs applies exclusions when present", {
  loaded_stub <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "BULK",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = data.frame(
      fish_observation_point_id = c(1L, 2L, 3L),
      data_error = c(TRUE, FALSE, FALSE),
      release_exclude = c(FALSE, TRUE, FALSE),
      stringsAsFactors = FALSE
    )
  )

  captured <- character(0)
  written <- list()
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbWriteTable = function(conn, name, value, ...) {
      written[[length(written) + 1]] <<- list(name = name, value = value)
      invisible(NULL)
    },
    .package = "DBI"
  )

  .lnk_pipeline_break_obs("mock", aoi = "BULK", loaded = loaded_stub,
                           schema = "w_bulk",
                           observations = "bcfishobs.observations")

  expect_length(written, 1L)
  expect_equal(nrow(written[[1]]$value), 2L)
  expect_setequal(written[[1]]$value$fish_observation_point_id, c(1L, 2L))

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "NOT IN\\s*\\(SELECT fish_observation_point_id FROM w_bulk.obs_exclusions\\)")
})

# -- habitat endpoints -------------------------------------------------------

test_that(".lnk_pipeline_break_habitat_endpoints creates empty table when habitat missing", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) data.frame(),
    .package = "DBI"
  )

  .lnk_pipeline_break_habitat_endpoints("mock",
    aoi = "BULK", schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w_bulk.habitat_endpoints")
  expect_no_match(joined, "SELECT DISTINCT")
})

test_that(".lnk_pipeline_break_habitat_endpoints unions DRM + URM when habitat exists", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) data.frame(x = 1L),
    .package = "DBI"
  )

  .lnk_pipeline_break_habitat_endpoints("mock",
    aoi = "BULK", schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "downstream_route_measure")
  expect_match(joined, "upstream_route_measure")
  expect_match(joined, "UNION")
})

# -- sequential break order --------------------------------------------------

test_that("lnk_pipeline_break honors the config break_order", {
  cfg_stub <- structure(list(
    pipeline = list(break_order = c("crossings", "observations"))
  ), class = c("lnk_config", "list"))
  loaded_stub <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "BULK",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = NULL
  )

  called_tables <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) invisible(NULL)
  )
  local_mocked_bindings(
    dbWriteTable = function(...) invisible(NULL),
    dbGetQuery = function(conn, sql, ...) data.frame(),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_break_apply = function(conn, table, breaks, ...) {
      called_tables <<- c(called_tables, breaks)
      invisible(NULL)
    },
    .package = "fresh"
  )

  lnk_pipeline_break("mock", aoi = "BULK", cfg = cfg_stub,
                      loaded = loaded_stub, schema = "w_bulk",
                      observations = "bcfishobs.observations")

  expect_equal(called_tables, c(
    "w_bulk.crossings_breaks",
    "w_bulk.observations_breaks"
  ))
})

test_that("lnk_pipeline_break errors on unknown break source name", {
  cfg_stub <- structure(list(
    pipeline = list(break_order = c("observations", "what_is_this"))
  ), class = c("lnk_config", "list"))
  loaded_stub <- list(
    wsg_species_presence = data.frame(
      watershed_group_code = "BULK",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    ),
    observation_exclusions = NULL
  )

  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) invisible(NULL)
  )
  local_mocked_bindings(
    dbWriteTable = function(...) invisible(NULL),
    dbGetQuery = function(conn, sql, ...) data.frame(),
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_break_apply = function(...) invisible(NULL),
    .package = "fresh"
  )

  expect_error(
    lnk_pipeline_break("mock", aoi = "BULK", cfg = cfg_stub,
                        loaded = loaded_stub, schema = "w_bulk",
                        observations = "bcfishobs.observations"),
    "Unknown break source.*what_is_this"
  )
})
