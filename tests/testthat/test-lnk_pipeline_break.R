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
# Post-link#92 simplification: prep_observations builds <schema>.observations
# with the WSG species-presence + exclusions filters applied. break_obs is now
# a thin reader from that pre-filtered table — no obs_exclusions temp table
# write, no inline species/exclusion SQL.

test_that(".lnk_pipeline_break_obs reads from <schema>.observations (link#92)", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  .lnk_pipeline_break_obs("mock", aoi = "BULK", loaded = list(),
                           schema = "w_bulk",
                           observations = "bcfishobs.observations")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DROP TABLE IF EXISTS w_bulk.observations_breaks")
  expect_match(joined, "CREATE TABLE w_bulk.observations_breaks")
  # Reads from the pre-filtered <schema>.observations table, NOT raw bcfishobs
  expect_match(joined, "FROM w_bulk.observations\\b")
  expect_no_match(joined, "FROM bcfishobs\\.observations")
  # Species filter, watershed_group filter, and exclusions all moved upstream
  # to prep_observations — must not appear in this step's SQL.
  expect_no_match(joined, "watershed_group_code")
  expect_no_match(joined, "species_code IN")
  expect_no_match(joined, "obs_exclusions")
  expect_no_match(joined, "observation_key NOT IN")
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
