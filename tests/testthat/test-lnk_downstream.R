# The one-group side of the export (#465): which parts a target's walk needs,
# and loading them into a persist schema.

# An export of the fixture in which ADMS reads LFRA (exported), BULK (skipped:
# its newest build is another config's) and KOTL (held by no exported schema).
local_downstream_export <- function(conn, env = parent.frame()) {
  schema <- local_export_fixture(conn, env = env)
  local_export_discharge(schema, env = env)
  testthat::local_mocked_bindings(
    .lnk_wsg_deps_line = function(conn, fwa = NULL) {
      data.frame(wsg = c("ADMS", "ADMS", "ADMS", "LFRA"),
                 dep = c("BULK", "KOTL", "LFRA", "ADMS"),
                 stringsAsFactors = FALSE)
    },
    .package = "link", .env = env)
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end,
                         config_name, config_hash, schema_persist, species)
     VALUES ('r9', 'BULK', '2026-10-05T00:00:00Z', '2026-10-05T01:00:00Z',
             'othercfg', 'sha256:B', '%s', '{CO}')", schema, schema))
  root <- withr::local_tempdir(.local_envir = env)
  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  list(schema = schema, root = root, manifest = p)
}

# A scratch persist schema for the default bundle, dropped afterwards.
local_downstream_cfg <- function(conn, env = parent.frame()) {
  cfg <- lnk_config("default")
  cfg$pipeline$schema <- paste0("lnk_test_downstream_", Sys.getpid())
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", cfg$pipeline$schema)), envir = env)
  cfg
}

test_that("the lister classes each dependency and lists the exported parts", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  x <- local_downstream_export(conn)
  f <- lnk_downstream_files(x$manifest, "ADMS", "testcfg",
                            cache_dir = withr::local_tempdir())
  expect_identical(f$wsg, c("BULK", "KOTL", "LFRA", "LFRA"))
  expect_identical(f$class, c("skipped", "not_held", "exported", "exported"))
  expect_identical(f$table[3:4], c("barrier_overrides", "barriers"))
  expect_identical(f$rows[3:4], c(0, 1))
  expect_identical(f$run_id[3:4], c("r3", "r3"))
  expect_identical(f$config_hash[3], "sha256:B")
  expect_match(f$reason[1], "no finished build")
  expect_match(f$fwa_url[2], "fwa_stream_networks_sp/KOTL.parquet$")
  expect_true(all(file.exists(f$href[3:4])))
  # a group nothing reads from lists nothing
  expect_identical(nrow(lnk_downstream_files(x$manifest, "BULK", "testcfg",
                                             cache_dir = withr::local_tempdir())),
                   0L)
  expect_error(lnk_downstream_files(x$manifest, "ADMS", "nocfg"),
               "exports no config 'nocfg'")
})

test_that("an export of named groups classes a left-out group not_exported", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  x <- local_downstream_export(conn)
  p <- lnk_scenario_export(conn, c(testcfg = x$schema), x$root,
                           wsgs = c("ADMS", "LFRA"), replace = TRUE)
  f <- lnk_downstream_files(p, "ADMS", "testcfg",
                            cache_dir = withr::local_tempdir())
  expect_identical(f$class[f$wsg == "KOTL"], "not_exported")
  expect_identical(f$class[f$wsg == "BULK"], "not_exported")
})

test_that("a manifest without a dependency map is refused by name", {
  root <- local_export_tree()
  expect_error(lnk_downstream_files(file.path(root, "manifest.json"), "ADMS",
                                    "cfgx"),
               "carries no dependency map")
})

