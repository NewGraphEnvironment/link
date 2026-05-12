# Tests for lnk_compare_wsg — argument validation + pipeline composition

mock_conn <- function() structure(list(), class = "DBIConnection")
mock_cfg <- function() lnk_config("bcfishpass")
mock_loaded <- function() list(
  parameters_fresh = data.frame(
    species_code = c("BT","CH","CM","CO","PK","SK","ST","WCT"),
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

test_that("lnk_compare_wsg rejects invalid aoi", {
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "", cfg = mock_cfg(),
                    loaded = mock_loaded()),
    "aoi"
  )
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = c("ADMS","BULK"), cfg = mock_cfg(),
                    loaded = mock_loaded()),
    "aoi"
  )
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ab", cfg = mock_cfg(),
                    loaded = mock_loaded()),
    "aoi"
  )
})

test_that("lnk_compare_wsg rejects non-lnk_config cfg", {
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS", cfg = list(name = "x"),
                    loaded = mock_loaded()),
    "cfg"
  )
})

test_that("lnk_compare_wsg rejects non-DBI conn", {
  expect_error(
    lnk_compare_wsg(conn = "not-a-conn", aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded()),
    "DBI"
  )
})

# ---------------------------------------------------------------------------
# Reference dispatch
# ---------------------------------------------------------------------------

test_that("lnk_compare_wsg rejects unsupported reference", {
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    reference = "unknown"),
    "Unsupported reference"
  )
})

test_that("lnk_compare_wsg requires conn_ref for reference='bcfishpass'", {
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    reference = "bcfishpass", conn_ref = NULL),
    "conn_ref"
  )
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    reference = "bcfishpass", conn_ref = "not-a-conn"),
    "conn_ref"
  )
})

# ---------------------------------------------------------------------------
# with_mapping_code = TRUE not yet implemented (Phase 2)
# ---------------------------------------------------------------------------

# with_mapping_code = TRUE is now implemented; its composition is
# covered by the "composes mapping_code phases" test below.

# ---------------------------------------------------------------------------
# Schema injection guard
# ---------------------------------------------------------------------------

test_that("lnk_compare_wsg rejects schema with characters outside the SQL identifier whitelist", {
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    schema = "x; DROP SCHEMA public CASCADE; --"),
    "schema"
  )
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    schema = "Working_ADMS"),    # mixed case
    "schema"
  )
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    schema = "1invalid"),        # leading digit
    "schema"
  )
})

# ---------------------------------------------------------------------------
# Composition: rollup-only path calls pipeline phases in order
# ---------------------------------------------------------------------------

test_that("lnk_compare_wsg errors before persist when active_species is empty", {
  m_setup <- function(...) invisible(NULL)
  m_load <- function(...) invisible(NULL)
  m_prepare <- function(...) invisible(NULL)
  m_crossings <- function(...) invisible(NULL)
  m_break <- function(...) invisible(NULL)
  m_classify <- function(...) invisible(NULL)
  m_connect <- function(...) invisible(NULL)
  m_species <- function(...) character(0)  # empty
  m_persist_init_called <- FALSE
  m_persist_init <- function(...) {
    m_persist_init_called <<- TRUE; invisible(NULL)
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
    lnk_pipeline_persist = m_persist,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          expect_error(
            lnk_compare_wsg(
              conn = mock_conn(), aoi = "ADMS",
              cfg = mock_cfg(), loaded = mock_loaded(),
              reference = "bcfishpass", conn_ref = mock_conn()
            ),
            "no active species"
          )
        }
      )
    }
  )

  # persist must not have been called with empty species
  expect_false(m_persist_init_called)
  expect_false(m_persist_called)
})

