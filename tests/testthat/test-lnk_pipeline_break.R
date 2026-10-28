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

test_that(".lnk_pipeline_break_obs keeps each species' top per line under top_per_species (#396)", {
  sql_for <- function(...) {
    captured <- character(0)
    local_mocked_bindings(
      .lnk_db_execute = function(conn, sql) {
        captured <<- c(captured, sql)
        invisible(NULL)
      }
    )
    .lnk_pipeline_break_obs("mock", aoi = "BULK", loaded = list(),
                            schema = "w_bulk",
                            observations = "bcfishobs.observations", ...)
    paste(captured, collapse = "\n")
  }
  top <- sql_for(mode = "top_per_species")
  expect_match(top, "GROUP BY blue_line_key, species_code", fixed = TRUE)
  expect_match(top, "round(max(downstream_route_measure))", fixed = TRUE)
  expect_match(top, "FROM w_bulk.observations\\b")
  for (sql in list(sql_for(mode = "all"), sql_for())) {
    expect_no_match(sql, "GROUP BY")
    expect_match(sql, "SELECT DISTINCT blue_line_key", fixed = TRUE)
  }
  expect_error(sql_for(mode = "top"), "must be one of all, top_per_species")
})

test_that("lnk_pipeline_break builds observation breaks from the bundle's knob (#396)", {
  mode_for <- function(cfg) {
    got <- NULL
    local_mocked_bindings(
      .lnk_pipeline_break_obs = function(..., mode) got <<- mode,
      .lnk_pipeline_break_habitat_endpoints = function(...) invisible(NULL),
      .lnk_pipeline_break_crossings = function(...) invisible(NULL),
      .lnk_pipeline_break_reassign_id = function(...) invisible(NULL)
    )
    local_mocked_bindings(frs_break_apply = function(...) invisible(NULL),
                          .package = "fresh")
    lnk_pipeline_break("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                       schema = "w_bulk")
    got
  }
  expect_identical(mode_for(lnk_config("default")), "top_per_species")
  expect_identical(mode_for(lnk_config("default_tuned")), "top_per_species")
  expect_identical(mode_for(lnk_config("bcfishpass")), "all")
  stub <- structure(list(name = "x", pipeline = list()),
                    class = c("lnk_config", "list"))
  expect_identical(mode_for(stub), "all")
})

test_that("a bad observation_breaks value fails when the manifest loads (#396)", {
  for (bad in list("TOP_PER_SPECIES", NA_character_, c("all", "all"), 1, "")) {
    pipeline <- list(observation_breaks = bad)
    expect_error(link:::.lnk_config_pipeline_check(pipeline, "x"),
                 "config 'x': observation_breaks must be one of all, top_per_species")
  }
  for (ok in c("all", "top_per_species")) {
    got <- link:::.lnk_config_pipeline_check(list(observation_breaks = ok), "x")
    expect_identical(got, list(observation_breaks = ok))
  }
  d <- withr::local_tempdir()
  writeLines(c("name: badobs", "extends: default",
               "pipeline:", "  observation_breaks: top"),
             file.path(d, "config.yaml"))
  expect_error(lnk_config(d), "config 'badobs': observation_breaks must be")
})

test_that("top_per_species keeps exactly each species' top on a line (live, #396)", {
  skip_if_no_db()
  conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                      user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(conn))
  s <- "zz_test_obs_breaks"
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  drop_sql <- sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s)
  withr::defer(DBI::dbExecute(conn, drop_sql))
  # One line: BT at 100.4 and 520.6 (the lower one is not a top), CO at 300.2;
  # a second line holding only a BT record at 50.
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.observations AS
     SELECT * FROM (VALUES
       (1, 'BT', 100.4::double precision),
       (1, 'BT', 520.6),
       (1, 'CO', 300.2),
       (2, 'BT', 50.0)
     ) v(blue_line_key, species_code, downstream_route_measure)", s))
  read_breaks <- function() {
    DBI::dbGetQuery(conn, sprintf(
      "SELECT blue_line_key, downstream_route_measure
       FROM %s.observations_breaks
       ORDER BY blue_line_key, downstream_route_measure", s))
  }
  .lnk_pipeline_break_obs(conn, "X", list(), s, "bcfishobs.observations",
                          mode = "top_per_species")
  got <- read_breaks()
  expect_identical(as.integer(got$blue_line_key), c(1L, 1L, 2L))
  expect_identical(as.numeric(got$downstream_route_measure), c(300, 521, 50))

  .lnk_pipeline_break_obs(conn, "X", list(), s, "bcfishobs.observations",
                          mode = "all")
  expect_identical(as.numeric(read_breaks()$downstream_route_measure),
                   c(100, 300, 521, 50))
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

test_that("lnk_pipeline_break wires falls into source_tables (link#96)", {
  # Regression for the documented-but-unimplemented break source. Before
  # this fix, falls were loaded into <schema>.falls (used by streams_breaks
  # for access gating + by prep_natural for obs/habitat lift) but were
  # never used as a SEGMENTATION break source. Where two falls sat close
  # together (no other break source between them), the resulting fresh.
  # streams segment spanned across the second fall, leaving its upper
  # portion incorrectly classified as accessible. See HORS BLK 356357296
  # in the link#96 issue body for the evidence trace.
  cfg_stub <- structure(list(
    pipeline = list(break_order = c("falls", "observations"))
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

  # falls table is hit before observations per cfg break_order
  expect_equal(called_tables, c(
    "w_bulk.falls",
    "w_bulk.observations_breaks"
  ))
})

test_that("lnk_pipeline_break default break_order includes falls (link#96)", {
  # When cfg$pipeline$break_order is NULL, the function falls back to a
  # default vector. Falls must appear in that default after gradient_minimal
  # — matches the docstring's documented order: observations →
  # gradient_minimal → falls → barriers_definite → habitat_endpoints →
  # crossings.
  cfg_stub <- structure(list(pipeline = list()), class = c("lnk_config", "list"))
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

  # Default order should hit falls between gradient_minimal and barriers_definite
  expect_true("w_bulk.falls" %in% called_tables)
  gm_pos <- match("w_bulk.gradient_barriers_minimal", called_tables)
  fl_pos <- match("w_bulk.falls", called_tables)
  bd_pos <- match("w_bulk.barriers_definite", called_tables)
  expect_true(gm_pos < fl_pos)
  expect_true(fl_pos < bd_pos)
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
