# Per-group parts of the habitat export (#465): the barrier and override rows
# another group's downstream walk reads, one part per group per config.

test_that("the export writes a barriers and an overrides part per exported group", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()

  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  gp <- m$group_parts
  keys <- vapply(gp, function(x) x$key, character(1))
  expect_setequal(keys, c(
    sprintf("barriers/config=testcfg/part-%s.parquet", c("ADMS", "BULK", "LFRA")),
    sprintf("barrier_overrides/config=testcfg/part-%s.parquet",
            c("ADMS", "BULK", "LFRA"))))
  rows <- stats::setNames(vapply(gp, function(x) as.integer(x$rows), integer(1)),
                          keys)
  expect_identical(unname(rows[c(
    "barriers/config=testcfg/part-ADMS.parquet",
    "barriers/config=testcfg/part-BULK.parquet",
    "barriers/config=testcfg/part-LFRA.parquet",
    "barrier_overrides/config=testcfg/part-ADMS.parquet",
    "barrier_overrides/config=testcfg/part-BULK.parquet")]),
    c(2L, 0L, 1L, 1L, 0L))
  # each part names the build it came from, and its md5 is the file's
  runs <- c(ADMS = "r1", BULK = "r2", LFRA = "r3")
  for (x in gp) {
    expect_identical(x$run_id, runs[[x$wsg]], info = x$key)
    f <- file.path(root, x$key)
    expect_identical(unname(tools::md5sum(f)), x$md5, info = x$key)
    expect_identical(as.numeric(file.size(f)), as.numeric(x$bytes))
  }
  # the manifest describes both datasets' columns
  ds <- vapply(m$datasets, function(x) x$dataset, character(1))
  expect_true(all(c("habitat/fwa/v1/barriers",
                    "habitat/fwa/v1/barrier_overrides") %in% ds))
  # lnk_catalog() still reads the segment parts alone
  expect_true(all(startsWith(lnk_catalog(p)$key, "segment/")))
})

test_that("a barriers part holds the persisted rows in a form that casts back", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  lnk_scenario_export(conn, c(testcfg = schema), root)

  b <- read_parquet_duck(file.path(root,
                                   "barriers/config=testcfg/part-ADMS.parquet"))
  expect_identical(names(b), names(link:::cols_barriers))
  expect_identical(b$id_barrier, c("CABD-x", "GRADIENT-1"))
  expect_identical(b$blocks_species, c("{BT,CH}", "{CH,CO}"))
  expect_identical(b$localcode_ltree, c("100.1.5", "100.1"))
  expect_identical(b$downstream_route_measure, c(120.125, 50))
  # geometry and arrays come back equal to the persisted rows
  back <- DBI::dbGetQuery(conn, sprintf(
    "SELECT b.id_barrier,
            ST_Equals(ST_SetSRID(ST_GeomFromWKB(decode(x.g, 'hex')), 3005),
                      b.geom) AS geom_equal,
            x.s::text[] = b.blocks_species AS species_equal
       FROM %s.barriers b
       JOIN (VALUES ($1, $2, $3), ($4, $5, $6)) x(id, g, s)
         ON x.id = b.id_barrier", schema),
    params = list(b$id_barrier[1], b$geom[1], b$blocks_species[1],
                  b$id_barrier[2], b$geom[2], b$blocks_species[2]))
  expect_true(all(back$geom_equal))
  expect_true(all(back$species_equal))

  o <- read_parquet_duck(file.path(
    root, "barrier_overrides/config=testcfg/part-ADMS.parquet"))
  expect_identical(names(o), names(link:::cols_barrier_overrides))
  expect_identical(nrow(o), 1L)
  # a group with none still has a part, with the columns
  none <- read_parquet_duck(file.path(
    root, "barrier_overrides/config=testcfg/part-BULK.parquet"))
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), names(link:::cols_barrier_overrides))
})

test_that("a persist schema without its barrier tables is refused", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  DBI::dbExecute(conn, sprintf("DROP TABLE %s.barrier_overrides", schema))
  expect_error(lnk_scenario_export(conn, c(testcfg = schema),
                                   withr::local_tempdir()),
               "barrier_overrides does not exist")
})

test_that("re-exporting one config keeps the other's per-group parts", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  s2 <- paste0(schema, "_g")
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", s2)))
  link:::.lnk_log_create_tables(conn, s2)
  export_copy_barriers(conn, schema, s2)
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
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  cfgs <- vapply(m$group_parts, function(x) x$config, character(1))
  expect_identical(sum(cfgs == "cfg2"), 6L)
  expect_identical(sum(cfgs == "testcfg"), 6L)
  # a kept per-group part changed on disk: refuse rather than publish it
  k <- m$group_parts[[which(cfgs == "cfg2")[1]]]$key
  write("x", file.path(root, k), append = TRUE)
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root),
               "missing or changed")
})

test_that("the regressions judgement names a dropped per-group part", {
  gpart <- function(cf, t, w) {
    list(config = cf, dataset = paste0("habitat/fwa/v1/", t), wsg = w)
  }
  cfg <- list(list(config = "a", runs = list()))
  old <- list(parts = list(), configs = cfg,
              group_parts = list(gpart("a", "barriers", "ADMS"),
                                 gpart("a", "barriers", "BULK")))
  new <- list(parts = list(), configs = cfg,
              group_parts = list(gpart("a", "barriers", "ADMS")))
  got <- link:::.lnk_manifest_regressions(old, new, "a")
  expect_length(got, 1L)
  expect_match(got, "drops 1 per-group part\\(s\\) \\(habitat/fwa/v1/barriers:BULK\\)")
  # a manifest from before per-group parts holds none to lose
  pre <- old
  pre$group_parts <- NULL
  expect_length(link:::.lnk_manifest_regressions(pre, new, "a"), 0L)
})
