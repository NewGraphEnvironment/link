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
  # Mock DBI::dbGetQuery so the new DDL-drift check sees an empty world
  # (table doesn't exist → no-op, CREATE IF NOT EXISTS handles it).
  cfg <- lnk_config("bcfishpass")
  with_mocked_bindings(
    dbGetQuery = function(conn, sql) data.frame(),  # no rows = no table
    .package = "DBI",
    lnk_persist_init("mock-conn", cfg, species = c("BT", "CH", "SK"))
  )

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "CREATE SCHEMA IF NOT EXISTS fresh")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams")
  expect_match(joined, "PRIMARY KEY \\(id_segment, watershed_group_code\\)")
  expect_match(joined, "geom geometry\\(MultiLineStringZM, 3005\\)")

  # GIST index on geom
  expect_match(joined, "CREATE INDEX IF NOT EXISTS streams_geom_idx ON fresh.streams USING GIST")

  # Per-species tables — one CREATE per species, lowercased
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams_habitat_bt")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams_habitat_ch")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.streams_habitat_sk")

  # Unified barriers table (link#152) — shape + indexes.
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.barriers")
  expect_match(joined, "PRIMARY KEY \\(id_barrier, watershed_group_code\\)")
  expect_match(joined, "id_barrier\\s+text NOT NULL")
  expect_match(joined, "blocks_species text\\[\\]")
  expect_match(joined, "geom geometry\\(Point, 3005\\)")
  expect_match(joined,
               "CREATE INDEX IF NOT EXISTS barriers_blocks_idx ON fresh\\.barriers USING GIN")
  expect_match(joined,
               "CREATE INDEX IF NOT EXISTS barriers_blk_drm_idx ON fresh\\.barriers \\(blue_line_key, downstream_route_measure\\)")
  expect_match(joined,
               "CREATE INDEX IF NOT EXISTS barriers_geom_idx ON fresh\\.barriers USING GIST")
})

test_that("lnk_persist_init errors on invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_persist_init("conn", list(), c("BT")),
               "cfg must be an lnk_config object")
  expect_error(lnk_persist_init("conn", cfg, character(0)),
               "species must be a non-empty character vector")
  expect_error(lnk_persist_init("conn", cfg, c("BT", "")),
               "species must not contain empty strings")
  expect_error(lnk_persist_init("conn", cfg, "BT", force_recreate = "yes"),
               "force_recreate must be a single logical")
})

# ---------------------------------------------------------------------------
# DDL drift detection (Phase 7 hardening, link#162)
# ---------------------------------------------------------------------------

test_that("lnk_persist_init errors loud when target table has unexpected GENERATED columns", {
  local_mocked_bindings(.lnk_db_execute = function(...) invisible(NULL))
  cfg <- lnk_config("bcfishpass")

  # First query: "does the table exist?" returns 1 row (yes)
  # Second query: "any GENERATED columns?" returns row with 'gradient'
  # Subsequent queries (for habitat tables): empty (don't exist)
  call_n <- 0
  mock_q <- function(conn, sql) {
    call_n <<- call_n + 1
    if (grepl("information_schema.tables", sql) &&
        grepl("'streams'", sql) && !grepl("habitat", sql)) {
      return(data.frame(x = 1L))
    }
    if (grepl("information_schema.columns", sql) &&
        grepl("'streams'", sql) && !grepl("habitat", sql)) {
      return(data.frame(column_name = "gradient", stringsAsFactors = FALSE))
    }
    data.frame()  # everything else: no rows
  }

  expect_error(
    with_mocked_bindings(
      dbGetQuery = mock_q, .package = "DBI",
      lnk_persist_init("conn", cfg, species = "BT")
    ),
    "DDL drift in fresh.streams.*gradient"
  )
})

test_that("lnk_persist_init with force_recreate=TRUE DROPs stale-DDL table", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql); invisible(NULL)
    }
  )
  cfg <- lnk_config("bcfishpass")

  # streams exists with bad DDL; habitat tables don't exist
  mock_q <- function(conn, sql) {
    if (grepl("information_schema.tables", sql) &&
        grepl("'streams'", sql) && !grepl("habitat", sql)) {
      return(data.frame(x = 1L))
    }
    if (grepl("information_schema.columns", sql) &&
        grepl("'streams'", sql) && !grepl("habitat", sql)) {
      return(data.frame(column_name = "gradient", stringsAsFactors = FALSE))
    }
    data.frame()
  }

  expect_message(
    with_mocked_bindings(
      dbGetQuery = mock_q, .package = "DBI",
      lnk_persist_init("conn", cfg, species = "BT", force_recreate = TRUE)
    ),
    "DROPping per force_recreate"
  )
  expect_true(any(grepl("DROP TABLE fresh\\.streams CASCADE", captured)))
  # The subsequent CREATE TABLE IF NOT EXISTS should still fire
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS fresh\\.streams", captured)))
})

test_that("lnk_persist_init is silent when existing table has no GENERATED columns", {
  local_mocked_bindings(.lnk_db_execute = function(...) invisible(NULL))
  cfg <- lnk_config("bcfishpass")
  # Tables exist but have no GENERATED columns
  mock_q <- function(conn, sql) {
    if (grepl("information_schema.tables", sql)) return(data.frame(x = 1L))
    if (grepl("information_schema.columns", sql)) return(data.frame())  # no gen cols
    data.frame()
  }
  expect_no_error(
    with_mocked_bindings(
      dbGetQuery = mock_q, .package = "DBI",
      lnk_persist_init("conn", cfg, species = "BT")
    )
  )
})
