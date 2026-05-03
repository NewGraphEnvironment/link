# Tests for lnk_persist_init + .lnk_table_names + .lnk_working_schema

test_that(".lnk_table_names returns expected list shape", {
  cfg <- lnk_config("bcfishpass")
  tn <- .lnk_table_names(cfg)
  expect_type(tn, "list")
  expect_equal(tn$schema, "fresh")
  expect_equal(tn$streams, "fresh.streams")
  expect_type(tn$habitat_for, "closure")
  expect_equal(tn$habitat_for("BT"), "fresh.streams_habitat_bt")
  expect_equal(tn$habitat_for("sk"), "fresh.streams_habitat_sk")
})

test_that(".lnk_table_names errors when cfg is not lnk_config", {
  expect_error(
    .lnk_table_names(list(pipeline = list(schema = "fresh"))),
    "cfg must be an lnk_config object"
  )
})

test_that(".lnk_table_names errors when pipeline.schema missing/empty", {
  cfg_stub <- structure(list(pipeline = list()), class = c("lnk_config", "list"))
  expect_error(.lnk_table_names(cfg_stub),
               "cfg\\$pipeline\\$schema must be a non-empty string")

  cfg_stub2 <- structure(list(pipeline = list(schema = "")), class = c("lnk_config", "list"))
  expect_error(.lnk_table_names(cfg_stub2),
               "cfg\\$pipeline\\$schema must be a non-empty string")

  cfg_stub3 <- structure(list(pipeline = list(schema = NULL)), class = c("lnk_config", "list"))
  expect_error(.lnk_table_names(cfg_stub3),
               "cfg\\$pipeline\\$schema must be a non-empty string")
})

test_that("habitat_for() rejects invalid species", {
  cfg <- lnk_config("bcfishpass")
  tn <- .lnk_table_names(cfg)
  expect_error(tn$habitat_for(""),     "single non-empty species code")
  expect_error(tn$habitat_for(NULL),   "single non-empty species code")
  expect_error(tn$habitat_for(c("BT", "CH")), "single non-empty species code")
})

test_that(".lnk_working_schema constructs working_<wsg>", {
  expect_equal(.lnk_working_schema("LRDO"), "working_lrdo")
  expect_equal(.lnk_working_schema("ADMS"), "working_adms")
  expect_error(.lnk_working_schema(""),  "single non-empty WSG code")
  expect_error(.lnk_working_schema(NULL), "single non-empty WSG code")
})

# -- lnk_persist_init SQL emission ------------------------------------------

test_that("lnk_persist_init creates schema + streams + per-species habitat tables", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")
  lnk_persist_init("mock-conn", cfg, species = c("BT", "CH", "SK"))

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE SCHEMA IF NOT EXISTS fresh")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams")
  expect_match(joined, "PRIMARY KEY \\(id_segment, watershed_group_code\\)")
  expect_match(joined, "geom geometry\\(MultiLineString, 3005\\)")

  # GIST index on geom
  expect_match(joined, "CREATE INDEX IF NOT EXISTS streams_geom_idx ON fresh.streams USING GIST")

  # Per-species tables — one CREATE per species, lowercased
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams_habitat_bt")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams_habitat_ch")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams_habitat_sk")
})

test_that("lnk_persist_init errors on invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_persist_init("conn", list(), c("BT")),
               "cfg must be an lnk_config object")
  expect_error(lnk_persist_init("conn", cfg, character(0)),
               "species must be a non-empty character vector")
  expect_error(lnk_persist_init("conn", cfg, c("BT", "")),
               "species must not contain empty strings")
})
