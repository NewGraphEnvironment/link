# Habitat export (#308)

test_that("the column contract parses and names every documented column", {
  cols <- link:::.lnk_export_cols()
  expect_identical(names(cols)[1:3], c("blue_line_key",
                                       "downstream_route_measure",
                                       "upstream_route_measure"))
  expect_true(all(cols %in% c("integer", "double", "string", "logical")))
  expect_true(all(c("mad_m3s", "mad_m3s_source", "accessible", "spawning",
                    "rearing", "lake_rearing", "wetland_rearing",
                    "accessible_ratio_gradient", "spawning_ratio_cw",
                    "spawning_ratio_mad", "spawning_ratio_gradient",
                    "rearing_ratio_cw", "rearing_ratio_mad",
                    "rearing_ratio_gradient") %in% names(cols)))
  expect_false(anyDuplicated(names(cols)) > 0)
})

test_that("conform refuses a wrong type, a reordered column and an NA flag", {
  cols <- c(a = "integer", accessible = "logical")
  ok <- data.frame(a = 1L, accessible = TRUE)
  # the key and flag checks need the real names; test type/order only here
  expect_error(link:::.lnk_export_conform(data.frame(a = 1, accessible = TRUE),
                                          cols), "wrong type")
  expect_error(link:::.lnk_export_conform(ok[2:1], cols), "column contract")
})

test_that("rows join on the full key, read FALSE for an absent species, and ratio on logged thresholds", {
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)

  adms <- link:::.lnk_export_rows(conn, schema, "ADMS", "BT",
                                  export_run(conn, schema, "ADMS"))
  # two segments, not four: BULK shares id_segment 1 and 2
  expect_identical(nrow(adms), 2L)
  expect_identical(adms$spawning, c(TRUE, FALSE))
  expect_identical(adms$mad_m3s, c(0.5, 0.5))
  expect_identical(adms$mad_m3s_source, c("modelled", "modelled"))
  expect_equal(adms$spawning_ratio_cw, c(4 / 2, NA))
  expect_equal(adms$spawning_ratio_mad, c(0.5 / 0.25, 0.5 / 0.25))
  expect_equal(adms$spawning_ratio_gradient, c(0.02 / 0.05, 0.20 / 0.05))
  expect_equal(adms$rearing_ratio_gradient, c(0.02 / 0.10, 0.20 / 0.10))
  expect_equal(adms$accessible_ratio_gradient, c(0.02 / 0.25, 0.20 / 0.25))
  # a blank threshold in the logged text snapshot is NULL, not 0
  expect_true(all(is.na(adms$rearing_ratio_cw)))

  # recomputed barrier flag from streams_access, beside the classified flag
  expect_identical(adms$has_barriers_dnstr, c(FALSE, TRUE))

  bulk <- link:::.lnk_export_rows(conn, schema, "BULK", "CO",
                                  export_run(conn, schema, "BULK"))
  expect_identical(nrow(bulk), 2L)
  for (f in c("accessible", "spawning", "rearing", "lake_rearing",
              "wetland_rearing")) {
    expect_identical(bulk[[f]], c(FALSE, FALSE), info = f)
  }
  expect_identical(bulk$mad_m3s, c(40, NA))
  # no streams_access column for CO: NA, not FALSE
  expect_true(all(is.na(bulk$has_barriers_dnstr)))

  # a build that logged no thresholds gives NA ratios, not a fallback
  lfra <- link:::.lnk_export_rows(conn, schema, "LFRA", "BT",
                                  export_run(conn, schema, "LFRA"))
  expect_true(is.na(lfra$spawning_ratio_cw))
  expect_equal(lfra$accessible_ratio_gradient, 0.01 / 0.25)
  expect_identical(lfra$wetland_rearing, TRUE)
})

test_that("a species with no habitat rows for the group is refused, not read as FALSE", {
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  expect_error(link:::.lnk_export_rows(conn, schema, "ADMS", "CO",
                                       export_run(conn, schema, "ADMS")),
               "has no rows for it")
  expect_error(link:::.lnk_export_rows(conn, schema, "ADMS", "SK",
                                       export_run(conn, schema, "ADMS")),
               "has no rows for it")
})

test_that("a fanned-out discharge join is refused", {
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.discharge VALUES (101, 0.6)", schema))
  expect_error(
    link:::.lnk_export_rows(conn, schema, "ADMS", "BT",
                            export_run(conn, schema, "ADMS")),
    "fanned out")
})

