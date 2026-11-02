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

# The mock overrides above are not a real access rule set, so the phase
# tests name the output with fixed tokens; the refusal test below uses the
# real resolver.
mock_tokens <- function() {
  c(cut = "cut-x", acc = "acc-x", grad = "grad-x", flow = "q-x")
}

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
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens(),
                        .lnk_persist_clear_unmodelled = function(...) invisible(character(0)))
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
  drops <- character()
  m_exec <- function(conn, sql, ...) {
    if (grepl("DROP", sql)) drops <<- c(drops, sql)
    1L
  }

  m_log_fail_called <- FALSE
  m_log_finish_called <- FALSE
  m_log_start <- function(...) {
    list(run_id = "rid", config_hash = "sha256:x", schema = "fresh_test",
         schema_working = "working_adms")
  }
  m_log_finish <- function(...) {
    m_log_finish_called <<- TRUE; invisible(TRUE)
  }
  m_log_fail <- function(...) {
    m_log_fail_called <<- TRUE; invisible(TRUE)
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
    .lnk_log_run_start = m_log_start,
    .lnk_log_run_finish = m_log_finish,
    .lnk_log_run_fail = m_log_fail,
    .lnk_log_config_snapshot = function(...) invisible(TRUE),
    .lnk_log_inputs = function(...) invisible(TRUE),
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

  # A run that dies mid-pipeline must be marked failed, not finished —
  # `date_end` stays NULL so partial state is visible rather than silent.
  expect_true(m_log_fail_called)
  expect_false(m_log_finish_called)

  # persist_init / barriers_unify / persist must NOT have fired
  # when active_species is empty
  expect_false(m_persist_init_called)
  expect_false(m_unify_called)
  expect_false(m_persist_called)
  # A run that stops still drops the province copy prepare built (link#401):
  # wsg_run_one.R keeps its working schema.
  expect_true("DROP TABLE IF EXISTS working_adms.observations_province" %in% drops)
})

test_that("lnk_pipeline_run composes phases in expected order", {
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens(),
                        .lnk_persist_clear_unmodelled = function(...) invisible(character(0)))
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
  m_presence <- function(...) {
    calls <<- c(calls, "presence"); NULL
  }
  m_views <- function(conn, schema, cfg, species, ...) {
    calls <<- c(calls, "barriers_views"); invisible(conn)
  }
  access_args <- NULL
  m_access <- function(conn, ...) {
    access_args <<- list(...)
    calls <<- c(calls, "access"); invisible(conn)
  }
  m_gate <- function(conn, ...) {
    calls <<- c(calls, "habitat_gate"); NULL
  }
  drops <- character()
  m_exec <- function(conn, sql) {
    if (grepl("DROP", sql)) {
      calls <<- c(calls, "exec_drop")
      drops <<- c(drops, sql)
    }
    1L
  }
  m_log_start <- function(...) {
    calls <<- c(calls, "log_start")
    list(run_id = "rid", config_hash = "sha256:x", schema = "fresh_test",
         schema_working = "working_adms")
  }
  m_log_finish <- function(...) {
    calls <<- c(calls, "log_finish"); invisible(TRUE)
  }

  with_mocked_bindings(
    .lnk_log_run_start = m_log_start,
    .lnk_log_run_finish = m_log_finish,
    .lnk_log_run_fail = function(...) invisible(TRUE),
    .lnk_log_config_snapshot = function(...) invisible(TRUE),
    .lnk_log_inputs = function(...) invisible(TRUE),
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
    lnk_presence = m_presence,
    lnk_barriers_views = m_views,
    lnk_pipeline_access = m_access,
    lnk_habitat_gate = m_gate,
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

  # Expected: run-log opened FIRST (link#127 — before anything writes, so
  # wsg_upstream reflects the state the run started from), then the
  # defensive drop, modelling phases, species resolution, persist_init,
  # barriers_unify, then the always-on access phase (link#218):
  # presence -> pre-persist -> barriers_views -> access, then the final
  # persist, the habitat gate on the persisted tables (link#349), and the
  # run-log closed LAST. mapping_code = FALSE here, so the token assembly
  # does NOT run.
  expected_order <- c(
    "log_start",
    "exec_drop",
    "setup", "load", "prepare", "crossings", "break", "species",
    "classify", "connect",
    "persist_init", "barriers_unify",
    "presence", "persist", "barriers_views", "access",
    "persist", "habitat_gate",
    "log_finish",
    "exec_drop"
  )
  expect_equal(calls, expected_order)
  # Code 2 counts every group's records, as bcfishpass's walk does (link#401);
  # the province copy is dropped when the run ends, after the walk read it.
  expect_identical(access_args$observations, "working_adms.observations_province")
  # bcfishpass's reading (the bcfishpass config, observation_upstream absent):
  # another group's record counts only below one of the group's own.
  expect_identical(access_args$observations_gate, "working_adms.observations")
  expect_identical(drops[length(drops)],
                   "DROP TABLE IF EXISTS working_adms.observations_province")
  # Returns conn invisibly
  expect_s3_class(result, "DBIConnection")
})