test_that("lnk_compare_wsg composes pipeline phases in expected order", {
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
    calls <<- c(calls, "species"); c("BT","CH","CO","SK")
  }
  m_persist_init <- function(conn, cfg, species) {
    calls <<- c(calls, "persist_init"); invisible(conn)
  }
  m_persist <- function(conn, aoi, cfg, species, schema) {
    calls <<- c(calls, "persist"); invisible(conn)
  }
  m_rollup_link <- function(...) {
    calls <<- c(calls, "rollup_link")
    list(km = data.frame(species_code = "BT", spawning_km = 10,
                         rearing_km = 20, rearing_stream_km = 15,
                         rearing_lake_centerline_km = 3,
                         rearing_wetland_centerline_km = 2),
         lake_ha = data.frame(species_code = "BT", lake_rearing_ha = 100),
         wetland_ha = data.frame(species_code = "BT", wetland_rearing_ha = 50))
  }
  m_rollup_ref <- function(...) {
    calls <<- c(calls, "rollup_ref")
    data.frame(species_code = "BT", spawning_km = 11, rearing_km = 21,
               rearing_stream_km = 16, rearing_lake_centerline_km = 3,
               rearing_wetland_centerline_km = 2,
               lake_rearing_ha = 105, wetland_rearing_ha = 50)
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
    lnk_pipeline_persist = m_persist,
    .lnk_compare_wsg_rollup_link = m_rollup_link,
    .lnk_compare_wsg_rollup_reference = m_rollup_ref,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          result <- lnk_compare_wsg(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            reference = "bcfishpass", conn_ref = mock_conn(),
            species = "BT", cleanup_working = FALSE
          )
        }
      )
    }
  )

  # Pipeline phases in correct order, before rollup queries.
  expected_order <- c(
    "exec_drop",  # defensive reset
    "setup", "load", "prepare", "crossings", "break", "classify", "connect",
    "species",    # active_species resolution
    "persist_init", "persist",
    "rollup_link", "rollup_ref"
  )
  expect_equal(calls, expected_order)

  # Return shape
  expect_named(result, c("rollup", "mapping_code"))
  expect_null(result$mapping_code)
  expect_s3_class(result$rollup, "tbl_df")
  # 7 habitat types × 1 species
  expect_equal(nrow(result$rollup), 7L)
  expect_setequal(unique(result$rollup$species), "BT")
})

# ---------------------------------------------------------------------------
# Rollup tibble shape + diff_pct computation
# ---------------------------------------------------------------------------

test_that(".lnk_compare_wsg_assemble_rollup produces 7 rows per species + correct diff_pct", {
  link_data <- list(
    km = data.frame(
      species_code = c("BT","CH"),
      spawning_km = c(100, 50),
      rearing_km = c(200, 100),
      rearing_stream_km = c(150, 80),
      rearing_lake_centerline_km = c(30, 10),
      rearing_wetland_centerline_km = c(20, 10),
      stringsAsFactors = FALSE
    ),
    lake_ha = data.frame(species_code = c("BT","CH"),
                         lake_rearing_ha = c(1000, 500),
                         stringsAsFactors = FALSE),
    wetland_ha = data.frame(species_code = c("BT","CH"),
                            wetland_rearing_ha = c(500, 250),
                            stringsAsFactors = FALSE)
  )
  ref_data <- data.frame(
    species_code = c("BT","CH"),
    spawning_km = c(99, 49),                # +1.0% / +2.04%
    rearing_km = c(198, 98),                # +1.0% / +2.04%
    rearing_stream_km = c(148, 79),
    rearing_lake_centerline_km = c(30, 10),  # 0% diff
    rearing_wetland_centerline_km = c(20, 10),  # 0% diff
    lake_rearing_ha = c(1000, 500),         # 0% diff
    wetland_rearing_ha = c(500, 250),       # 0% diff
    stringsAsFactors = FALSE
  )

  out <- link:::.lnk_compare_wsg_assemble_rollup(
    aoi = "TEST", species = c("BT","CH"),
    rollup_link = link_data, rollup_ref = ref_data
  )

  # 7 habitat types × 2 species
  expect_equal(nrow(out), 14L)
  expect_named(out, c("wsg", "species", "habitat_type", "unit",
                       "link_value", "ref_value", "diff_pct"))
  expect_setequal(unique(out$wsg), "TEST")
  expect_setequal(unique(out$species), c("BT", "CH"))

  bt_spawn <- out[out$species == "BT" & out$habitat_type == "spawning", ]
  expect_equal(bt_spawn$link_value, 100)
  expect_equal(bt_spawn$ref_value, 99)
  expect_equal(bt_spawn$diff_pct, 1.0)

  bt_lake <- out[out$species == "BT" & out$habitat_type == "lake_rearing", ]
  expect_equal(bt_lake$link_value, 1000)
  expect_equal(bt_lake$ref_value, 1000)
  expect_equal(bt_lake$diff_pct, 0)
  expect_equal(bt_lake$unit, "ha")
})

test_that(".lnk_compare_wsg_assemble_rollup handles NA ref values (not modelled)", {
  link_data <- list(
    km = data.frame(species_code = "RB", spawning_km = 100, rearing_km = 200,
                    rearing_stream_km = 180,
                    rearing_lake_centerline_km = 15,
                    rearing_wetland_centerline_km = 5,
                    stringsAsFactors = FALSE),
    lake_ha = data.frame(species_code = "RB", lake_rearing_ha = 0,
                         stringsAsFactors = FALSE),
    wetland_ha = data.frame(species_code = "RB", wetland_rearing_ha = 0,
                            stringsAsFactors = FALSE)
  )
  # bcfp doesn't model RB — all-NA ref row
  ref_data <- data.frame(
    species_code = "RB",
    spawning_km = NA_real_,
    rearing_km = NA_real_,
    rearing_stream_km = NA_real_,
    rearing_lake_centerline_km = NA_real_,
    rearing_wetland_centerline_km = NA_real_,
    lake_rearing_ha = NA_real_,
    wetland_rearing_ha = NA_real_,
    stringsAsFactors = FALSE
  )

  out <- link:::.lnk_compare_wsg_assemble_rollup(
    aoi = "TEST", species = "RB",
    rollup_link = link_data, rollup_ref = ref_data
  )

  # All diff_pct should be NA (not 0 — distinguishing "not modelled"
  # from "real zero")
  expect_true(all(is.na(out$diff_pct)))
  expect_true(all(is.na(out$ref_value)))
})

