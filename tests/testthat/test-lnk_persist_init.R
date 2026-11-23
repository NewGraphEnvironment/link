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

  # Province-wide barrier-overrides table (link#200) — shape + indexes.
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh\\.barrier_overrides")
  expect_match(joined,
               "PRIMARY KEY \\(blue_line_key, downstream_route_measure, species_code, watershed_group_code\\)")
  expect_match(joined,
               "CREATE INDEX IF NOT EXISTS barrier_overrides_blk_drm_idx ON fresh\\.barrier_overrides \\(blue_line_key, downstream_route_measure\\)")
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


# -- No lock for DDL that is already done (link#369) -------------------------
# The driver consolidates a cloud host while the dispatcher models, so a
# consolidate's COPY can hold a write on a persist table when the next group's
# lnk_persist_init runs. CREATE INDEX IF NOT EXISTS and ALTER TABLE ADD COLUMN
# IF NOT EXISTS lock their table before they find the work done, so the no-op
# waited for that write.

test_that("an index or column that already exists is not re-issued", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  expect_false(.lnk_index_create("c", have = "a_idx", "a_idx", "s.t (x)"))
  expect_true(.lnk_index_create("c", have = "a_idx", "b_idx", "s.t (y)"))
  expect_identical(captured, "CREATE INDEX IF NOT EXISTS b_idx ON s.t (y)")

  captured <- character(0)
  .lnk_log_align_columns("c", "s", "log", c(a = "text", b = "integer NOT NULL"),
                         have = "a")
  expect_identical(captured, "ALTER TABLE s.log ADD COLUMN IF NOT EXISTS b integer")
})

test_that("an unreadable catalog names nothing, so every statement is issued", {
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) stop("no catalog"),
    .package = "DBI"
  )
  expect_identical(.lnk_schema_indexes("c", "s"), character(0))
  expect_identical(nrow(.lnk_schema_columns("c", "s")), 0L)
})

test_that("an up-to-date persist schema waits on no other session's write (#369)", {
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if_not(identical(info$host, "localhost") && identical(info$dbname, "fwapg"),
              "needs the local docker fwapg")
  schema <- paste0("zz_test369_", Sys.getpid())
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- schema
  sp <- c("BT", "CH")
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  suppressMessages(lnk_persist_init(conn, cfg, species = sp))

  # A second session holds what a consolidate's COPY holds, on every table it
  # writes.
  holder <- DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg",
    host = "localhost", port = 5432L, user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(holder))
  tbls <- c("streams", paste0("streams_habitat_", tolower(sp)), "barriers",
            "barrier_overrides", "barrier_override_evidence", "streams_access",
            "streams_mapping_code", "streams_near_river", "log", "log_input",
            "log_recompute")
  DBI::dbExecute(holder, "BEGIN")
  for (t in tbls) {
    DBI::dbExecute(holder, sprintf("LOCK TABLE %s.%s IN ROW EXCLUSIVE MODE", schema, t))
  }
  withr::defer(DBI::dbExecute(holder, "ROLLBACK"), priority = "first")
  DBI::dbExecute(conn, "SET lock_timeout = '2s'")
  withr::defer(DBI::dbExecute(conn, "RESET lock_timeout"), priority = "first")

  expect_no_error(suppressMessages(lnk_persist_init(conn, cfg, species = sp)))

  # The premise: with the catalog reads disabled, the same init waits on the
  # held write and times out. Without it the expectation above is vacuous.
  local_mocked_bindings(
    .lnk_schema_indexes = function(conn, schema) character(0),
    .lnk_schema_columns = function(conn, schema)
      data.frame(table_name = character(0), column_name = character(0))
  )
  expect_error(suppressMessages(lnk_persist_init(conn, cfg, species = sp)),
               "lock timeout")
})

