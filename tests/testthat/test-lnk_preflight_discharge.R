cfg_src <- function(source) {
  list(name = "x", pipeline = list(discharge_source = source))
}

test_that("a loaded, valued table passes; absent or empty fails, with the load", {
  ok <- lnk_preflight_discharge(cfg = cfg_src("wet"), quiet = TRUE,
    state = data.frame(exists = TRUE, valued = TRUE, comment = "loaded x"))
  expect_true(ok$ok)
  expect_identical(ok$table, "discharge.fwa_v1_segment_monthly")
  expect_identical(ok$comment, "loaded x")

  gone <- lnk_preflight_discharge(cfg = cfg_src("wet"), quiet = TRUE,
    state = data.frame(exists = FALSE, valued = FALSE, comment = NA))
  expect_false(gone$ok)
  expect_match(gone$message, "does not exist", fixed = TRUE)
  expect_match(gone$message, "pick_only = TRUE", fixed = TRUE)

  empty <- lnk_preflight_discharge(cfg = cfg_src("wet"), quiet = TRUE,
    state = data.frame(exists = TRUE, valued = FALSE, comment = NA))
  expect_false(empty$ok)
  expect_match(empty$message, "no value the pipeline reads", fixed = TRUE)

  # A config that names no source checks fwapg's table.
  fw <- lnk_preflight_discharge(cfg = list(pipeline = list()), quiet = TRUE,
    state = data.frame(exists = FALSE, valued = FALSE, comment = NA))
  expect_identical(fw$source, "fwapg")
  expect_match(fw$message, "fwa_stream_networks_discharge", fixed = TRUE)
})

test_that("the report names the state", {
  expect_message(lnk_preflight_discharge(cfg = cfg_src("wet"),
    state = data.frame(exists = FALSE, valued = FALSE, comment = NA)),
    "^FAIL discharge \\(wet\\)")
})

test_that("prepare's join fails with the way to load a missing source", {
  conn <- skip_if_no_db()
  testthat::local_mocked_bindings(
    .lnk_discharge_state = function(conn, source) {
      data.frame(exists = FALSE, valued = FALSE, comment = NA_character_)
    }, .package = "link")
  expect_error(link:::.lnk_discharge_join(conn, "x.streams", "ADMS",
                                          source = "wet"),
               "wet::wet_db_load")
})

test_that("the state is read from the database", {
  conn <- skip_if_no_db()
  st <- link:::.lnk_discharge_state(conn, "fwapg")
  expect_identical(names(st), c("exists", "valued", "comment"))
  if (!st$exists) skip("no fwapg discharge in this database")
  expect_true(st$valued)
  w <- link:::.lnk_discharge_state(conn, "wet")
  if (w$exists) {
    expect_true(w$valued)
    expect_match(w$comment, "wet_db_load", fixed = TRUE)
  }
})

test_that("a run fingerprints wet's table only when its config reads wet", {
  base <- link:::.lnk_input_primitives()
  expect_identical(link:::.lnk_input_primitives_run(NULL), base)
  expect_identical(link:::.lnk_input_primitives_run(cfg_src("fwapg")), base)
  w <- link:::.lnk_input_primitives_run(cfg_src("wet"))
  expect_identical(nrow(w), nrow(base) + 1L)
  expect_identical(w$table_name[nrow(w)], "discharge.fwa_v1_segment_monthly")
  # Not a vintage-gate primitive: a host without wet passes the gate.
  expect_false("discharge.fwa_v1_segment_monthly" %in%
                 link:::.lnk_vintage_primitives())
})

test_that("log_input records wet's table and its load comment for a wet run", {
  conn <- skip_if_no_db()
  if (!link:::.lnk_discharge_state(conn, "wet")$exists) {
    skip("no wet discharge in this database")
  }
  schema <- paste0("zz_test331li_", Sys.getpid())
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  link:::.lnk_log_create_tables(conn, schema)
  expect_true(link:::.lnk_log_inputs(conn, schema, "run-wet", "ADMS",
                                     cfg = cfg_src("wet")))
  expect_true(link:::.lnk_log_inputs(conn, schema, "run-fw", "ADMS",
                                     cfg = cfg_src("fwapg")))
  li <- DBI::dbGetQuery(conn, sprintf(
    "SELECT run_id, table_comment, artifact_url FROM %s.log_input
      WHERE table_name = 'discharge.fwa_v1_segment_monthly'", schema))
  expect_identical(li$run_id, "run-wet")
  # Independent of the code under test: the catalogue read directly.
  want <- DBI::dbGetQuery(conn,
    "SELECT obj_description('discharge.fwa_v1_segment_monthly'::regclass,
                            'pg_class') AS c")$c
  expect_identical(li$table_comment, want)
  expect_match(li$artifact_url, "discharge/fwa/v1/manifest.json", fixed = TRUE)
})

test_that("a wet load is named by its build, not by how much of it was loaded", {
  full <- paste("wet_db_load(): discharge/fwa/v1/segment_monthly, scenario",
                "historical last loaded from https://x/manifest.json",
                "(built 2026-10-15T02:06:57Z, wet acb820f)")
  pick <- paste0(full, "; subset month IN (0) AND pick")
  expect_identical(link:::.lnk_discharge_wet_load_id(pick), full)
  expect_identical(link:::.lnk_discharge_wet_load_id(full), full)
  expect_identical(link:::.lnk_discharge_wet_load_id(NA_character_),
                   NA_character_)
})
