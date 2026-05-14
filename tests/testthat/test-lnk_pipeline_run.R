# Tests for lnk_pipeline_run — argument validation + phase composition

mock_conn <- function() structure(list(), class = "DBIConnection")
mock_cfg <- function() lnk_config("bcfishpass")
mock_loaded <- function() list(
  parameters_fresh = data.frame(
    species_code = c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT"),
    access_gradient_max = c(0.25, 0.15, 0.15, 0.15, 0.15, 0.15, 0.20, 0.20),
    stringsAsFactors = FALSE
  ),
  wsg_species_presence = data.frame(
    watershed_group_code = "ADMS",
    bt = "t", ch = "t", cm = "", co = "t", pk = "", sk = "t",
    st = "", wct = "", ct = "", dv = "", rb = "",
    stringsAsFactors = FALSE
  )
)

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

test_that("lnk_pipeline_run rejects invalid aoi", {
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = "", cfg = mock_cfg(),
                     loaded = mock_loaded()),
    "aoi"
  )
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = c("ADMS", "BULK"), cfg = mock_cfg(),
                     loaded = mock_loaded()),
    "aoi"
  )
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = "ab", cfg = mock_cfg(),
                     loaded = mock_loaded()),
    "aoi"
  )
})

test_that("lnk_pipeline_run rejects non-lnk_config cfg", {
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = "ADMS", cfg = list(name = "x"),
                     loaded = mock_loaded()),
    "cfg"
  )
})

test_that("lnk_pipeline_run rejects non-DBI conn", {
  expect_error(
    lnk_pipeline_run(conn = "not-a-conn", aoi = "ADMS",
                     cfg = mock_cfg(), loaded = mock_loaded()),
    "DBI"
  )
})

test_that("lnk_pipeline_run rejects schema with characters outside the SQL identifier whitelist", {
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = "ADMS",
                     cfg = mock_cfg(), loaded = mock_loaded(),
                     schema = "x; DROP SCHEMA public CASCADE; --"),
    "schema"
  )
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = "ADMS",
                     cfg = mock_cfg(), loaded = mock_loaded(),
                     schema = "Working_ADMS"),       # mixed case
    "schema"
  )
  expect_error(
    lnk_pipeline_run(mock_conn(), aoi = "ADMS",
                     cfg = mock_cfg(), loaded = mock_loaded(),
                     schema = "1invalid"),           # leading digit
    "schema"
  )
})

# ---------------------------------------------------------------------------
# Composition: phases called in expected order, persist follows barriers_unify
# ---------------------------------------------------------------------------

test_that("lnk_pipeline_run errors before persist when active_species is empty", {
  m_setup <- function(...) invisible(NULL)
  m_load <- function(...) invisible(NULL)
  m_prepare <- function(...) invisible(NULL)
  m_crossings <- function(...) invisible(NULL)
  m_break <- function(...) invisible(NULL)
  m_classify <- function(...) invisible(NULL)
  m_connect <- function(...) invisible(NULL)
  m_species <- function(...) character(0)            # empty
  m_persist_init_called <- FALSE
  m_persist_init <- function(...) {
    m_persist_init_called <<- TRUE; invisible(NULL)
  }
  m_unify_called <- FALSE
  m_unify <- function(...) {
    m_unify_called <<- TRUE; invisible(NULL)
  }
  m_persist_called <- FALSE
  m_persist <- function(...) {
    m_persist_called <<- TRUE; invisible(NULL)
  }
  m_exec <- function(...) 1L

  with_mocked_bindings(
    lnk_pipeline_setup = m_setup,
    lnk_pipeline_load = m_load,
    lnk_pipeline_prepare = m_prepare,
    lnk_pipeline_crossings = m_crossings,
    lnk_pipeline_break = m_break,
    lnk_pipeline_classify = m_classify,
    lnk_pipeline_connect = m_connect,
    lnk_pipeline_species = m_species,
    lnk_persist_init = m_persist_init,
    lnk_barriers_unify = m_unify,
    lnk_pipeline_persist = m_persist,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          expect_error(
            lnk_pipeline_run(
              conn = mock_conn(), aoi = "ADMS",
              cfg = mock_cfg(), loaded = mock_loaded()
            ),
            "no active species"
          )
        }
      )
    }
  )

  # persist_init / barriers_unify / persist must NOT have fired
  # when active_species is empty
  expect_false(m_persist_init_called)
  expect_false(m_unify_called)
  expect_false(m_persist_called)
})

