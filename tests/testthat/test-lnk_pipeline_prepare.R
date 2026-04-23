# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_prepare rejects invalid aoi", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = NULL, cfg = cfg, schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "", cfg = cfg, schema = "w"),
    "aoi must be a single non-empty string"
  )
})

test_that("lnk_pipeline_prepare rejects non-lnk_config cfg", {
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK",
                          cfg = list(), schema = "w"),
    "cfg must be an lnk_config object"
  )
})

test_that("lnk_pipeline_prepare rejects invalid schema and observations", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_prepare("mock-conn", aoi = "BULK", cfg = cfg,
                          schema = "working",
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

.cfg_no_control <- structure(list(overrides = list()),
  class = c("lnk_config", "list"))
.cfg_with_control <- structure(list(
  overrides = list(
    barriers_definite_control = data.frame(
      blue_line_key = 1L,
      downstream_route_measure = 1,
      barrier_ind = "t",
      watershed_group_code = "ADMS",
      stringsAsFactors = FALSE
    )
  )
), class = c("lnk_config", "list"))

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
    cfg = .cfg_no_control, schema = "w")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w.streams_blk")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "edge_type != 6010")
  expect_match(joined, "ADD COLUMN IF NOT EXISTS wscode_ltree ltree")
  # Without the manifest key, no control-prune DELETE is emitted.
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
    cfg = .cfg_with_control, schema = "w_adms")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DELETE FROM w_adms.gradient_barriers_raw g")
  expect_match(joined, "USING w_adms.barriers_definite_control c")
  expect_match(joined, "c.barrier_ind::boolean = false")
})

# -- prep_natural SQL shape -------------------------------------------------

test_that(".lnk_pipeline_prep_natural unions gradient + falls only (no definite)", {
  # barriers_definite is intentionally NOT unioned into natural_barriers —
  # bcfishpass appends user-definite post-filter in each model_access_*.sql,
  # so observations/habitat never override them. lnk_pipeline_break handles
  # them as a separate break source; lnk_pipeline_classify emits them into
  # fresh.streams_breaks directly.
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_natural("mock-conn", schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w_bulk.natural_barriers")
  expect_match(joined, "FROM w_bulk.gradient_barriers_raw g")
  expect_match(joined, "FROM w_bulk.falls f")
  expect_no_match(joined, "FROM w_bulk\\.barriers_definite\\b")
  expect_match(joined, "'blocked'")
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

  # Four per-model reductions
  expect_length(minimal_calls, 4L)
  from_tables <- vapply(minimal_calls, `[[`, character(1), "from")
  table_names <- sub("^[^.]+\\.", "", from_tables)
  expect_setequal(table_names,
    c("barriers_bt", "barriers_ch_cm_co_pk_sk",
      "barriers_st", "barriers_wct"))

  # Union step creates gradient_barriers_minimal
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
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    overrides = list(
      barriers_definite_control = data.frame(
        blue_line_key = 360873822L,
        downstream_route_measure = 1000,
        barrier_ind = "t",
        stringsAsFactors = FALSE
      )
    )
  ), class = c("lnk_config", "list"))

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", cfg = cfg_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_equal(captured$args$control, "working_bulk.barriers_definite_control")
})

test_that(".lnk_pipeline_prep_overrides passes control = NULL when manifest omits it", {
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    overrides = list()                # no barriers_definite_control key
  ), class = c("lnk_config", "list"))

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", cfg = cfg_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_null(captured$args$control)
})

# -- prep_overrides habitat pass-through (manifest-driven) -------------------

test_that(".lnk_pipeline_prep_overrides passes habitat when manifest declares it", {
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    overrides = list(),
    habitat_classification = data.frame(
      blue_line_key = 1L,
      species_code = "BT",
      stringsAsFactors = FALSE
    )
  ), class = c("lnk_config", "list"))

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", cfg = cfg_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_equal(captured$args$habitat,
    "working_bulk.user_habitat_classification")
})

test_that(".lnk_pipeline_prep_overrides passes habitat = NULL when manifest omits it", {
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(
      species_code = "BT",
      observation_threshold = 1L,
      observation_date_min = "2000-01-01",
      observation_buffer_m = 20,
      observation_species = "BT",
      stringsAsFactors = FALSE
    ),
    overrides = list()
  ), class = c("lnk_config", "list"))

  captured <- list()
  local_mocked_bindings(
    lnk_barrier_overrides = function(conn, ...) {
      captured[["args"]] <<- list(...)
      invisible(NULL)
    }
  )

  .lnk_pipeline_prep_overrides("mock-conn", cfg = cfg_stub,
    schema = "working_bulk", observations = "bcfishobs.observations")

  expect_null(captured$args$habitat)
})
