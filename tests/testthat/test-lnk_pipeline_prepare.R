# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_prepare rejects invalid aoi", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = NULL, cfg = cfg,
                          loaded = list(), schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "", cfg = cfg,
                          loaded = list(), schema = "w"),
    "aoi must be a single non-empty string"
  )
})

test_that("lnk_pipeline_prepare rejects non-lnk_config cfg", {
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK",
                          cfg = list(), loaded = list(), schema = "w"),
    "cfg must be an lnk_config object"
  )
})

test_that("lnk_pipeline_prepare rejects non-list loaded", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          loaded = "not-a-list", schema = "w"),
    "loaded must be a named list"
  )
})

test_that("lnk_pipeline_prepare rejects invalid schema and observations", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          loaded = list(), schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          loaded = list(), schema = "working",
                          observations = "bad;name"),
    "observations"
  )
})

# -- quote_literal helper ---------------------------------------------------

test_that(".lnk_quote_literal doubles single-quotes", {
  expect_equal(.lnk_quote_literal("BULK"), "'BULK'")
  expect_equal(.lnk_quote_literal("O'Brien"), "'O''Brien'")
  expect_error(.lnk_quote_literal(c("a", "b")), "single string")
  expect_error(.lnk_quote_literal(123), "single string")
})

# -- prep_gradient SQL shape (mocked) ---------------------------------------

.loaded_no_control <- list()
.loaded_with_control <- list(
  user_barriers_definite_control = data.frame(
    blue_line_key = 1L,
    downstream_route_measure = 1,
    barrier_ind = "t",
    watershed_group_code = "ADMS",
    stringsAsFactors = FALSE
  )
)

test_that(".lnk_pipeline_prep_gradient quotes aoi safely in the streams_blk query", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_break_find = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_gradient("mock-conn", aoi = "BULK",
    loaded = .loaded_no_control, schema = "w")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w.streams_blk")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "edge_type != 6010")
  expect_match(joined, "ADD COLUMN IF NOT EXISTS wscode_ltree ltree")
  expect_no_match(joined, "DELETE FROM w.gradient_barriers_raw")
})

test_that(".lnk_pipeline_prep_gradient prunes when manifest declares control", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_break_find = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_gradient("mock-conn", aoi = "ADMS",
    loaded = .loaded_with_control, schema = "w_adms")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DELETE FROM w_adms.gradient_barriers_raw g")
  expect_match(joined, "USING w_adms.barriers_definite_control c")
  expect_match(joined, "c.barrier_ind::boolean = false")
})

# -- prep_natural SQL shape -------------------------------------------------

# Helper: minimal cfg-like object for mocking. The real cfg is built by
# lnk_config(), which reads YAML — too heavy for these unit tests.
.fake_cfg <- function(break_order = NULL) {
  structure(list(pipeline = list(break_order = break_order)),
            class = "lnk_config")
}

test_that(".lnk_pipeline_prep_natural unions gradient + falls when subsurfaceflow opted out", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  cfg <- .fake_cfg(break_order = c("observations", "gradient_minimal",
    "barriers_definite", "habitat_endpoints", "crossings"))
  .lnk_pipeline_prep_natural("mock-conn", aoi = "BULK", cfg = cfg,
    loaded = list(), schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w_bulk.natural_barriers")
  expect_match(joined, "FROM w_bulk.gradient_barriers_raw g")
  expect_match(joined, "FROM w_bulk.falls f")
  expect_no_match(joined, "FROM w_bulk\\.barriers_definite\\b")
  expect_match(joined, "'blocked'")
  # Subsurfaceflow code path must not fire when not opted in
  expect_no_match(joined, "barriers_subsurfaceflow")
  expect_no_match(joined, "edge_type IN \\(1410, 1425\\)")
})

