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
  cl <- "run_id, watershed_group_code, table_name, row_count"
  expect_identical(sql, c(
    paste0("CREATE TEMP TABLE consolidate_in ON COMMIT DROP AS SELECT ", cl,
           " FROM s.log_input WITH NO DATA;"),
    paste0("\\copy consolidate_in (", cl, ") FROM '/tmp/x.tsv'"),
    paste0("DELETE FROM s.log_input d USING consolidate_in s",
           " WHERE (d.run_id, d.table_name) = (s.run_id, s.table_name);"),
    paste0("INSERT INTO s.log_input (", cl, ") SELECT ", cl,
           " FROM consolidate_in;")))
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

test_that("the bucket DELETE reaches persist tables only", {
  e <- source_consolidate()
  sql <- e$consolidate_dest_delete_sql("s",
    c("log", "log_input", "log_recompute", "streams", "streams_habitat_bt"),
    c("ADMS", "BULK"))
  expect_identical(sql, c(
    "DELETE FROM s.streams WHERE watershed_group_code IN ('ADMS', 'BULK')",
    "DELETE FROM s.streams_habitat_bt WHERE watershed_group_code IN ('ADMS', 'BULK')"))
  expect_identical(e$consolidate_dest_delete_sql("s", "log", "ADMS"),
                   character(0))
})

test_that("stage 2 loads a log table in one transaction, a persist table by COPY", {
  e <- source_consolidate()
  sqlf <- withr::local_tempfile(fileext = ".sql")
  cmd <- e$consolidate_stage2_cmd("s", "log", c("run_id", "host"), "/tmp/x.tsv",
                                  sqlf)
  expect_match(cmd, "psql -X -v ON_ERROR_STOP=1 -1 -f ", fixed = TRUE)
  expect_match(paste(readLines(sqlf), collapse = "\n"),
               "WHERE (d.run_id) = (s.run_id);", fixed = TRUE)
  sqlf2 <- withr::local_tempfile(fileext = ".sql")
  cmd <- e$consolidate_stage2_cmd("s", "streams", c("id_segment", "geom"),
                                  "/tmp/x.tsv", sqlf2)
  expect_match(cmd, "psql -X -v ON_ERROR_STOP=1 -c \"COPY s.streams (id_segment, geom) FROM STDIN\" < ", fixed = TRUE)
  expect_false(file.exists(sqlf2))
})

