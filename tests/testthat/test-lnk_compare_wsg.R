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

test_that("lnk_compare_wsg with_mapping_code=TRUE errors with Phase 2 message", {
  expect_error(
    lnk_compare_wsg(mock_conn(), aoi = "ADMS",
                    cfg = mock_cfg(), loaded = mock_loaded(),
                    reference = "bcfishpass", conn_ref = mock_conn(),
                    with_mapping_code = TRUE),
    "Phase 2 of link#162"
  )
})

# ---------------------------------------------------------------------------
# Composition: rollup-only path calls pipeline phases in order
# ---------------------------------------------------------------------------

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