test_that(".lnk_pipeline_prep_natural unions subsurfaceflow into natural_barriers when opted in", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  cfg <- .fake_cfg(break_order = c("observations", "gradient_minimal",
    "barriers_definite", "subsurfaceflow", "habitat_endpoints", "crossings"))
  .lnk_pipeline_prep_natural("mock-conn", aoi = "HARR", cfg = cfg,
    loaded = list(), schema = "w_harr")

  joined <- paste(captured, collapse = "\n")
  # Builds the subsurfaceflow table from FWA
  expect_match(joined, "CREATE TABLE w_harr.barriers_subsurfaceflow")
  expect_match(joined, "edge_type IN \\(1410, 1425\\)")
  # AND appends those positions to natural_barriers so lnk_barrier_overrides
  # sees them — this is the link#88 fix. Match per-statement (not on the
  # newline-joined blob): a single emitted SQL string must contain both the
  # INSERT target and the SELECT source. A cross-statement regex on the
  # joined blob would false-positive on the falls INSERT plus a downstream
  # CREATE TABLE that names barriers_subsurfaceflow.
  has_fix_insert <- any(
    grepl("INSERT INTO w_harr\\.natural_barriers", captured) &
    grepl("FROM w_harr\\.barriers_subsurfaceflow", captured))
  expect_true(has_fix_insert,
    info = "expected one captured SQL with INSERT INTO natural_barriers ... FROM barriers_subsurfaceflow")
})

test_that(".lnk_pipeline_prep_natural honours barriers_definite_control on subsurfaceflow", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  cfg <- .fake_cfg(break_order = c("subsurfaceflow"))
  loaded <- list(user_barriers_definite_control = data.frame(
    blue_line_key = 1L, downstream_route_measure = 0,
    barrier_ind = "true"))
  .lnk_pipeline_prep_natural("mock-conn", aoi = "HARR", cfg = cfg,
    loaded = loaded, schema = "w_harr")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "LEFT OUTER JOIN w_harr.barriers_definite_control c")
  expect_match(joined,
    "c.barrier_ind IS NULL OR c.barrier_ind::boolean IS TRUE")
})

# -- prep_minimal structure --------------------------------------------------

test_that(".lnk_pipeline_prep_minimal builds 4 per-model tables and unions them", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  minimal_calls <- list()
  local_mocked_bindings(
    frs_barriers_minimal = function(conn, from, to, ...) {
      minimal_calls[[length(minimal_calls) + 1]] <<-
        list(from = from, to = to)
      invisible(NULL)
    },
    .package = "fresh"
  )

  .lnk_pipeline_prep_minimal("mock-conn", aoi = "BULK", schema = "w_bulk")

  expect_length(minimal_calls, 4L)
  from_tables <- vapply(minimal_calls, `[[`, character(1), "from")
  table_names <- sub("^[^.]+\\.", "", from_tables)
  expect_setequal(table_names,
    c("barriers_bt", "barriers_ch_cm_co_pk_sk",
      "barriers_st", "barriers_wct"))

  joined <- paste(captured, collapse = "\n")
  expect_match(joined,
    "CREATE TABLE w_bulk.gradient_barriers_minimal AS")
  expect_match(joined, "UNION")
})

# -- prep_network SQL shape --------------------------------------------------

test_that(".lnk_pipeline_prep_network loads fresh.streams with FWA filters", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    frs_col_join = function(...) invisible(NULL),
    frs_col_generate = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_network("mock-conn", aoi = "BULK", schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE fresh.streams")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "localcode_ltree IS NOT NULL")
  expect_match(joined, "edge_type != 6010")
  expect_match(joined, "wscode_ltree <@ '999'::ltree IS FALSE")
  expect_match(joined, "ADD COLUMN id_segment integer")
})

# -- prep_overrides control pass-through (manifest-driven) -------------------

test_that(".lnk_pipeline_prep_overrides passes control when manifest declares it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    user_barriers_definite_control = data.frame(
      blue_line_key = 360873822L,
      downstream_route_measure = 1000,
      barrier_ind = "t",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_equal(captured$args$control, "working_bulk.barriers_definite_control")
})

test_that(".lnk_pipeline_prep_overrides passes control = NULL when manifest omits it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_null(captured$args$control)
})

# -- prep_overrides habitat pass-through (manifest-driven) -------------------

test_that(".lnk_pipeline_prep_overrides passes habitat when manifest declares it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    user_habitat_classification = data.frame(
      blue_line_key = 1L,
      species_code = "BT",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_equal(captured$args$habitat,
    "working_bulk.user_habitat_classification")
})

test_that(".lnk_pipeline_prep_overrides passes habitat = NULL when manifest omits it", {
  loaded_stub <- list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    )
  )

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", loaded = loaded_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_null(captured$args$habitat)
})