test_that("lnk_pipeline_run composes phases in expected order", {
  calls <- character()
  m_setup <- function(conn, schema, overwrite) {
    calls <<- c(calls, "setup"); invisible(conn)
  }
  m_load <- function(conn, aoi, cfg, loaded, schema) {
    calls <<- c(calls, "load"); invisible(conn)
  }
  m_prepare <- function(conn, aoi, cfg, loaded, schema, conn_tunnel = NULL,
                        ...) {
    calls <<- c(calls, "prepare"); invisible(conn)
  }
  m_crossings <- function(conn, aoi, cfg, loaded, schema, ...) {
    calls <<- c(calls, "crossings"); invisible(conn)
  }
  m_break <- function(conn, aoi, cfg, loaded, schema, ...) {
    calls <<- c(calls, "break"); invisible(conn)
  }
  m_classify <- function(conn, aoi, cfg, loaded, schema, ...) {
    calls <<- c(calls, "classify"); invisible(conn)
  }
  m_connect <- function(conn, aoi, cfg, loaded, schema, ...) {
    calls <<- c(calls, "connect"); invisible(conn)
  }
  m_species <- function(cfg, loaded, aoi) {
    calls <<- c(calls, "species"); c("BT", "CH", "CO", "SK")
  }
  m_persist_init <- function(conn, cfg, species) {
    calls <<- c(calls, "persist_init"); invisible(conn)
  }
  m_unify <- function(conn, aoi, cfg, loaded, schema, ...) {
    calls <<- c(calls, "barriers_unify"); invisible(conn)
  }
  m_persist <- function(conn, aoi, cfg, species, schema) {
    calls <<- c(calls, "persist"); invisible(conn)
  }
  m_exec <- function(conn, sql) {
    if (grepl("DROP", sql)) calls <<- c(calls, "exec_drop")
    1L
  }

  with_mocked_bindings(
    lnk_pipeline_setup = m_setup,
    lnk_pipeline_load = m_load,
    lnk_pipeline_prepare = m_prepare,
    lnk_pipeline_crossings = m_crossings,
    lnk_pipeline_break = m_break,
    lnk_pipeline_classify = m_classify,
    lnk_pipeline_connect = m_connect,
    lnk_pipeline_species = m_species,
    lnk_persist_init = m_persist_init,
    lnk_barriers_unify = m_unify,
    lnk_pipeline_persist = m_persist,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          result <- lnk_pipeline_run(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            cleanup_working = FALSE
          )
        }
      )
    }
  )

  # Expected: defensive drop, then phases in order, then species
  # resolution, then persist_init, then barriers_unify, then persist.
  expected_order <- c(
    "exec_drop",
    "setup", "load", "prepare", "crossings", "break", "classify", "connect",
    "species",
    "persist_init", "barriers_unify", "persist"
  )
  expect_equal(calls, expected_order)
  # Returns conn invisibly
  expect_s3_class(result, "DBIConnection")
})

test_that("lnk_pipeline_run passes NULL conn_tunnel when dams = FALSE", {
  prepare_args <- list()
  m_noop <- function(...) invisible(NULL)
  m_prepare <- function(conn, aoi, cfg, loaded, schema, conn_tunnel = NULL,
                        ...) {
    prepare_args <<- list(conn_tunnel = conn_tunnel); invisible(conn)
  }
  m_species <- function(...) c("BT")
  m_exec <- function(...) 1L

  with_mocked_bindings(
    lnk_pipeline_setup = m_noop,
    lnk_pipeline_load = m_noop,
    lnk_pipeline_prepare = m_prepare,
    lnk_pipeline_crossings = m_noop,
    lnk_pipeline_break = m_noop,
    lnk_pipeline_classify = m_noop,
    lnk_pipeline_connect = m_noop,
    lnk_pipeline_species = m_species,
    lnk_persist_init = m_noop,
    lnk_barriers_unify = m_noop,
    lnk_pipeline_persist = m_noop,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          lnk_pipeline_run(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            dams = FALSE, cleanup_working = FALSE
          )
        }
      )
    }
  )

  expect_null(prepare_args$conn_tunnel)
})

test_that("lnk_pipeline_run drops working schema when cleanup_working = TRUE", {
  drop_schema_seen <- FALSE
  m_noop <- function(...) invisible(NULL)
  m_species <- function(...) c("BT")
  m_exec <- function(conn, sql) {
    if (grepl("DROP SCHEMA", sql)) drop_schema_seen <<- TRUE
    1L
  }

  with_mocked_bindings(
    lnk_pipeline_setup = m_noop,
    lnk_pipeline_load = m_noop,
    lnk_pipeline_prepare = m_noop,
    lnk_pipeline_crossings = m_noop,
    lnk_pipeline_break = m_noop,
    lnk_pipeline_classify = m_noop,
    lnk_pipeline_connect = m_noop,
    lnk_pipeline_species = m_species,
    lnk_persist_init = m_noop,
    lnk_barriers_unify = m_noop,
    lnk_pipeline_persist = m_noop,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          lnk_pipeline_run(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            cleanup_working = TRUE
          )
        }
      )
    }
  )

  expect_true(drop_schema_seen)
})