test_that("a group with only paused species is built with no habitat (#432)", {
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens())
  calls <- character()
  persisted <- list()
  cleared <- list()
  note <- function(x) {
    function(...) {
      calls <<- c(calls, x)
      invisible(NULL)
    }
  }
  m_noop <- function(...) invisible(NULL)
  with_mocked_bindings(
    lnk_pipeline_setup = m_noop, lnk_pipeline_load = m_noop,
    lnk_pipeline_prepare = m_noop, lnk_pipeline_crossings = m_noop,
    lnk_pipeline_break = m_noop,
    lnk_pipeline_classify = note("classify"),
    lnk_pipeline_connect = note("connect"),
    lnk_pipeline_species = function(cfg, loaded, aoi, paused = FALSE) {
      if (paused) "RB" else character(0)
    },
    lnk_persist_init = m_noop, lnk_barriers_unify = m_noop,
    lnk_pipeline_persist = function(conn, aoi, cfg, species, schema) {
      persisted[[length(persisted) + 1L]] <<- species
      invisible(NULL)
    },
    .lnk_persist_clear_unmodelled = function(conn, cfg, aoi, species, schema) {
      cleared[[length(cleared) + 1L]] <<- species
      invisible(NULL)
    },
    lnk_presence = m_noop,
    lnk_barriers_views = m_noop, lnk_pipeline_access = note("access"),
    lnk_habitat_gate = note("gate"),
    .lnk_mapping_code_persist = function(conn, schema, aoi, species, presence) {
      calls <<- c(calls, paste0("mapping_code:", length(species)))
      invisible(NULL)
    },
    with_mocked_bindings(dbExecute = function(...) 1L, .package = "DBI",
      expect_message(
        lnk_pipeline_run(conn = mock_conn(), aoi = "MURT", cfg = mock_cfg(),
                         loaded = mock_loaded(), cleanup_working = FALSE,
                         log = FALSE, mapping_code = TRUE),
        "only paused species present \\(RB\\)")))
  expect_identical(calls, c("access", "mapping_code:0"))
  expect_identical(persisted, list(character(0), character(0)))
  expect_identical(cleared, list(character(0)))
})

test_that("habitat_gate = FALSE skips the gate; it must be one TRUE or FALSE", {
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens(),
                        .lnk_persist_clear_unmodelled = function(...) invisible(character(0)))
  gated <- 0L
  m_noop <- function(...) invisible(NULL)
  run <- function(habitat_gate) {
    with_mocked_bindings(
      lnk_pipeline_setup = m_noop, lnk_pipeline_load = m_noop,
      lnk_pipeline_prepare = m_noop, lnk_pipeline_crossings = m_noop,
      lnk_pipeline_break = m_noop, lnk_pipeline_classify = m_noop,
      lnk_pipeline_connect = m_noop,
      lnk_pipeline_species = function(...) "BT",
      lnk_persist_init = m_noop, lnk_barriers_unify = m_noop,
      lnk_pipeline_persist = m_noop, lnk_presence = m_noop,
      lnk_barriers_views = m_noop, lnk_pipeline_access = m_noop,
      lnk_habitat_gate = function(...) { gated <<- gated + 1L; NULL },
      with_mocked_bindings(dbExecute = function(...) 1L, .package = "DBI",
        lnk_pipeline_run(conn = mock_conn(), aoi = "ADMS", cfg = mock_cfg(),
                         loaded = mock_loaded(), cleanup_working = FALSE,
                         log = FALSE, habitat_gate = habitat_gate)))
  }
  run(FALSE)
  expect_equal(gated, 0L)
  run(TRUE)
  expect_equal(gated, 1L)
  expect_error(run(NA))
  expect_error(run(c(TRUE, TRUE)))
})

