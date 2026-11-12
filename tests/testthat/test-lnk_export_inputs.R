# Input snapshots in the habitat export (#465): CABD and PSCIS by content,
# observations and crossings cited by version.

test_that("a table's content md5 ignores physical row order and sees content", {
  conn <- skip_if_no_db()
  mk <- function(name, rows) {
    DBI::dbExecute(conn, sprintf("DROP TABLE IF EXISTS pg_temp.%s", name))
    DBI::dbExecute(conn, sprintf(
      "CREATE TEMP TABLE %s (id int, name text, geom geometry(Point, 3005))", name))
    DBI::dbExecute(conn, sprintf("INSERT INTO %s VALUES %s", name, rows))
    paste0("pg_temp.", name)
  }
  a <- mk("lnk_md5_a", "(1, 'x', ST_SetSRID(ST_MakePoint(1, 2), 3005)), (2, NULL, NULL)")
  b <- mk("lnk_md5_b", "(2, NULL, NULL), (1, 'x', ST_SetSRID(ST_MakePoint(1, 2), 3005))")
  c <- mk("lnk_md5_c", "(2, NULL, NULL), (1, 'y', ST_SetSRID(ST_MakePoint(1, 2), 3005))")
  ma <- link:::.lnk_table_content_md5(conn, a)
  expect_match(ma, "^[0-9a-f]{32}$")
  expect_identical(link:::.lnk_table_content_md5(conn, b), ma)
  expect_false(identical(link:::.lnk_table_content_md5(conn, c), ma))
  expect_identical(link:::.lnk_table_content_md5(conn, "pg_temp.lnk_md5_none"),
                   NA_character_)
})

# The fixture export with its CABD and PSCIS pointed at two fixture tables.
local_inputs_fixture <- function(conn, env = parent.frame()) {
  schema <- local_export_fixture(conn, env = env)
  local_export_discharge(schema, env = env)
  for (t in c("cabd_fx", "pscis_fx")) {
    DBI::dbExecute(conn, sprintf(
      "CREATE TABLE %s.%s (id int, status text, geom geometry(Point, 3005))",
      schema, t))
    DBI::dbExecute(conn, sprintf(
      "INSERT INTO %s.%s VALUES (1, 'BARRIER', ST_SetSRID(ST_MakePoint(1, 2), 3005)),
                                (2, 'PASSABLE', NULL)", schema, t))
  }
  testthat::local_mocked_bindings(
    .lnk_export_input_tables = function() {
      list(snapshot = c(cabd_dams = paste0(schema, ".cabd_fx"),
                        pscis_assessment = paste0(schema, ".pscis_fx")),
           cited = c(observations = "bcfishobs.observations"))
    }, .package = "link", .env = env)
  schema
}

test_that("a build whose logged content is held now gets a snapshot; others say why", {
  skip_if_not_installed("duckdb")
  conn <- skip_if_no_db()
  schema <- local_inputs_fixture(conn)
  cabd <- paste0(schema, ".cabd_fx")
  pscis <- paste0(schema, ".pscis_fx")
  now <- link:::.lnk_table_content_md5(conn, cabd)
  # ADMS (r1) logged what is held now; BULL (r2) other content and no dams;
  # LFRA (r3) nothing (a build from before #465)
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_input (run_id, table_name, artifact_content_md5,
                               artifact_url, artifact_version_id)
     VALUES ('r1', $1, $3, NULL, NULL), ('r1', $2, $3, NULL, NULL),
            ('r2', $1, 'ffffffffffffffffffffffffffffffff', NULL, NULL),
            ('r2', $2, 'ffffffffffffffffffffffffffffffff', NULL, NULL),
            ('r1', 'bcfishobs.observations', NULL, 'https://x/obs.parquet', 'v1')",
    schema), params = list(cabd, pscis, now))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET arg_dams = false WHERE run_id = 'r2'", schema))
  root <- withr::local_tempdir()
  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  runs <- m$configs[[1]]$runs
  inp <- stats::setNames(lapply(runs, function(r) r$inputs),
                         vapply(runs, function(r) r$run_id, character(1)))
  key <- sprintf("inputs/cabd_dams/%s.parquet", now)
  expect_identical(inp$r1$cabd_dams$key, key)
  expect_true(file.exists(file.path(root, key)))
  expect_identical(inp$r1$observations$version_id, "v1")
  expect_identical(inp$r2$cabd_dams$reason, "not read")
  expect_identical(inp$r2$pscis_assessment$reason, "changed since build")
  # a changed input keeps its table, so the loader can still compare it
  expect_identical(inp$r2$pscis_assessment$table, pscis)
  expect_identical(inp$r3$cabd_dams$reason, "no content identity at build")
  # the snapshot holds the table's rows as text, its file in `files`
  snap <- read_parquet_duck(file.path(root, key))
  expect_identical(snap$id, c("1", "2"))
  expect_match(snap$geom[1], "^0101000020bd0b0000")
  f <- Filter(function(x) identical(x$key, key), m$files)
  expect_length(f, 1L)
  expect_identical(f[[1]]$kind, "input")
  expect_identical(f[[1]]$md5, unname(tools::md5sum(file.path(root, key))))

  # the table moves on: an existing snapshot is still referenced
  DBI::dbExecute(conn, sprintf("UPDATE %s SET status = 'X' WHERE id = 2", cabd))
  p <- lnk_scenario_export(conn, c(testcfg = schema), root)
  m <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  r1 <- Filter(function(r) identical(r$run_id, "r1"), m$configs[[1]]$runs)[[1]]
  expect_identical(r1$inputs$cabd_dams$key, key)
  expect_length(Filter(function(x) identical(x$key, key), m$files), 1L)
})

