# Tests for data-raw/schema_consolidate.R's handling of the log tables
# (link#354). The script runs over ssh, so these drive its two pure helpers
# and, live, the destination-side psql script it writes.
#
# data-raw/ is .Rbuildignore'd, so an installed package legitimately does not
# have the script; that, not skip_on_cran(), is the honest guard.
consolidate_script <- function() {
  testthat::test_path("..", "..", "data-raw", "schema_consolidate.R")
}

source_consolidate <- function(env = parent.frame()) {
  script <- consolidate_script()
  testthat::skip_if_not(file.exists(script),
                        "data-raw/schema_consolidate.R not in this tree")
  e <- new.env(parent = globalenv())
  sys.source(script, envir = e)
  e
}

test_that("log tables are split from persist tables, in discovery order", {
  e <- source_consolidate()
  wgc <- c("barriers", "log", "log_input", "log_recompute", "streams",
           "streams_habitat_bt")
  out <- e$consolidate_tables_split(wgc)
  expect_identical(out$history, c("log", "log_input", "log_recompute"))
  expect_identical(out$persist, c("barriers", "streams", "streams_habitat_bt"))
  # Every log table is history, including the config-hash ones that carry no
  # watershed_group_code today and so are never discovered.
  expect_identical(e$consolidate_tables_split(names(.lnk_log_specs()))$persist,
                   character(0))
})

test_that("consolidate_history_sql replaces by primary key, never by group", {
  e <- source_consolidate()
  sql <- e$consolidate_history_sql("s", "log_input",
    c("run_id", "watershed_group_code", "table_name", "row_count"),
    c("run_id", "table_name"), "/tmp/x.tsv")
  joined <- paste(sql, collapse = "\n")
  expect_match(joined, "CREATE TEMP TABLE consolidate_in ON COMMIT DROP AS SELECT run_id, watershed_group_code, table_name, row_count FROM s.log_input WITH NO DATA;", fixed = TRUE)
  expect_match(joined, "\\copy consolidate_in (run_id, watershed_group_code, table_name, row_count) FROM '/tmp/x.tsv'", fixed = TRUE)
  expect_match(joined, "DELETE FROM s.log_input d USING consolidate_in s WHERE (d.run_id, d.table_name) = (s.run_id, s.table_name);", fixed = TRUE)
  expect_match(joined, "INSERT INTO s.log_input (run_id, watershed_group_code, table_name, row_count) SELECT run_id, watershed_group_code, table_name, row_count FROM consolidate_in;", fixed = TRUE)
  delete <- grep("^DELETE", sql, value = TRUE)
  expect_no_match(delete, "watershed_group_code")
})

test_that("consolidate_history_sql refuses an unshared key or a quoted path", {
  e <- source_consolidate()
  expect_error(
    e$consolidate_history_sql("s", "log", c("watershed_group_code", "host"),
                              "run_id", "/tmp/x.tsv"),
    "primary key column\\(s\\) run_id of s.log are not shared")
  expect_error(
    e$consolidate_history_sql("s", "log", "run_id", "run_id", "/tmp/it's.tsv"),
    "single quote")
})

test_that("the staged script keeps a group's earlier builds (live)", {
  e <- source_consolidate()
  conn <- skip_if_no_db()
  psql <- Sys.which("psql")
  skip_if(!nzchar(psql), "psql not on PATH")
  info <- DBI::dbGetInfo(conn)
  skip_if(!identical(as.character(info$port), "5432") ||
            !info$host %in% c("localhost", "127.0.0.1"),
          "not the local docker fwapg the script writes to")

  dst <- paste0("lnk_test_consol_dst_", Sys.getpid())
  src <- paste0("lnk_test_consol_src_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  for (sc in c(dst, src)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
    link:::.lnk_log_create_tables(conn, sc)
  }
  withr::defer(for (sc in c(dst, src)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
  })

  # Destination: ADMS built twice before (A, then B still open), BULK once.
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end)
     VALUES ('A', 'ADMS', '2026-08-01', '2026-08-01'),
            ('B', 'ADMS', '2026-10-01', NULL),
            ('D', 'BULK', '2026-10-01', '2026-10-01')", dst))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_input (run_id, watershed_group_code, table_name, row_count)
     VALUES ('A', 'ADMS', 'streams', 1), ('B', 'ADMS', 'streams', 2)", dst))
  # Source: B again, now closed, and a new build C of ADMS.
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end)
     VALUES ('B', 'ADMS', '2026-10-01', '2026-10-02'),
            ('C', 'ADMS', '2026-10-17', '2026-10-17')", src))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log_input (run_id, watershed_group_code, table_name, row_count)
     VALUES ('B', 'ADMS', 'streams', 20), ('C', 'ADMS', 'streams', 3),
            ('C', 'ADMS', 'falls', 4)", src))

  env <- c(PGHOST = info$host, PGPORT = "5432", PGDATABASE = info$dbname,
           PGUSER = "postgres", PGPASSWORD = "postgres")
  # system2() warns on a non-zero exit; the status is read off the result.
  run_psql <- function(args, stderr = TRUE) {
    withr::with_envvar(env, suppressWarnings(
      system2(psql, args, stdout = TRUE, stderr = stderr)))
  }
  stage <- function(table, cols, pk, bad = FALSE) {
    tsv <- withr::local_tempfile(fileext = ".tsv")
    # stderr dropped: a NOTICE on it would land in the data file.
    out <- run_psql(c("-X", "-c", shQuote(sprintf(
      "COPY (SELECT %s FROM %s.%s WHERE watershed_group_code IN ('ADMS')) TO STDOUT",
      paste(cols, collapse = ", "), src, table))), stderr = FALSE)
    writeLines(c(out, if (bad) "not\ta\trow"), tsv)
    sqlf <- withr::local_tempfile(fileext = ".sql")
    writeLines(e$consolidate_history_sql(dst, table, cols, pk, tsv), sqlf)
    res <- run_psql(c("-X", "-1", "-v", "ON_ERROR_STOP=1", "-f", shQuote(sqlf)))
    attr(res, "status") %||% 0L
  }
  cols_log <- c("run_id", "watershed_group_code", "date_start", "date_end")
  cols_in <- c("run_id", "watershed_group_code", "table_name", "row_count")

  # A malformed file fails the whole transaction: nothing is deleted.
  expect_false(identical(stage("log", cols_log, "run_id", bad = TRUE), 0L))
  expect_identical(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int n FROM %s.log", dst))$n,
    3L)

  expect_identical(stage("log", cols_log, "run_id"), 0L)
  expect_identical(stage("log_input", cols_in, c("run_id", "table_name")), 0L)

  log <- DBI::dbGetQuery(conn, sprintf(
    "SELECT run_id, watershed_group_code, date_end::date::text AS date_end
       FROM %s.log ORDER BY run_id", dst))
  # A survives (history), B is replaced (its date_end set), C is added, and
  # BULK, outside the bucket, is untouched.
  expect_identical(log$run_id, c("A", "B", "C", "D"))
  expect_identical(log$date_end[log$run_id == "B"], "2026-10-02")
  inp <- DBI::dbGetQuery(conn, sprintf(
    "SELECT run_id, table_name, row_count::int AS n FROM %s.log_input
      ORDER BY run_id, table_name", dst))
  expect_identical(paste(inp$run_id, inp$table_name, inp$n),
                   c("A streams 1", "B streams 20", "C falls 4", "C streams 3"))

  # Copying the same rows again changes nothing (a consolidate re-run).
  expect_identical(stage("log", cols_log, "run_id"), 0L)
  expect_identical(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int n FROM %s.log", dst))$n,
    4L)
})