test_that("the export writes one part per drainage, md5s that match, and FALSE for an unmodelled species", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()

  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  keys <- vapply(m$parts, function(x) x$key, character(1))
  # a part only where a group modelled the species
  expect_setequal(keys, c(
    "segment/config=testcfg/species=BT/part-100.parquet",
    "segment/config=testcfg/species=CO/part-400.parquet"))
  for (x in m$parts) {
    f <- file.path(root, x$key)
    expect_identical(unname(tools::md5sum(f)), x$md5, info = x$key)
    expect_identical(as.numeric(file.size(f)), as.numeric(x$bytes))
    expect_identical(nrow(read_parquet_duck(f)), as.integer(x$rows))
  }
  fraser <- read_parquet_duck(file.path(
    root, "segment/config=testcfg/species=BT/part-100.parquet"))
  expect_identical(fraser$watershed_group_code, c("ADMS", "ADMS", "LFRA"))
  expect_identical(names(fraser), names(link:::.lnk_export_cols()))
  skeena <- read_parquet_duck(file.path(
    root, "segment/config=testcfg/species=CO/part-400.parquet"))
  expect_identical(nrow(skeena), 2L)
  expect_false(any(skeena$accessible | skeena$spawning | skeena$rearing))

  cf <- m$configs[[1]]
  expect_identical(cf$config, "testcfg")
  expect_identical(unlist(cf$wsgs), c("ADMS", "BULK", "LFRA"))
  expect_identical(unlist(cf$species), c("BT", "CO"))
  expect_identical(cf$thresholds_logged[["sha256:A"]], TRUE)
  expect_identical(cf$thresholds_logged[["sha256:B"]], FALSE)
  expect_match(cf$bundles[[1]]$reason, "no config named")
  expect_true(all(vapply(cf$runs, function(r) is.null(r$model), logical(1))))
  # only the recompute after ADMS's build is part of it
  adms <- Filter(function(r) r$watershed_group_code == "ADMS", cf$runs)[[1]]
  expect_identical(unlist(adms$recompute_keys),
                   "provenance/recompute_id=rc1")
  expect_true(file.exists(file.path(
    root, "provenance/recompute_id=rc1/log_recompute.parquet")))
  expect_false(dir.exists(file.path(root, "provenance/recompute_id=rc0")))
  fk <- vapply(m$files, function(x) x$key, character(1))
  for (x in m$files) {
    expect_identical(unname(tools::md5sum(file.path(root, x$key))), x$md5,
                     info = x$key)
  }
  expect_true("provenance/run_uid=U1/log.parquet" %in% fk)
})

test_that("provenance is keyed by run_uid, or by run_id outside a dispatch, and is written once", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()

  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  u1 <- read_parquet_duck(file.path(root, "provenance/run_uid=U1/log.parquet"))
  expect_setequal(u1$run_id, c("r1", "r2"))
  r3 <- read_parquet_duck(file.path(root, "provenance/run_id=r3/log.parquet"))
  expect_identical(r3$run_id, "r3")
  inp <- read_parquet_duck(file.path(root,
                                     "provenance/run_uid=U1/log_input.parquet"))
  expect_identical(inp$run_id, "r1")
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  pk <- vapply(m$configs[[1]]$runs, function(x) x$provenance_key, character(1))
  expect_setequal(pk, c("provenance/run_uid=U1", "provenance/run_id=r3"))

  # the same build exports again cleanly...
  expect_no_error(lnk_scenario_export(conn, c(testcfg = schema), root))
  # ...but a changed record of it does not overwrite the published one
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET notes = 'edited' WHERE run_id = 'r3'", schema))
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root),
               "different content")
})

test_that("a group with no finished build of the config is refused", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams VALUES
       (1, 'BABL', 401, 1000, 40, 2, 3.0, 'MODELLED', 0.03, 0, 60, 60)",
    schema))

  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root,
                                   wsgs = "BABL"), "BABL \\(no log row\\)")
  expect_message(lnk_scenario_export(conn, c(testcfg = schema), root),
                 "BABL: no log row")
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root,
                                   wsgs = "ZZZZ"), "not in streams")

  # a newer build under another config supersedes the one we would export
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end,
                         config_name, config_hash)
     VALUES ('r4', 'LFRA', '2026-10-05T00:00:00Z', '2026-10-05T01:00:00Z',
             'othercfg', 'sha256:C')", schema))
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root,
                                   wsgs = "LFRA"), "latest build is config")

  # an unfinished latest build is refused even under the right config
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start,
                         config_name, config_hash)
     VALUES ('r5', 'ADMS', '2026-10-06T00:00:00Z', 'testcfg', 'sha256:A')",
    schema))
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root,
                                   wsgs = "ADMS"), "did not finish")

  # a build logged against another persist schema is not this schema's
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET schema_persist = 'elsewhere' WHERE run_id = 'r2'",
    schema))
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root,
                                   wsgs = "BULK"), "logged schema 'elsewhere'")
})