test_that("lnk_pipeline_run passes NULL conn_tunnel when dams = FALSE", {
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens(),
                        .lnk_persist_clear_unmodelled = function(...) invisible(character(0)))
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
    lnk_presence = m_noop,
    lnk_barriers_views = m_noop,
    lnk_pipeline_access = m_noop,
    lnk_habitat_gate = m_noop,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          lnk_pipeline_run(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            dams = FALSE, log = FALSE, cleanup_working = FALSE
          )
        }
      )
    }
  )

  expect_null(prepare_args$conn_tunnel)
})

test_that("lnk_pipeline_run drops working schema when cleanup_working = TRUE", {
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens(),
                        .lnk_persist_clear_unmodelled = function(...) invisible(character(0)))
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
    lnk_presence = m_noop,
    lnk_barriers_views = m_noop,
    lnk_pipeline_access = m_noop,
    lnk_habitat_gate = m_noop,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          lnk_pipeline_run(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            cleanup_working = TRUE, log = FALSE
          )
        }
      )
    }
  )

  expect_true(drop_schema_seen)
})

# ---------------------------------------------------------------------------
# Access always runs; mapping_code token assembly is gated (link#218)
# ---------------------------------------------------------------------------

test_that("lnk_pipeline_run builds access for both mapping_code values, gates lnk_mapping_code", {
  local_mocked_bindings(lnk_vocabulary_resolve = function(...) mock_tokens(),
                        .lnk_persist_clear_unmodelled = function(...) invisible(character(0)))
  run_once <- function(mapping_code) {
    seen <- list(access = FALSE, mapping = FALSE)
    m_noop <- function(...) invisible(NULL)
    m_species <- function(...) c("BT")
    m_access <- function(...) {
      seen$access <<- TRUE; invisible(NULL)
    }
    m_mapping <- function(...) {
      seen$mapping <<- TRUE; invisible(NULL)
    }
    m_exec <- function(...) 1L

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
      lnk_presence = m_noop,
      lnk_barriers_views = m_noop,
      lnk_pipeline_access = m_access,
      lnk_habitat_gate = m_noop,
      .lnk_mapping_code_persist = m_mapping,
      {
        with_mocked_bindings(
          dbExecute = m_exec,
          .package = "DBI",
          {
            lnk_pipeline_run(
              conn = mock_conn(), aoi = "ADMS",
              cfg = mock_cfg(), loaded = mock_loaded(),
              mapping_code = mapping_code, cleanup_working = FALSE,
              log = FALSE
            )
          }
        )
      }
    )
    seen
  }

  off <- run_once(FALSE)
  on <- run_once(TRUE)

  # Access builds regardless of the flag.
  expect_true(off$access)
  expect_true(on$access)
  # Token assembly is gated.
  expect_false(off$mapping)
  expect_true(on$mapping)
})


test_that("a config with no vocabulary token is refused before anything runs", {
  cfg <- mock_cfg()
  cfg$pipeline$break_order <- rev(cfg$pipeline$break_order)
  started <- FALSE
  set_up <- FALSE
  with_mocked_bindings(
    .lnk_log_run_start = function(...) started <<- TRUE,
    lnk_pipeline_setup = function(...) set_up <<- TRUE,
    {
      expect_error(
        lnk_pipeline_run(conn = mock_conn(), aoi = "ADMS", cfg = cfg,
                         loaded = lnk_load_overrides(cfg)),
        "no cut token")
    }
  )
  expect_false(started)
  expect_false(set_up)
})