test_that("the loader puts the dependencies' rows into the schema and records them", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  x <- local_downstream_export(conn)
  f <- lnk_downstream_files(x$manifest, "ADMS", "testcfg",
                            cache_dir = withr::local_tempdir())
  cfg <- local_downstream_cfg(conn)
  s <- cfg$pipeline$schema

  # rows missing from the export refuse
  expect_error(lnk_downstream_load(conn, f, cfg), "lacks the rows of 1 group")
  expect_message(rep <- lnk_downstream_load(conn, f, cfg, allow_missing = TRUE),
                 "another bundle")
  expect_identical(rep$wsg, "LFRA")
  expect_identical(rep$barriers, 1)
  expect_identical(rep$barrier_overrides, 0)
  expect_false(rep$config_same)

  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT n.id_barrier, n.blocks_species::text AS bs, n.wscode_ltree::text AS ws,
            n.geom IS NULL AS no_geom,
            n.downstream_route_measure = o.downstream_route_measure AS m_same
       FROM %s.barriers n JOIN %s.barriers o USING (id_barrier, watershed_group_code)",
    s, x$schema))
  expect_identical(got$id_barrier, "FALLS-3")
  expect_identical(got$bs, "{CH}")
  expect_identical(got$ws, "100")
  expect_true(got$no_geom)
  expect_true(got$m_same)
  log <- DBI::dbGetQuery(conn, sprintf(
    "SELECT watershed_group_code AS w, table_name, run_id, rows
       FROM %s.log_downstream_load ORDER BY table_name", s))
  expect_identical(log$table_name, c("barrier_overrides", "barriers"))
  expect_identical(log$run_id, c("r3", "r3"))

  # files filtered to one table load that table and report NA for the other
  rep1 <- suppressMessages(lnk_downstream_load(
    conn, f[is.na(f$table) | f$table == "barriers", ], cfg,
    allow_missing = TRUE))
  expect_identical(rep1$barriers, 1)
  expect_identical(rep1$barrier_overrides, NA_real_)

  # a reload replaces what an earlier load wrote
  lnk_downstream_load(conn, f, cfg, allow_missing = TRUE)
  expect_identical(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.barriers", s))$n, 1L)
})

test_that("the loader moves a geometry and an override exactly", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  x <- local_downstream_export(conn)
  f <- lnk_downstream_files(x$manifest, "LFRA", "testcfg",
                            cache_dir = withr::local_tempdir())
  cfg <- local_downstream_cfg(conn)
  s <- cfg$pipeline$schema
  suppressMessages(lnk_downstream_load(conn, f, cfg))
  eq <- DBI::dbGetQuery(conn, sprintf(
    "SELECT n.id_barrier, ST_Equals(n.geom, o.geom) AS g,
            ST_SRID(n.geom) AS srid,
            n.blocks_species = o.blocks_species AS bs,
            n.localcode_ltree = o.localcode_ltree AS loc,
            n.linear_feature_id IS NOT DISTINCT FROM o.linear_feature_id AS lfid
       FROM %s.barriers n JOIN %s.barriers o USING (id_barrier, watershed_group_code)
      ORDER BY 1", s, x$schema))
  expect_identical(eq$id_barrier, c("CABD-x", "GRADIENT-1"))
  expect_true(all(eq$g & eq$bs & eq$loc & eq$lfid))
  expect_identical(eq$srid, c(3005L, 3005L))
  ov <- DBI::dbGetQuery(conn, sprintf(
    "SELECT * FROM %s.barrier_overrides", s))
  expect_identical(nrow(ov), 1L)
  expect_identical(ov$species_code, "CH")
})

test_that("the loader refuses rows it did not load, and a changed part", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  x <- local_downstream_export(conn)
  f <- lnk_downstream_files(x$manifest, "LFRA", "testcfg",
                            cache_dir = withr::local_tempdir())
  cfg <- local_downstream_cfg(conn)
  s <- cfg$pipeline$schema
  lnk_persist_init(conn, cfg, species = cfg$species)
  link:::.lnk_log_create_tables(conn, s)
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end)
     VALUES ('mine', 'ADMS', now(), now())", s))
  expect_error(lnk_downstream_load(conn, f, cfg), "ADMS \\(built here\\)")
  suppressMessages(lnk_downstream_load(conn, f, cfg, replace = TRUE))
  expect_identical(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.barriers", s))$n, 2L)

  # a part that no longer matches the manifest stops before any write
  DBI::dbExecute(conn, sprintf("DELETE FROM %s.barriers", s))
  k <- f$href[f$table == "barriers"]
  write("x", k, append = TRUE)
  expect_error(lnk_downstream_load(conn, f, cfg, replace = TRUE),
               "does not match the manifest")
  expect_identical(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.barriers", s))$n, 0L)
})

test_that("the loader refuses a part holding another group's rows", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  x <- local_downstream_export(conn)
  f <- lnk_downstream_files(x$manifest, "LFRA", "testcfg",
                            cache_dir = withr::local_tempdir())
  cfg <- local_downstream_cfg(conn)
  i <- which(f$table == "barriers")
  rows <- read_parquet_duck(f$href[i])
  rows$watershed_group_code <- "XXXX"
  bad <- file.path(withr::local_tempdir(), "part-ADMS.parquet")
  link:::.lnk_parquet_write(rows, bad)
  f$href[i] <- bad
  f$bytes[i] <- as.numeric(file.size(bad))
  f$md5[i] <- unname(tools::md5sum(bad))
  expect_error(lnk_downstream_load(conn, f, cfg),
               "holds rows of another group")
  expect_identical(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n FROM %s.barriers", cfg$pipeline$schema))$n, 0L)
})