test_that("lnk_compare_wsg composes mapping_code branch when with_mapping_code=TRUE", {
  calls <- character()
  m_phase <- function(name) function(...) {
    calls <<- c(calls, name); invisible(NULL)
  }
  m_species <- function(...) {
    calls <<- c(calls, "species"); c("BT","CH","CO","SK")
  }
  m_persist_init <- function(...) {
    calls <<- c(calls, "persist_init"); invisible(NULL)
  }
  m_unify <- function(...) {
    calls <<- c(calls, "barriers_unify"); invisible(NULL)
  }
  m_persist <- function(...) {
    calls <<- c(calls, "persist"); invisible(NULL)
  }
  m_rollup_link <- function(...) {
    calls <<- c(calls, "rollup_link")
    list(km = data.frame(species_code = "BT", spawning_km = 10,
                         rearing_km = 20, rearing_stream_km = 15,
                         rearing_lake_centerline_km = 3,
                         rearing_wetland_centerline_km = 2),
         lake_ha = data.frame(species_code = "BT", lake_rearing_ha = 100),
         wetland_ha = data.frame(species_code = "BT", wetland_rearing_ha = 50))
  }
  m_rollup_ref <- function(...) {
    calls <<- c(calls, "rollup_ref")
    data.frame(species_code = "BT", spawning_km = 11, rearing_km = 21,
               rearing_stream_km = 16, rearing_lake_centerline_km = 3,
               rearing_wetland_centerline_km = 2,
               lake_rearing_ha = 105, wetland_rearing_ha = 50)
  }
  m_mc <- function(...) {
    calls <<- c(calls, "mapping_code_branch")
    tibble::tibble(
      wsg = "ADMS", species = "BT",
      total_segs = 100L, match_pct = 99.5, n_diffs = 0L,
      top_pattern = NA_character_, top_pattern_count = NA_integer_)
  }
  m_exec <- function(...) 1L

  with_mocked_bindings(
    lnk_pipeline_setup = m_phase("setup"),
    lnk_pipeline_load = m_phase("load"),
    lnk_pipeline_prepare = m_phase("prepare"),
    lnk_pipeline_crossings = m_phase("crossings"),
    lnk_pipeline_break = m_phase("break"),
    lnk_pipeline_classify = m_phase("classify"),
    lnk_pipeline_connect = m_phase("connect"),
    lnk_pipeline_species = m_species,
    lnk_persist_init = m_persist_init,
    lnk_barriers_unify = m_unify,
    lnk_pipeline_persist = m_persist,
    .lnk_compare_wsg_rollup_link = m_rollup_link,
    .lnk_compare_wsg_rollup_reference = m_rollup_ref,
    .lnk_compare_wsg_mapping_code = m_mc,
    {
      with_mocked_bindings(
        dbExecute = m_exec,
        .package = "DBI",
        {
          result <- lnk_compare_wsg(
            conn = mock_conn(), aoi = "ADMS",
            cfg = mock_cfg(), loaded = mock_loaded(),
            reference = "bcfishpass", conn_ref = mock_conn(),
            with_mapping_code = TRUE,
            species = "BT", cleanup_working = FALSE
          )
        }
      )
    }
  )

  # Order check: barriers_unify between persist_init and persist.
  expect_true(which(calls == "barriers_unify") >
              which(calls == "persist_init"))
  expect_true(which(calls == "barriers_unify") <
              which(calls == "persist"))

  # mapping_code_branch fires AFTER rollup queries (additive on the
  # same network state — rollup numbers don't depend on mapping_code
  # output).
  expect_true(which(calls == "mapping_code_branch") >
              which(calls == "rollup_ref"))

  expect_named(result, c("rollup", "mapping_code"))
  expect_s3_class(result$mapping_code, "tbl_df")
  expect_equal(nrow(result$mapping_code), 1L)
  expect_named(result$mapping_code,
               c("wsg", "species", "total_segs", "match_pct",
                 "n_diffs", "top_pattern", "top_pattern_count"))
})