test_that("a group whose destination log is newer refuses the source", {
  e <- source_consolidate()
  dest <- data.frame(watershed_group_code = c("ADMS", "BULK", "DUNC", "KOTL"),
                     newest = c(100, 200, 300, 400))
  src <- data.frame(watershed_group_code = c("ADMS", "BULK", "DUNC", "NEWW"),
                    newest = c(100, 250, 299, 1))
  # ADMS same build, BULK older here: fine. DUNC newer here, KOTL logged here
  # and not on the source: refused. NEWW has no row here: fine.
  expect_identical(e$consolidate_newer_on_dest(dest, src), c("DUNC", "KOTL"))
  expect_identical(
    e$consolidate_newer_on_dest(dest[0, ], src), character(0))
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
  cols_log <- c("run_id", "watershed_group_code", "date_start", "date_end")
  cols_in <- c("run_id", "watershed_group_code", "table_name", "row_count")
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
  # Without -1 the script fails closed: ON COMMIT DROP under autocommit drops
  # the temp table before \copy, so nothing is deleted or added.
  tsv0 <- withr::local_tempfile(fileext = ".tsv")
  writeLines("Z\tADMS\t2026-01-01\t\\N", tsv0)
  sql0 <- withr::local_tempfile(fileext = ".sql")
  writeLines(e$consolidate_history_sql(dst, "log", cols_log, "run_id", tsv0),
             sql0)
  res0 <- run_psql(c("-X", "-v", "ON_ERROR_STOP=1", "-f", shQuote(sql0)))
  expect_false(is.null(attr(res0, "status")))
  expect_identical(
    DBI::dbGetQuery(conn, sprintf("SELECT count(*)::int n FROM %s.log", dst))$n,
    3L)

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

# -- Beside a dispatcher that is writing (link#369) ------------------------

test_that("the copy check counts the bucket's rows only", {
  e <- source_consolidate()
  sql <- e$consolidate_bucket_count_sql("s", c("streams", "log"), c("ADMS", "BULK"))
  expect_identical(sql, paste0(
    "SELECT ((SELECT count(*) FROM s.streams WHERE watershed_group_code IN ('ADMS', 'BULK'))",
    " + (SELECT count(*) FROM s.log WHERE watershed_group_code IN ('ADMS', 'BULK')))::bigint AS n"))
})

test_that("the bucket count ignores another group's delete (live)", {
  e <- source_consolidate()
  conn <- skip_if_no_db()
  sc <- paste0("lnk_test_consol_cnt_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc)))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", sc))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.t (watershed_group_code text)", sc))
  DBI::dbExecute(conn, sprintf(
    paste("INSERT INTO %s.t SELECT 'ADMS' FROM generate_series(1, 3)",
          "UNION ALL SELECT 'OKAN' FROM generate_series(1, 50)"), sc))
  sql <- e$consolidate_bucket_count_sql(sc, "t", "ADMS")
  pre <- as.numeric(DBI::dbGetQuery(conn, sql)$n)
  # The dispatcher replaces its own group meanwhile: a whole-table count
  # would drop by 50 and fail a good copy of ADMS.
  DBI::dbExecute(conn, sprintf("DELETE FROM %s.t WHERE watershed_group_code = 'OKAN'", sc))
  DBI::dbExecute(conn, sprintf("INSERT INTO %s.t VALUES ('ADMS')", sc))
  expect_identical(pre, 3)
  expect_gt(as.numeric(DBI::dbGetQuery(conn, sql)$n), pre)
})

test_that("a destination missing link's persist tables refuses the source", {
  e <- source_consolidate()
  # An image's leftovers seen in every 2026 consolidate log: not link's.
  leftovers <- c("streams_bt", "streams_ch", "streams_habitat", "streams_v2")
  expect_identical(e$consolidate_missing_persist(leftovers), character(0))
  # A habitat table for a species outside the run's config is a leftover too.
  expect_identical(
    e$consolidate_missing_persist(c("streams", "streams_habitat_ko", "streams_v2",
                                    "barriers", "streams_mapping_code")),
    c("streams", "barriers", "streams_mapping_code"))
})

test_that("a backup that fails stops, and one that works names its file (live)", {
  e <- source_consolidate()
  conn <- skip_if_no_db()
  skip_if(!nzchar(Sys.which("pg_dump")), "pg_dump not on PATH")
  info <- DBI::dbGetInfo(conn)
  skip_if(!identical(as.character(info$port), "5432") ||
            !info$host %in% c("localhost", "127.0.0.1"),
          "not the local docker fwapg the dump reads")
  d <- withr::local_tempdir()
  absent <- paste0("lnk_test_absent_", Sys.getpid())
  expect_error(suppressMessages(
    e$schema_consolidate_backup(absent, file.path(d, "a.dump"))),
    "pg_dump of lnk_test_absent_[0-9]+ failed")

  sc <- paste0("lnk_test_consol_bak_", Sys.getpid())
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", sc))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc)))
  DBI::dbExecute(conn, sprintf("CREATE TABLE %s.t AS SELECT 1 AS x", sc))
  p <- file.path(d, "b.dump")
  expect_identical(suppressMessages(e$schema_consolidate_backup(sc, p)), p)
  expect_gt(file.size(p), 0)
})

# -- An ssh that exits 0 whatever the remote command returned (link#376) ----
# Tailscale SSH to macOS does this. Every remote call goes through
# consolidate_remote(), which reads the status the remote shell prints.

# A stub ssh on PATH: runs the remote command (its last argument) locally,
# then exits with `exit_with` whatever that command returned.
stub_ssh <- function(env = parent.frame(), exit_with = 0L, run = TRUE) {
  d <- withr::local_tempdir(.local_envir = env)
  body <- if (run) "sh -c \"$last\"" else ":"
  writeLines(c("#!/bin/sh", 'for a in "$@"; do last="$a"; done', body,
               sprintf("exit %d", exit_with)), file.path(d, "ssh"))
  Sys.chmod(file.path(d, "ssh"), "755")
  withr::local_envvar(PATH = paste(d, Sys.getenv("PATH"), sep = ":"),
                      .local_envir = env)
  d
}

test_that("a failed remote command fails even when ssh exits 0", {
  e <- source_consolidate()
  stub_ssh()
  r <- e$consolidate_remote("h", "echo partial; exit 3")
  expect_identical(r$rc, 3L)
  expect_identical(r$out, "partial")
  r <- e$consolidate_remote("h", "echo 'A|1'; echo 'B|2'")
  expect_identical(r$rc, 0L)
  expect_identical(r$out, c("A|1", "B|2"))
})

test_that("a status the remote shell never printed is a failure", {
  e <- source_consolidate()
  # The session ran nothing it could report (dropped, or killed), and ssh
  # still exited 0: no trailer is never read as success.
  stub_ssh(run = FALSE)
  expect_identical(e$consolidate_remote("h", "true")$rc, 255L)
})

test_that("ssh's own failure wins over anything printed", {
  e <- source_consolidate()
  stub_ssh(exit_with = 255L)
  expect_identical(e$consolidate_remote("h", "true")$rc, 255L)
})

test_that("a copy to a file keeps the data clean of the trailer", {
  e <- source_consolidate()
  stub_ssh()
  f <- withr::local_tempfile(fileext = ".tsv")
  r <- e$consolidate_remote("h", "printf 'a\\tb\\n'; echo oops >&2; exit 2",
                            stdout_path = f)
  expect_identical(r$rc, 2L)
  expect_identical(readLines(f), "a\tb")
  expect_identical(r$err, "oops")
  r <- e$consolidate_remote("h", "printf 'a\\tb\\n'", stdout_path = f)
  expect_identical(r$rc, 0L)
  expect_identical(readLines(f), "a\tb")
})

test_that("the remote command's own quotes survive the round trip", {
  e <- source_consolidate()
  stub_ssh()
  r <- e$consolidate_remote("h", "printf '%s\\n' \"it's\" 'A','B'")
  expect_identical(r$rc, 0L)
  expect_identical(r$out, c("it's", "A,B"))
})

test_that("schema_consolidate reaches a source only through consolidate_remote", {
  e <- source_consolidate()
  body <- paste(deparse(body(e$schema_consolidate)), collapse = "\n")
  # A raw ssh call there would trust ssh's exit status again.
  expect_no_match(body, "ssh '", fixed = TRUE)
  expect_match(body, "consolidate_remote(", fixed = TRUE)
})

test_that("a load is counted from psql's COPY tag, never assumed", {
  e <- source_consolidate()
  expect_identical(e$consolidate_copy_count("COPY 12"), 12L)
  expect_identical(e$consolidate_copy_count("COPY 0"), 0L)
  # No tag, or anything else: unknown, which never equals what was sent.
  expect_identical(e$consolidate_copy_count(character()), NA_integer_)
  expect_identical(e$consolidate_copy_count(c("COPY 1", "COPY 2")), NA_integer_)
  expect_identical(e$consolidate_copy_count("ERROR: x"), NA_integer_)
})

test_that("a persist table's load is checked against what was sent", {
  e <- source_consolidate()
  body <- paste(deparse(body(e$schema_consolidate)), collapse = "\n")
  expect_match(body, "consolidate_copy_count(dest_out)", fixed = TRUE)
  expect_match(body, "copy_count", fixed = TRUE)
})

test_that("consolidate takes link's tables only, never a schema's primitives", {
  e <- source_consolidate()
  # What `fresh` held on 2026-10-24: persist, log, primitives and reference.
  fresh <- c("barrier_overrides", "barriers", "crossings_vw_bcfp", "log",
             "log_input", "log_recompute", "modelled_stream_crossings", "streams",
             "streams_access", "streams_habitat_bt", "streams_habitat_ch",
             "streams_mapping_code", "streams_vw_bcfp", "streams_habitat",
             "streams_v2")
  expect_identical(e$consolidate_link_tables(fresh), c(
    "barrier_overrides", "barriers", "log", "log_input", "log_recompute",
    "streams", "streams_access", "streams_habitat_bt", "streams_habitat_ch",
    "streams_mapping_code"))
})
