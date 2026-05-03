# Tests for lnk_pipeline_persist — SQL emission shape (mocked DB)

test_that("lnk_pipeline_persist emits DELETE+INSERT for streams + each species", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_pipeline_persist("mock-conn", aoi = "LRDO", cfg = cfg,
    species = c("BT", "SK"))

  joined <- paste(captured, collapse = "\n")

  # streams: DELETE + INSERT pair, scoped to LRDO
  expect_match(joined, "DELETE FROM fresh\\.streams WHERE watershed_group_code = 'LRDO'")
  expect_match(joined, "INSERT INTO fresh\\.streams \\(.*id_segment.*watershed_group_code.*geom.*\\)")
  expect_match(joined, "FROM working_lrdo\\.streams")

  # streams_habitat_<sp>: one DELETE+INSERT pair per species (lowercased)
  expect_match(joined, "DELETE FROM fresh\\.streams_habitat_bt WHERE watershed_group_code = 'LRDO'")
  expect_match(joined, "DELETE FROM fresh\\.streams_habitat_sk WHERE watershed_group_code = 'LRDO'")
  expect_match(joined, "INSERT INTO fresh\\.streams_habitat_bt")
  expect_match(joined, "INSERT INTO fresh\\.streams_habitat_sk")

  # Long->wide pivot: per-species INSERT filters working_<aoi>.streams_habitat
  # by species_code, and projects only cols_habitat (no species_code in SELECT)
  expect_match(joined,
    "INSERT INTO fresh\\.streams_habitat_bt \\(id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing\\)\\s+SELECT id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing FROM working_lrdo\\.streams_habitat WHERE species_code = 'BT'")
})

test_that("lnk_pipeline_persist counts: 2 streams ops + 2 ops per species", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_pipeline_persist("mock-conn", aoi = "ADMS", cfg = cfg,
    species = c("BT", "CH", "SK"))

  # 2 (streams DELETE+INSERT) + 2 * 3 (per-species DELETE+INSERT) = 8
  expect_equal(length(captured), 8L)
})

test_that("lnk_pipeline_persist input validation", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_pipeline_persist("c", aoi = "", cfg = cfg, species = "BT"),
               "aoi must be a single non-empty WSG code")
  expect_error(lnk_pipeline_persist("c", aoi = "LRDO", cfg = list(), species = "BT"),
               "cfg must be an lnk_config object")
  expect_error(lnk_pipeline_persist("c", aoi = "LRDO", cfg = cfg, species = character(0)),
               "species must be a non-empty character vector")
})

test_that("lnk_pipeline_persist accepts non-default schema", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_pipeline_persist("mock-conn", aoi = "LRDO", cfg = cfg,
    species = "BT", schema = "working_custom")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "FROM working_custom\\.streams")
  expect_match(joined, "FROM working_custom\\.streams_habitat WHERE species_code = 'BT'")
})
