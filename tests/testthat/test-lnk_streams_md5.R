# The streams digest a run logs at its finish and an export checks (#334).

local_streams_schema <- function(conn, tag, env = parent.frame()) {
  sch <- paste0("lnk_test_md5_", tag, "_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sch))
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DROP SCHEMA IF EXISTS %s CASCADE", sch)), envir = env)
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", sch))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.streams (%s)", sch,
    paste(names(link:::cols_streams), link:::cols_streams, collapse = ", ")))
  sch
}

fill_streams <- function(conn, sch) {
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams VALUES
       (2, 'ADMS', 701, 1000, 10, 10, 'Adams River', 4, 30, NULL, 'GA24850000',
        '100.1', '100.1.2', 4.123456789012345, 'MODELLED', 5, 0.0123456789,
        100.000000001, 250.5, 150.499999999,
        ST_SetSRID(ST_GeomFromText(
          'MULTILINESTRING ZM ((1200000.1 600000.2 500 100, 1200100.3 600050.4 510 250.5))'),
          3005)),
       (1, 'ADMS', 700, 1000, 10, 10, NULL, 4, 30, NULL, 'GA24850000',
        '100.1', '100.1', NULL, NULL, NULL, 0.1, 0, 100, 100, NULL),
       (1, 'BULK', 800, 1000, 20, 20, NULL, 2, 1, NULL, 'GA24850000',
        '400', '400', 1, 'MODELLED', 3, 0.2, 0, 10, 10, NULL)", sch))
}

test_that("the digest is stable, versioned, and per group", {
  conn <- skip_if_no_db()
  sch <- local_streams_schema(conn, "a")
  fill_streams(conn, sch)
  d <- link:::.lnk_streams_md5(conn, sch, "ADMS")
  expect_match(d, "^v1:[0-9a-f]{32}$")
  expect_identical(link:::.lnk_streams_md5(conn, sch, "ADMS"), d)
  expect_false(identical(link:::.lnk_streams_md5(conn, sch, "BULK"), d))
  expect_true(is.na(link:::.lnk_streams_md5(conn, sch, "ZZZZ")))
  # the session's float output does not move it
  DBI::dbExecute(conn, "SET extra_float_digits = 0")
  withr::defer(DBI::dbExecute(conn, "RESET extra_float_digits"))
  expect_identical(link:::.lnk_streams_md5(conn, sch, "ADMS"), d)
})

test_that("a text COPY into another schema keeps the digest; a moved value does not", {
  # a consolidate moves rows with COPY in text format (schema_consolidate.R)
  conn <- skip_if_no_db()
  a <- local_streams_schema(conn, "src")
  b <- local_streams_schema(conn, "dst")
  fill_streams(conn, a)
  # each row through its text form and back, as COPY's text format does
  # (the same output and input functions), in another order
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %1$s.streams
     SELECT (s::text::%1$s.streams).* FROM %2$s.streams s ORDER BY random()",
    b, a))
  expect_identical(link:::.lnk_streams_md5(conn, b, "ADMS"),
                   link:::.lnk_streams_md5(conn, a, "ADMS"))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.streams SET gradient = gradient + 1e-15
      WHERE id_segment = 2 AND watershed_group_code = 'ADMS'", b))
  expect_false(identical(link:::.lnk_streams_md5(conn, b, "ADMS"),
                         link:::.lnk_streams_md5(conn, a, "ADMS")))
})

test_that("a table without the full column set gives no digest", {
  conn <- skip_if_no_db()
  sch <- local_streams_schema(conn, "short")
  fill_streams(conn, sch)
  DBI::dbExecute(conn, sprintf("ALTER TABLE %s.streams DROP COLUMN geom", sch))
  expect_true(is.na(link:::.lnk_streams_md5(conn, sch, "ADMS")))
})

test_that("an export stops where the persisted streams are not the build's", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  # a digest the fixture's rows cannot have
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET streams_md5 = 'v1:%s' WHERE run_id = 'r1'",
    schema, strrep("0", 32)))
  expect_error(lnk_scenario_export(conn, c(testcfg = schema), root),
               "not the ones run r1 logged")
})

test_that("an export reports builds that logged no digest", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  root <- withr::local_tempdir()
  m <- jsonlite::fromJSON(lnk_scenario_export(conn, c(testcfg = schema), root),
                          simplifyVector = FALSE)
  cf <- m$configs[[1]]
  expect_identical(cf$streams_digest$`no digest`, 3L)
  expect_identical(cf$streams_digest$match, 0L)
  expect_true(all(vapply(cf$runs, function(r) r$streams_digest,
                         character(1)) == "no digest"))
})