test_that("an up-to-date long-form habitat view is not replaced under its readers (#374)", {
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if_not(identical(info$host, "localhost") && identical(info$dbname, "fwapg"),
              "needs the local docker fwapg")
  schema <- paste0("zz_test374_", Sys.getpid())
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- schema
  sp <- c("BT", "CH")
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  suppressMessages(lnk_persist_init(conn, cfg, species = sp))
  key <- .lnk_view_state(conn, schema, "streams_habitat_long_vw")$description
  expect_match(key, "^lnk_def:[0-9a-f]{32}:[0-9a-f]{32}$")

  # A second session reads the view, as a recompute job does mid-pool.
  holder <- DBI::dbConnect(RPostgres::Postgres(),
                           dbname = "fwapg", host = "localhost", port = 5432L,
                           user = "postgres", password = "postgres")
  withr::defer(DBI::dbDisconnect(holder))
  DBI::dbExecute(holder, "BEGIN")
  DBI::dbGetQuery(holder, sprintf("SELECT count(*) FROM %s.streams_habitat_long_vw", schema))
  withr::defer(DBI::dbExecute(holder, "ROLLBACK"), priority = "first")
  DBI::dbExecute(conn, "SET lock_timeout = '2s'")
  withr::defer(DBI::dbExecute(conn, "RESET lock_timeout"), priority = "first")

  expect_no_error(suppressMessages(lnk_persist_init(conn, cfg, species = sp)))
  expect_identical(.lnk_view_state(conn, schema, "streams_habitat_long_vw")$description, key)

  # The premise: with no key to compare, the same init replaces the view, waits
  # on the reader and times out. Without it the expectation above is vacuous.
  local_mocked_bindings(.lnk_view_state = function(conn, schema, name) {
    data.frame(description = character(0), def = character(0))
  })
  expect_error(suppressMessages(lnk_persist_init(conn, cfg, species = sp)),
               "lock timeout")
})

test_that("a changed species set replaces the long-form view", {
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if_not(identical(info$host, "localhost") && identical(info$dbname, "fwapg"),
              "needs the local docker fwapg")
  schema <- paste0("zz_test374b_", Sys.getpid())
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- schema
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  suppressMessages(lnk_persist_init(conn, cfg, species = "BT"))
  k1 <- .lnk_view_state(conn, schema, "streams_habitat_long_vw")$description
  suppressMessages(lnk_persist_init(conn, cfg, species = c("BT", "CH")))
  k2 <- .lnk_view_state(conn, schema, "streams_habitat_long_vw")$description
  expect_false(identical(k1, k2))
  sp <- DBI::dbGetQuery(conn, sprintf("SELECT DISTINCT species_code FROM %s.streams_habitat_long_vw",
                                      schema))
  expect_identical(nrow(sp), 0L)
  q_def <- sprintf("SELECT pg_get_viewdef('%s.streams_habitat_long_vw'::regclass) d", schema)
  def <- DBI::dbGetQuery(conn, q_def)$d
  expect_match(def, "streams_habitat_ch")
})

test_that("a replace by another writer that leaves the comment is noticed", {
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if_not(identical(info$host, "localhost") && identical(info$dbname, "fwapg"),
              "needs the local docker fwapg")
  schema <- paste0("zz_test374c_", Sys.getpid())
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- schema
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  suppressMessages(lnk_persist_init(conn, cfg, species = c("BT", "CH")))
  # An older checkout replaces the view with one species; the comment stays.
  older <- sprintf(
    "CREATE OR REPLACE VIEW %1$s.streams_habitat_long_vw AS
     SELECT id_segment, watershed_group_code, 'bt'::text AS species_code, spawning, rearing
     FROM %1$s.streams_habitat_bt",
    schema
  )
  DBI::dbExecute(conn, older)
  expect_match(.lnk_view_state(conn, schema, "streams_habitat_long_vw")$description, "^lnk_def:")
  suppressMessages(lnk_persist_init(conn, cfg, species = c("BT", "CH")))
  def <- .lnk_view_state(conn, schema, "streams_habitat_long_vw")$def
  expect_match(def, "streams_habitat_ch")
})