test_that("log_input copies the ledger's content md5", {
  conn <- skip_if_no_db()
  schema <- paste0("lnk_test_inputs_", Sys.getpid())
  host <- paste0("test465-", Sys.getpid())
  withr::defer({
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
    DBI::dbExecute(conn, sprintf(
      "DELETE FROM provenance.source_artifact WHERE host = %s",
      DBI::dbQuoteLiteral(conn, host)))
  })
  withr::local_envvar(LNK_HOST_ALIAS = host)
  link:::.lnk_log_create_tables(conn, schema)
  url <- link:::.lnk_input_primitives()
  url <- url$url[url$table_name == "cabd.dams"]
  lnk_artifact_record(conn, data.frame(table_name = "cabd.dams", url = url),
                      recorded_by = "loader", host = host)
  rec <- DBI::dbGetQuery(conn,
    "SELECT content_md5 FROM provenance.source_artifact
      WHERE host = $1 AND table_name = 'cabd.dams'", params = list(host))
  expect_identical(rec$content_md5,
                   link:::.lnk_table_content_md5(conn, "cabd.dams"))
  link:::.lnk_log_inputs(conn, schema, "rX", "ADMS")
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT artifact_content_md5 FROM %s.log_input
      WHERE run_id = 'rX' AND table_name = 'cabd.dams'", schema))
  expect_identical(got$artifact_content_md5, rec$content_md5)
})

test_that("a ledger written before content_md5 existed still records log_input", {
  conn <- skip_if_no_db()
  schema <- paste0("lnk_test_oldledger_", Sys.getpid())
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE",
                                            schema)))
  link:::.lnk_log_create_tables(conn, schema)
  old <- link:::cols_source_artifact
  old <- old[setdiff(names(old), "content_md5")]
  old <- sub("\\s+CHECK .*$", "", old)
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.source_artifact (%s)", schema,
                               paste(names(old), old, collapse = ", ")))
  local_mocked_bindings(.lnk_artifact_location = function() {
    list(schema = schema, table = "source_artifact")
  })
  expect_no_warning(link:::.lnk_log_inputs(conn, schema, "rOld", "ADMS"))
  got <- DBI::dbGetQuery(conn, sprintf(
    "SELECT count(*)::int AS n, count(artifact_content_md5)::int AS m
       FROM %s.log_input WHERE run_id = 'rOld'", schema))
  expect_gt(got$n, 0L)
  expect_identical(got$m, 0L)
})
