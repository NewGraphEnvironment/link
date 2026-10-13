# link#265 -- source-artifact identity for the DB primitives.

# --- the dictionary ---------------------------------------------------------

test_that("every primitive declares a kind and an artifact URL", {
  p <- .lnk_input_primitives()
  expect_true(all(c("kind", "url") %in% names(p)))
  expect_true(all(p$kind %in% c("object", "api", "derived")))
  expect_false(any(is.na(p$url) | !nzchar(p$url)))
  # Every object is a fetch from the bchamp store; that is what makes a
  # HEAD's version id meaningful.
  obj <- p$url[p$kind == "object"]
  expect_true(all(startsWith(obj, "https://nrs.objectstore.gov.bc.ca/bchamp/")))
  # A derived table names the SQL that builds it, not a fetch.
  expect_false(any(grepl("^https?://", p$url[p$kind == "derived"])))
  expect_identical(p$table_name[p$kind == "derived"],
                   "whse_basemapping.fwa_stream_networks_order_parent")
  expect_setequal(p$table_name[p$kind == "api"],
                  c("whse_fish.pscis_assessment_svw", "cabd.dams"))
})

test_that("the stream network expands to one artifact per watershed group", {
  p <- .lnk_input_primitives()
  e <- .lnk_artifact_expand(p, c("BULK", "MORR"))
  s <- e$url[e$table_name == "whse_basemapping.fwa_stream_networks_sp"]
  expect_identical(s, c(
    "https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_sp/BULK.parquet",
    "https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_sp/MORR.parquet"))
  expect_identical(nrow(e), nrow(p) + 1L)
  # No groups: the template has nothing to expand into, so it drops out
  # rather than emitting a URL with a literal {wsg} in it.
  e0 <- .lnk_artifact_expand(p)
  expect_false(any(grepl("{wsg}", e0$url, fixed = TRUE)))
  expect_identical(nrow(e0), nrow(p) - 1L)
})

test_that("the DDL keys on host, table and url, and constrains the labels", {
  sql <- character()
  local_mocked_bindings(.lnk_db_execute = function(conn, s) {
    sql <<- c(sql, s)
    invisible(conn)
  })
  .lnk_artifact_create(structure(list(), class = "DBIConnection"))
  ddl <- grep("CREATE TABLE IF NOT EXISTS fresh.log_source_artifact", sql,
              value = TRUE)
  expect_length(ddl, 1L)
  expect_match(ddl, "PRIMARY KEY (host, table_name, url)", fixed = TRUE)
  expect_match(ddl, "recorded_by IN ('loader', 'probe')", fixed = TRUE)
  expect_match(ddl, "kind IN ('object', 'api', 'derived')", fixed = TRUE)
  # The align pass must not try to ADD a CHECK through ADD COLUMN.
  alters <- grep("ADD COLUMN IF NOT EXISTS", sql, value = TRUE)
  expect_length(alters, length(cols_source_artifact))
  expect_false(any(grepl("CHECK|NOT NULL", alters)))
})


# --- HEAD -------------------------------------------------------------------

fake_response <- function(status, headers = list()) {
  structure(list(status_code = status, headers = headers),
            class = "response")
}

test_that(".lnk_artifact_head reads the three identity handles", {
  local_mocked_bindings(
    HEAD = function(url, ...) fake_response(200L, list(
      `x-amz-version-id` = "1776306159523",
      etag = "\"da5ba121842036c6f494a1eef0ac41f4-18\"",
      `last-modified` = "Thu, 16 Apr 2026 02:22:39 GMT")),
    status_code = function(r) r$status_code,
    headers = function(r) r$headers,
    .package = "httr")
  h <- .lnk_artifact_head("https://example.invalid/x.parquet")
  expect_identical(h$version_id, "1776306159523")
  expect_identical(h$etag, "da5ba121842036c6f494a1eef0ac41f4-18")
  expect_equal(h$last_modified,
               as.POSIXct("2026-04-16 02:22:39", tz = "UTC"))
  expect_identical(h$status, 200L)
  expect_true(is.na(h$notes))
})

test_that(".lnk_artifact_head records an honest NULL on 404, never errors", {
  local_mocked_bindings(
    HEAD = function(url, ...) fake_response(404L),
    status_code = function(r) r$status_code,
    .package = "httr")
  h <- .lnk_artifact_head("https://example.invalid/missing.parquet")
  expect_true(is.na(h$version_id))
  expect_true(is.na(h$etag))
  expect_identical(h$status, 404L)
  expect_match(h$notes, "HTTP 404")
})