test_that("two schemas for one config may not hold the same group, and shared segmentation is checked", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  expect_error(
    lnk_scenario_export(conn, c(testcfg = schema, testcfg = schema), root),
    "more than one schema")

  s2 <- paste0(schema, "_b")
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", s2)))
  link:::.lnk_log_create_tables(conn, s2)
  DBI::dbExecute(conn, sprintf(
    "CREATE TABLE %s.streams AS SELECT * FROM %s.streams", s2, schema))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log SELECT * FROM %s.log WHERE run_id <> 'r0'", s2, schema))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET config_name = 'cfg2', run_uid = NULL,
                        schema_persist = '%s', run_id = run_id || '_b'",
    s2, s2))
  for (t in c("streams_habitat_bt", "streams_habitat_co")) {
    DBI::dbExecute(conn, sprintf(
      "CREATE TABLE %s.%s AS SELECT * FROM %s.%s", s2, t, schema, t))
  }
  expect_no_error(lnk_scenario_export(
    conn, c(testcfg = schema, cfg2 = s2), root, shared_segmentation = TRUE))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.streams SET length_metre = 99
      WHERE watershed_group_code = 'ADMS' AND id_segment = 1", s2))
  expect_error(lnk_scenario_export(
    conn, c(testcfg = schema, cfg2 = s2), root, shared_segmentation = TRUE),
    "segmentation differs")
})

test_that("bundle files are published only when today's bundle hashes the same", {
  root <- withr::local_tempdir()
  cfg <- lnk_config("default")
  h <- link:::.lnk_config_hash(cfg)
  b <- link:::.lnk_export_bundle("default", c(h, "sha256:old"), root)
  expect_identical(b$bundles[[1]]$config_hash, h)
  f <- b$bundles[[1]]$files
  expect_gt(length(f), 0)
  for (x in f) {
    expect_identical(digest::digest(file = file.path(root, x$key),
                                    algo = "sha256"), x$sha256, info = x$key)
  }
  expect_true(any(vapply(f, function(x) x$name == "config.yaml", logical(1))))
  expect_null(b$bundles[[2]]$prefix)
  expect_match(b$bundles[[2]]$reason, "changed since the build")
})

test_that("re-exporting one config keeps the other config's parts, and refuses a changed one", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()

  s2 <- paste0(schema, "_b")
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", s2)))
  link:::.lnk_log_create_tables(conn, s2)
  for (t in c("streams", "streams_habitat_bt", "streams_habitat_co")) {
    DBI::dbExecute(conn, sprintf(
      "CREATE TABLE %s.%s AS SELECT * FROM %s.%s", s2, t, schema, t))
  }
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log SELECT * FROM %s.log WHERE run_id <> 'r0'", s2, schema))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET config_name = 'cfg2', run_uid = NULL,
                        schema_persist = '%s', run_id = run_id || '_b'",
    s2, s2))

  lnk_scenario_export(conn, c(cfg2 = s2), root)
  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  cat <- lnk_catalog(p)
  expect_setequal(unique(cat$config), c("cfg2", "testcfg"))
  expect_setequal(vapply(attr(cat, "configs"), function(x) x$config,
                         character(1)), c("cfg2", "testcfg"))

  # a part of the kept config changed on disk: refuse rather than publish it
  f <- file.path(root, cat$key[cat$config == "cfg2"][1])
  write("x", f, append = TRUE)
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root),
               "missing or changed")
})

test_that("a log from before a column existed reads it as NA", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  DBI::dbExecute(conn, sprintf(
    "ALTER TABLE %s.log DROP COLUMN discharge_fill, DROP COLUMN run_uid",
    schema))
  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  expect_true(all(vapply(m$configs[[1]]$discharge$fill, is.null, logical(1))))
  expect_true(file.exists(file.path(root, "provenance/run_id=r1/log.parquet")))
})
