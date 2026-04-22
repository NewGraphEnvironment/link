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

test_that(".lnk_pipeline_prep_gradient quotes aoi safely in the streams_blk query", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      data.frame()                 # pretend no control table exists
    },
    .package = "DBI"
  )
  # Mock frs_break_find to no-op so we don't need a DB
  local_mocked_bindings(
    frs_break_find = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_gradient("mock-conn", aoi = "BULK", schema = "w")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE TABLE w.streams_blk")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "edge_type != 6010")
  expect_match(joined, "ADD COLUMN IF NOT EXISTS wscode_ltree ltree")
})

test_that(".lnk_pipeline_prep_gradient prunes by control when control table exists", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, sql, ...) {
      # Pretend control table exists
      data.frame(x = 1L)
    },
    .package = "DBI"
  )
  local_mocked_bindings(
    frs_break_find = function(...) invisible(NULL),
    .package = "fresh"
  )

  .lnk_pipeline_prep_gradient("mock-conn", aoi = "ADMS", schema = "w_adms")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DELETE FROM w_adms.gradient_barriers_raw g")
  expect_match(joined, "USING w_adms.barriers_definite_control c")
  expect_match(joined, "c.barrier_ind::boolean = false")
})

# -- prep_natural SQL shape -------------------------------------------------

test_that(".lnk_pipeline_prep_natural unions gradient + falls + definite", {
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
  expect_match(joined, "FROM w_bulk.barriers_definite d")
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