test_that(".lnk_artifact_head records an honest NULL when unreachable", {
  local_mocked_bindings(
    HEAD = function(url, ...) stop("Could not resolve host: example.invalid"),
    .package = "httr")
  expect_no_error(h <- .lnk_artifact_head("https://example.invalid/x"))
  expect_true(is.na(h$version_id))
  expect_true(is.na(h$status))
  expect_match(h$notes, "Could not resolve host")
})


# --- record -----------------------------------------------------------------

capture_record <- function(expr, exists = TRUE) {
  sql <- character()
  local_mocked_bindings(
    .lnk_db_execute = function(conn, s) {
      sql <<- c(sql, s)
      invisible(conn)
    },
    .lnk_artifact_exists = function(conn, tables) rep(exists, length(tables)),
    .lnk_artifact_count = function(conn, a) {
      if (exists) rep(32541, nrow(a)) else rep(NA_real_, nrow(a))
    },
    .env = parent.frame()
  )
  testthat::with_mocked_bindings(
    dbQuoteLiteral = function(conn, x, ...) {
      paste0("'", gsub("'", "''", as.character(x)), "'")
    },
    .package = "DBI",
    force(expr))
  sql
}

prim_url <- function(tbl) {
  p <- .lnk_input_primitives()
  p$url[p$table_name == tbl]
}

test_that("a probe never overwrites a loader row", {
  fc <- structure(list(), class = "DBIConnection")
  sql <- capture_record(lnk_artifact_record(fc, data.frame(
    table_name = "whse_basemapping.fwa_obstructions_sp",
    url = prim_url("whse_basemapping.fwa_obstructions_sp"),
    version_id = "1776306166790"), recorded_by = "probe", host = "m1"))
  ins <- grep("INSERT INTO fresh.log_source_artifact", sql, value = TRUE)
  expect_length(ins, 1L)
  expect_match(ins, "ON CONFLICT (host, table_name, url) DO UPDATE",
               fixed = TRUE)
  expect_match(ins, "WHERE log_source_artifact.recorded_by = 'probe'",
               fixed = TRUE)
  expect_match(ins, "OR EXCLUDED.recorded_by = 'loader'", fixed = TRUE)
  expect_match(ins, "'probe'", fixed = TRUE)
  expect_match(ins, "'1776306166790'", fixed = TRUE)
  # n_rows is a bigint literal, never scientific notation.
  expect_match(ins, "'32541'::bigint", fixed = TRUE)
})