test_that(".lnk_compare_wsg_mapping_code errors for unsupported reference", {
  expect_error(
    link:::.lnk_compare_wsg_mapping_code(
      conn = mock_conn(), conn_ref = mock_conn(),
      aoi = "ADMS", cfg = mock_cfg(), loaded = mock_loaded(),
      schema = "working_adms", reference = "unknown_ref"),
    "currently supports reference = 'bcfishpass' only"
  )
})

test_that(".lnk_compare_wsg_mapping_code_diff computes per-species stats with top_pattern", {
  # 4 segments. Species BT: 1 match, 3 mismatches all with same pattern.
  # Species CH: all 4 match. Species CM: 2 match, 2 different patterns.
  link_mc <- data.frame(
    id_segment = 1:4,
    mapping_code_bt = c("ACCESS;NONE", "ACCESS;NONE", "ACCESS;NONE", "ACCESS;NONE"),
    mapping_code_ch = c("ACCESS;NONE", "ACCESS;NONE", "ACCESS;NONE", "ACCESS;NONE"),
    mapping_code_cm = c("ACCESS;NONE", "ACCESS;NONE", "REAR;NONE", "ACCESS;NONE"),
    blue_line_key = 1:4, downstream_route_measure = c(10, 20, 30, 40),
    length_metre = 100,
    stringsAsFactors = FALSE
  )
  bcfp_mc <- data.frame(
    segmented_stream_id = 1:4,
    mapping_code_bt = c("ACCESS;NONE", "ACCESS;MODELLED", "ACCESS;MODELLED", "ACCESS;MODELLED"),
    mapping_code_ch = c("ACCESS;NONE", "ACCESS;NONE", "ACCESS;NONE", "ACCESS;NONE"),
    mapping_code_cm = c("ACCESS;NONE", "ACCESS;MODELLED", "SPAWN;NONE", "ACCESS;NONE"),
    blue_line_key = 1:4, downstream_route_measure = c(10, 20, 30, 40),
    length_metre = 100,
    stringsAsFactors = FALSE
  )
  m_q <- function(conn, sql) {
    if (grepl("FROM bcfishpass", sql)) bcfp_mc else link_mc
  }
  with_mocked_bindings(
    dbGetQuery = m_q,
    dbQuoteLiteral = function(...) DBI::SQL("'ADMS'"),
    .package = "DBI",
    {
      result <- link:::.lnk_compare_wsg_mapping_code_diff(
        conn = mock_conn(), conn_ref = mock_conn(),
        aoi = "ADMS", schema = "working_adms",
        bcfp_species = c("bt", "ch", "cm")
      )
    }
  )

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3L)
  expect_equal(result$total_segs, c(4L, 4L, 4L))

  bt <- result[result$species == "bt", ]
  expect_equal(bt$n_diffs, 3L)
  expect_equal(bt$match_pct, 25)
  expect_equal(bt$top_pattern, "ACCESS;NONE | ACCESS;MODELLED")
  expect_equal(bt$top_pattern_count, 3L)

  ch <- result[result$species == "ch", ]
  expect_equal(ch$n_diffs, 0L)
  expect_equal(ch$match_pct, 100)
  expect_true(is.na(ch$top_pattern))

  cm <- result[result$species == "cm", ]
  expect_equal(cm$n_diffs, 2L)
  expect_equal(cm$match_pct, 50)
})

test_that(".lnk_compare_wsg_assemble_rollup handles zero ref values (avoid div-by-zero)", {
  link_data <- list(
    km = data.frame(species_code = "BT", spawning_km = 100, rearing_km = 200,
                    rearing_stream_km = 180,
                    rearing_lake_centerline_km = 0,
                    rearing_wetland_centerline_km = 0,
                    stringsAsFactors = FALSE),
    lake_ha = data.frame(species_code = "BT", lake_rearing_ha = 0,
                         stringsAsFactors = FALSE),
    wetland_ha = data.frame(species_code = "BT", wetland_rearing_ha = 0,
                            stringsAsFactors = FALSE)
  )
  ref_data <- data.frame(
    species_code = "BT",
    spawning_km = 100, rearing_km = 200, rearing_stream_km = 180,
    rearing_lake_centerline_km = 0,
    rearing_wetland_centerline_km = 0,
    lake_rearing_ha = 0,
    wetland_rearing_ha = 0,
    stringsAsFactors = FALSE
  )

  out <- link:::.lnk_compare_wsg_assemble_rollup(
    aoi = "TEST", species = "BT",
    rollup_link = link_data, rollup_ref = ref_data
  )
  # ref_value == 0 → diff_pct NA (avoid div-by-zero)
  zero_ref <- out[out$ref_value == 0, ]
  expect_true(all(is.na(zero_ref$diff_pct)))
})