# fresh 0.54.0 keys its near-river table on linear_feature_id (#452), and a
# table persisted before then gains the column once.
test_that("a near-river table without linear_feature_id is migrated, once", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(3L)
    },
    .lnk_db_transaction = function(conn, code) code
  )
  cols <- function(...) {
    nm <- c(...)
    function(conn, schema) {
      data.frame(table_name = rep("streams_near_river", length(nm)),
                 column_name = nm)
    }
  }
  old <- c("id_segment", "watershed_group_code", "measure", "threshold",
           "distance_max", "dist_m")

  local_mocked_bindings(.lnk_schema_columns = cols(old))
  expect_identical(.lnk_near_river_lfid_migrate("c", "s"), 3L)
  expect_identical(captured[1],
    "ALTER TABLE s.streams_near_river ADD COLUMN IF NOT EXISTS linear_feature_id bigint")
  expect_match(captured[2], "UPDATE s\\.streams_near_river nr")
  expect_match(captured[2], "st\\.id_segment = nr\\.id_segment")
  expect_match(captured[2], "st\\.watershed_group_code = nr\\.watershed_group_code")
  expect_match(captured[2], "nr\\.linear_feature_id IS NULL")
  expect_length(captured, 2L)

  # Up to date: nothing issued, so no lock (#369).
  captured <- character(0)
  local_mocked_bindings(.lnk_schema_columns = cols(c(old, "linear_feature_id")))
  expect_identical(.lnk_near_river_lfid_migrate("c", "s"), 0L)
  expect_length(captured, 0L)

  # A catalog that names nothing: left alone (the persist's INSERT names the
  # column and fails loudly if it is missing).
  local_mocked_bindings(.lnk_schema_columns = cols())
  expect_identical(.lnk_near_river_lfid_migrate("c", "s"), 0L)
  expect_length(captured, 0L)
})

test_that("lnk_persist_init fills linear_feature_id on an old near-river table from streams", {
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if_not(identical(info$host, "localhost") && identical(info$dbname, "fwapg"),
              "needs the local docker fwapg")
  schema <- paste0("zz_test452_", Sys.getpid())
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- schema
  sp <- c("BT", "CH")
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  suppressMessages(lnk_persist_init(conn, cfg, species = sp))
  # Back to the table as link 0.86.0 made it, holding a build's rows.
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s.streams_near_river DROP COLUMN linear_feature_id", schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams (id_segment, watershed_group_code, linear_feature_id)
     VALUES (1, 'AAAA', 701), (2, 'AAAA', 702), (1, 'BBBB', 801)", schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams_near_river
       (id_segment, watershed_group_code, measure, threshold, distance_max, dist_m)
     VALUES (1, 'AAAA', 'channel_width', 15, 1000, 10),
            (2, 'AAAA', 'channel_width', 15, 1000, 20),
            (1, 'BBBB', 'channel_width', 15, 1000, 30),
            (9, 'BBBB', 'channel_width', 15, 1000, 40)", schema))

  suppressMessages(lnk_persist_init(conn, cfg, species = sp))
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, watershed_group_code, linear_feature_id
       FROM %s.streams_near_river ORDER BY watershed_group_code, id_segment", schema))
  # Each row takes its own group's segment, never another group's at the same
  # id_segment; a row whose segment is not in streams stays NULL.
  expect_identical(as.numeric(got$linear_feature_id), c(701, 702, 801, NA))

  # A second init finds the column and changes nothing.
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.streams_near_river SET linear_feature_id = NULL
      WHERE id_segment = 1 AND watershed_group_code = 'AAAA'", schema))
  suppressMessages(lnk_persist_init(conn, cfg, species = sp))
  again <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.streams_near_river
      WHERE linear_feature_id IS NULL", schema))$n
  expect_identical(again, 2L)
})
