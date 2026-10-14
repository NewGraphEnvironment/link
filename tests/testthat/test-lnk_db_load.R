# lnk_db_load() (#308)

local_load_table <- function(conn, env = parent.frame()) {
  sch <- paste0("lnk_test_load_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sch))
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", sch)), envir = env)
  paste0(sch, ".fwa_v1_segment")
}

test_that("export, catalog and load round-trip, keyed by position, with no fan-out", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  tbl <- local_load_table(conn)

  cat <- lnk_catalog(lnk_scenario_export(conn, c(testcfg = schema), root))
  out <- lnk_db_load(conn, cat, table = tbl)
  expect_identical(sum(out$rows), sum(cat$rows))

  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT config, species, watershed_group_code, count(*)::integer AS n,
            sum(length_metre) AS m,
            sum(CASE WHEN spawning THEN length_metre ELSE 0 END) AS spawn_m
       FROM %s GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", tbl))
  expect_identical(got$watershed_group_code, c("ADMS", "LFRA", "BULK"))
  expect_identical(got$species, c("BT", "BT", "CO"))
  expect_identical(got$n, c(2L, 1L, 2L))
  expect_equal(got$m, c(250, 40, 580))
  expect_equal(got$spawn_m, c(100, 0, 0))

  # a reload of the config replaces it rather than appending
  lnk_db_load(conn, cat, table = tbl)
  n <- DBI::dbGetQuery(conn, sprintf("SELECT count(*)::integer AS n FROM %s",
                                     tbl))$n
  expect_identical(n, 5L)
  pk <- DBI::dbGetQuery(conn, sprintf(
    "SELECT pg_get_constraintdef(oid) AS d FROM pg_constraint
      WHERE conrelid = '%s'::regclass AND contype = 'p'", tbl))$d
  expect_match(pk, "config, species, blue_line_key, downstream_route_measure")
})

test_that("a part whose md5 does not match is refused and the table is unchanged", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  root <- local_export_tree()
  tbl <- local_load_table(conn)
  cat <- lnk_catalog(file.path(root, "manifest.json"))
  lnk_db_load(conn, cat, table = tbl)

  bad <- cat
  bad$md5 <- strrep("0", 32)
  expect_error(lnk_db_load(conn, bad, table = tbl), "does not match")
  expect_identical(DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::integer AS n FROM %s", tbl))$n, 3L)

  # bytes changed on disk after the manifest was written
  write("x", file.path(root, cat$key), append = TRUE)
  expect_error(lnk_db_load(conn, cat, table = tbl), "does not match")
})

test_that("a failure mid-load rolls the whole load back", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  root <- local_export_tree()
  local_export_tree(config = "cfgx", species = "CO", root = root)
  tbl <- local_load_table(conn)
  # two parts: rebuild the manifest over both
  keys <- c("segment/config=cfgx/species=BT/part-100.parquet",
            "segment/config=cfgx/species=CO/part-100.parquet")
  e <- do.call(rbind, lapply(keys, function(k) link:::.lnk_file_entry(root, k)))
  link:::.lnk_manifest_write(root, data.frame(
    key = keys, dataset = "habitat/fwa/v1/segment", config = "cfgx",
    species = c("BT", "CO"), code = "100", drainage = "Fraser", wsgs = "ADMS",
    rows = 3L, bytes = e$bytes, md5 = e$md5), NULL, list())
  cat <- lnk_catalog(file.path(root, "manifest.json"))
  lnk_db_load(conn, cat[1, ], table = tbl)

  calls <- 0L
  real <- DBI::dbAppendTable
  local_mocked_bindings(dbAppendTable = function(conn, name, value, ...) {
    calls <<- calls + 1L
    if (calls == 2L) stop("connection lost")
    real(conn, name, value, ...)
  }, .package = "DBI")
  expect_error(lnk_db_load(conn, cat, table = tbl), "connection lost")
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT species, count(*)::integer AS n FROM %s GROUP BY 1", tbl))
  expect_identical(got$species, "BT")
  expect_identical(got$n, 3L)
})

test_that("a remote part is fetched once, checked, and reused from the cache", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  root <- local_export_tree()
  tbl <- local_load_table(conn)
  cache <- withr::local_tempdir()
  cat <- lnk_catalog(file.path(root, "manifest.json"))
  cat$href <- paste0("s3://fresh-bc/habitat/fwa/v1/", cat$key)
  n <- 0L
  local_mocked_bindings(.lnk_aws = function(args) {
    n <<- n + 1L
    src <- sub("^'s3://fresh-bc/habitat/fwa/v1/(.*)'$", "\\1", args[3])
    file.copy(file.path(root, src), gsub("^'|'$", "", args[4]),
              overwrite = TRUE)
    character(0)
  })
  lnk_db_load(conn, cat, table = tbl, cache_dir = cache)
  lnk_db_load(conn, cat, table = tbl, cache_dir = cache)
  expect_identical(n, 1L)
  expect_true(file.exists(file.path(cache, cat$key)))

  # a download that does not match is never kept in the cache
  unlink(file.path(cache, cat$key))
  bad <- cat
  bad$md5 <- strrep("1", 32)
  expect_error(lnk_db_load(conn, bad, table = tbl, cache_dir = cache),
               "does not match")
  expect_false(file.exists(file.path(cache, cat$key)))
})

test_that("a table with another column contract is refused", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  root <- local_export_tree()
  tbl <- local_load_table(conn)
  sch <- sub("\\..*$", "", tbl)
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", sch))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s (config text, x int)", tbl))
  cat <- lnk_catalog(file.path(root, "manifest.json"))
  expect_error(lnk_db_load(conn, cat, table = tbl), "other columns")
})