test_that("the probe-vs-loader rule holds in a real database", {
  conn <- skip_if_no_db()
  host <- paste0("test265-", Sys.getpid())
  withr::defer(DBI::dbExecute(conn, sprintf(
    "DELETE FROM fresh.log_source_artifact WHERE host = %s",
    DBI::dbQuoteLiteral(conn, host))))
  tbl <- "whse_basemapping.fwa_obstructions_sp"
  one <- function(v) data.frame(table_name = tbl, url = prim_url(tbl),
                                version_id = v)
  get <- function() DBI::dbGetQuery(conn, sprintf(
    "SELECT version_id, recorded_by FROM fresh.log_source_artifact
      WHERE host = %s", DBI::dbQuoteLiteral(conn, host)))

  lnk_artifact_record(conn, one("L1"), "loader", host = host)
  lnk_artifact_record(conn, one("P1"), "probe", host = host)
  expect_identical(get()$version_id, "L1")       # probe did not clobber
  lnk_artifact_record(conn, one("L2"), "loader", host = host)
  expect_identical(get()$version_id, "L2")       # loader replaces loader
  DBI::dbExecute(conn, sprintf(
    "UPDATE fresh.log_source_artifact SET recorded_by = 'probe'
      WHERE host = %s", DBI::dbQuoteLiteral(conn, host)))
  lnk_artifact_record(conn, one("P2"), "probe", host = host)
  expect_identical(get()$version_id, "P2")       # probe replaces probe
})

test_that("a URL the dictionary does not know stops the record", {
  fc <- structure(list(), class = "DBIConnection")
  expect_error(capture_record(lnk_artifact_record(fc, data.frame(
    table_name = "cabd.dams", url = "https://example.invalid/dams.geojson"),
    host = "m1")), "does not match the primitives dictionary")
  expect_error(capture_record(lnk_artifact_record(fc, data.frame(
    table_name = "whse_basemapping.fwa_obstacles_sp", url = "x"),
    host = "m1")), "not a primitive")
  # The {wsg} slot takes a group code and nothing else.
  sp <- prim_url("whse_basemapping.fwa_stream_networks_sp")
  expect_no_error(capture_record(lnk_artifact_record(fc, data.frame(
    table_name = "whse_basemapping.fwa_stream_networks_sp",
    url = sub("{wsg}", "BULK", sp, fixed = TRUE)), host = "m1")))
  expect_error(capture_record(lnk_artifact_record(fc, data.frame(
    table_name = "whse_basemapping.fwa_stream_networks_sp",
    url = sub("{wsg}", "../x", sp, fixed = TRUE)), host = "m1")),
    "does not match")
})

test_that("an absent primitive is recorded with NULL rows and a note", {
  fc <- structure(list(), class = "DBIConnection")
  sql <- capture_record(lnk_artifact_record(fc, data.frame(
    table_name = "cabd.dams", url = prim_url("cabd.dams")), host = "m1"),
    exists = FALSE)
  ins <- grep("INSERT INTO", sql, value = TRUE)
  expect_match(ins, "NULL::bigint", fixed = TRUE)
  expect_match(ins, "table absent at record time", fixed = TRUE)
})


# --- probe ------------------------------------------------------------------

test_that("lnk_artifact_probe HEADs objects only and survives a dead URL", {
  heads <- character()
  recorded <- NULL
  local_mocked_bindings(
    .lnk_artifact_wsgs = function(conn) c("BULK", "MORR"),
    .lnk_artifact_head = function(url, ...) {
      heads <<- c(heads, url)
      if (grepl("MORR", url)) {
        data.frame(version_id = NA_character_, etag = NA_character_,
                   last_modified = as.POSIXct(NA, tz = "UTC"),
                   status = NA_integer_, notes = "HEAD failed: timeout",
                   stringsAsFactors = FALSE)
      } else {
        data.frame(version_id = "v1", etag = "e1",
                   last_modified = as.POSIXct("2026-04-16", tz = "UTC"),
                   status = 200L, notes = NA_character_,
                   stringsAsFactors = FALSE)
      }
    },
    lnk_artifact_record = function(conn, artifacts, recorded_by, host) {
      recorded <<- list(a = artifacts, by = recorded_by)
      invisible(artifacts)
    })
  expect_message(a <- lnk_artifact_probe(structure(list(),
                                                   class = "DBIConnection")),
                 "1 without a version id")
  expect_identical(recorded$by, "probe")
  # 8 FWA primitives, the stream network expanded to 2 groups.
  expect_identical(nrow(a), 9L)
  # The derived table is recorded but never HEADed.
  expect_false(any(grepl("order_parent", heads)))
  op <- a[a$table_name == "whse_basemapping.fwa_stream_networks_order_parent", ]
  expect_identical(op$kind, "derived")
  expect_true(is.na(op$version_id))
  # Only fwapg primitives by default; the snapshot four are the loader's.
  expect_false(any(a$table_name %in% c("cabd.dams", "bcfishobs.observations")))
  dead <- a[grepl("MORR", a$url), ]
  expect_true(is.na(dead$version_id))
  expect_match(dead$notes, "timeout")
})


# --- each run carries its artifacts (log_input) ------------------------------

test_that("log_input names the artifact each primitive is read from", {
  sql <- capture_write(.lnk_log_inputs(fake_conn(), "s", "run-1", "BULK"))
  ins <- grep("INSERT INTO s\\.log_input", sql, value = TRUE)
  expect_length(ins, 1L)
  for (col in c("artifact_url", "artifact_kind", "artifact_version_id",
                "artifact_etag", "artifact_last_modified",
                "artifact_recorded_by")) {
    expect_match(ins, col, fixed = TRUE)
  }
  # The stream network is read from the run's own group's object.
  expect_match(ins, "fwa_stream_networks_sp/BULK.parquet", fixed = TRUE)
  expect_no_match(ins, "{wsg}", fixed = TRUE)
})

test_that("log_input leaves identity NULL when no artifact table exists", {
  # capture_write's dbGetQuery returns no rows, so the existence probe reads
  # "absent": the row is still written, with NULL identity, not skipped.
  sql <- capture_write(.lnk_log_inputs(fake_conn(), "s", "run-1", "BULK"))
  ins <- grep("INSERT INTO s\\.log_input", sql, value = TRUE)
  expect_no_match(ins, "log_source_artifact", fixed = TRUE)
  expect_match(ins, "NULL::text AS artifact_version_id", fixed = TRUE)
})

test_that("log_input joins this host's artifact rows when they exist", {
  sql <- capture_write(.lnk_log_inputs(fake_conn(), "s", "run-1", "BULK"),
                       probe_rows = 1L)
  ins <- grep("INSERT INTO s\\.log_input", sql, value = TRUE)
  expect_match(ins, "LEFT JOIN fresh.log_source_artifact a", fixed = TRUE)
  expect_match(ins, "a.url = p.url", fixed = TRUE)
  expect_match(ins, sprintf("a.host = '%s'", .lnk_host()), fixed = TRUE)
})

test_that("log_input carries identity from a real artifact table", {
  conn <- skip_if_no_db()
  host <- paste0("test265li-", Sys.getpid())
  schema <- paste0("zz_test265_", Sys.getpid())
  withr::defer({
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema))
    DBI::dbExecute(conn, sprintf(
      "DELETE FROM fresh.log_source_artifact WHERE host = %s",
      DBI::dbQuoteLiteral(conn, host)))
  })
  withr::local_envvar(LNK_HOST_ALIAS = host)
  p <- .lnk_input_primitives()
  sp <- "whse_basemapping.fwa_stream_networks_sp"
  lnk_artifact_record(conn, data.frame(
    table_name = sp,
    url = sub("{wsg}", "BULK", p$url[p$table_name == sp], fixed = TRUE),
    version_id = "v-bulk", etag = "e-bulk"), recorded_by = "probe")
  .lnk_log_create_tables(conn, schema)
  expect_true(.lnk_log_inputs(conn, schema, "run-265", "BULK"))
  li <- DBI::dbGetQuery(conn, sprintf(
    "SELECT table_name, artifact_url, artifact_kind, artifact_version_id,
            artifact_recorded_by
       FROM %s.log_input WHERE run_id = 'run-265'", schema))
  expect_identical(nrow(li), nrow(p))   # every primitive, recorded or not
  row <- li[li$table_name == sp, ]
  expect_identical(row$artifact_version_id, "v-bulk")
  expect_identical(row$artifact_recorded_by, "probe")
  # Unrecorded primitives keep a row, with NULL identity and the URL the run
  # expected to read.
  dams <- li[li$table_name == "cabd.dams", ]
  expect_true(is.na(dams$artifact_recorded_by))
  expect_identical(dams$artifact_kind, "api")
  expect_identical(dams$artifact_url, p$url[p$table_name == "cabd.dams"])
  # The real table name, which link#271 fixed, is fingerprinted.
  obs <- DBI::dbGetQuery(conn, sprintf(
    "SELECT row_count FROM %s.log_input
      WHERE run_id = 'run-265'
        AND table_name = 'whse_basemapping.fwa_obstructions_sp'", schema))
  expect_false(is.na(obs$row_count))
})


# --- review fixes -------------------------------------------------------------

test_that("a round row count and a quoted ETag record as one canonical form", {
  local_mocked_bindings(
    .lnk_artifact_count = function(conn, a) rep(1e5, nrow(a)))
  fc <- structure(list(), class = "DBIConnection")
  sql <- character()
  local_mocked_bindings(
    .lnk_db_execute = function(conn, s) {
      sql <<- c(sql, s)
      invisible(conn)
    },
    .lnk_artifact_exists = function(conn, tables) rep(TRUE, length(tables)))
  with_mocked_bindings(
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    lnk_artifact_record(fc, data.frame(
      table_name = "cabd.dams", url = prim_url("cabd.dams"),
      etag = "\"abc-18\""), host = "m1"))
  ins <- grep("INSERT INTO", sql, value = TRUE)
  # as.character(1e5) is "1e+05", which Postgres refuses as a bigint.
  expect_match(ins, "'100000'::bigint", fixed = TRUE)
  expect_match(ins, "'abc-18'", fixed = TRUE)
  expect_no_match(ins, "\"abc-18\"", fixed = TRUE)
})

test_that("the probe stops asking after consecutive failures", {
  calls <- 0L
  local_mocked_bindings(
    .lnk_artifact_wsgs = function(conn) c("AAAA", "BBBB", "CCCC", "DDDD"),
    .lnk_artifact_head = function(url, ...) {
      calls <<- calls + 1L
      .lnk_artifact_head_na("HEAD failed: timeout")
    },
    lnk_artifact_record = function(conn, artifacts, recorded_by, host) {
      invisible(artifacts)
    })
  a <- suppressMessages(lnk_artifact_probe(
    structure(list(), class = "DBIConnection"),
    tables = "whse_basemapping.fwa_stream_networks_sp", max_fail = 2L))
  expect_identical(calls, 2L)
  expect_identical(nrow(a), 4L)
  expect_true(all(is.na(a$version_id)))
  expect_identical(sum(grepl("not probed", a$notes)), 2L)
})

test_that("HTTP dates parse element by element, NA beside a value", {
  # httr::parse_http_date(c(<date>, NA)) is NA for BOTH elements; that blanked
  # last_modified on the first live snapshot, whose api rows carry no date.
  x <- c("Tue, 22 Sep 2026 06:07:10 GMT", NA, "")
  got <- .lnk_http_date(x)
  expect_equal(got[1], as.POSIXct("2026-09-22 06:07:10", tz = "UTC"))
  expect_true(all(is.na(got[2:3])))
  expect_identical(attr(got, "tzone"), "UTC")
})
