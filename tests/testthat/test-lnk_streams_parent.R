# lnk_streams_parent(): each full segment's largest-overlap minimal parent (#444).

sp_log_ddl <- function(schema) {
  sprintf(
    "CREATE TABLE %s.log (
       run_id text PRIMARY KEY, watershed_group_code varchar(4),
       date_start timestamptz, date_end timestamptz, run_uid text,
       config_hash text, link_sha text, link_dirty boolean, fresh_sha text,
       fresh_dirty boolean, token_cut text, token_acc text, token_grad text,
       token_flow text, species text[])", schema
  )
}

sp_streams_ddl <- function(schema) {
  sprintf(
    "CREATE TABLE %s.streams (
       id_segment integer, watershed_group_code varchar(4),
       blue_line_key integer, downstream_route_measure double precision,
       upstream_route_measure double precision, gradient double precision,
       length_metre double precision,
       PRIMARY KEY (id_segment, watershed_group_code))", schema
  )
}

sp_insert_streams <- function(conn, schema, rows) {
  vals <- sprintf(
    "(%d, '%s', %d, %.6f, %.6f, %.6f, %.6f)",
    rows$id, rows$wsg, rows$blk, rows$dm, rows$um, rows$grad,
    rows$um - rows$dm
  )
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams (id_segment, watershed_group_code, blue_line_key,
       downstream_route_measure, upstream_route_measure, gradient, length_metre)
     VALUES %s", schema, paste(vals, collapse = ", ")
  ))
}

sp_insert_log <- function(conn, schema, run_id, wsg = "TEST", cut = "cut-min",
                          open = FALSE) {
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.log VALUES ('%s', '%s', now() - interval '1 hour', %s,
       'uid-%s', 'hash-%s', 'sha', FALSE, 'fsha', FALSE, '%s', 'acc-v5',
       'grad-seg', 'q-fwapg', '{BT,CH}')",
    schema, run_id, wsg, if (open) "NULL" else "now()", schema, schema, cut
  ))
}

# Two lines. Line 1: minimal cut at 100 (overshooting 4 mm, as FWA does); the
# full side cuts 0.6 m above it, so its segment 2 straddles. Line 2: the full
# side cuts exactly at the minimal cut, and segment 6's 3 mm overlap with the
# minimal segment below is a sliver.
sp_fixture <- function(conn) {
  base <- paste0("zz_test444_", Sys.getpid())
  full <- paste0(base, "_f")
  minimal <- paste0(base, "_m")
  for (s in c(full, minimal)) {
    DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", s))
    DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
    DBI::dbExecute(conn, sp_streams_ddl(s))
    DBI::dbExecute(conn, sp_log_ddl(s))
  }
  sp_insert_streams(conn, minimal, data.frame(
    id = 1:4, wsg = "TEST", blk = c(1L, 1L, 2L, 2L),
    dm = c(0, 100, 0, 50), um = c(100.004, 250, 50.003, 80),
    grad = c(0.01, 0.05, 0.02, 0.03)
  ))
  sp_insert_streams(conn, full, data.frame(
    id = 1:7, wsg = "TEST", blk = c(1L, 1L, 1L, 1L, 2L, 2L, 2L),
    dm = c(0, 40, 100.6, 180, 0, 50, 65), um = c(40, 100.6, 180, 250, 50.003, 65, 80),
    grad = 0.04
  ))
  sp_insert_log(conn, minimal, "m-run", cut = "cut-min")
  sp_insert_log(conn, full, "f-run", cut = "cut-full-top")
  list(full = full, minimal = minimal)
}

test_that("each full segment gets its largest-overlap minimal parent", {
  conn <- skip_if_no_db()
  s <- sp_fixture(conn)
  withr::defer(for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x)))

  out <- suppressMessages(lnk_streams_parent(conn, "TEST",
    schema = s$full,
    schema_minimal = s$minimal
  ))
  expect_equal(out$n_full, 7)
  expect_equal(out$n_minimal, 4)
  expect_equal(out$n_straddle, 1)
  expect_equal(out$max_straddle_m, 0.596, tolerance = 1e-9)

  p <- DBI::dbGetQuery(conn, sprintf(
    "SELECT * FROM %s.streams_parent ORDER BY id_segment", s$full
  ))
  expect_equal(nrow(p), 7L)
  expect_equal(p$id_segment_minimal, c(1L, 1L, 2L, 2L, 3L, 4L, 4L))
  expect_equal(p$gradient_minimal, c(0.01, 0.01, 0.05, 0.05, 0.02, 0.03, 0.03))
  expect_equal(p$length_minimal[1], 100.004, tolerance = 1e-9)
  # Segment 2 straddles the minimal cut at 100 by 0.6 m (less FWA's 4 mm).
  expect_equal(p$overlap_m[2], 60.004, tolerance = 1e-9)
  expect_equal(p$straddle_m[2], 0.596, tolerance = 1e-9)
  # Segment 6's 3 mm overlap with minimal segment 3 is a sliver, dropped.
  expect_equal(p$overlap_m[6], 15, tolerance = 1e-9)
  expect_equal(p$straddle_m[6], 0, tolerance = 1e-9)
  # Both sides' km are covered: overlap + straddle is each full segment's length.
  len <- DBI::dbGetQuery(conn, sprintf(
    "SELECT length_metre FROM %s.streams ORDER BY id_segment", s$full
  ))$length_metre
  expect_equal(p$overlap_m + p$straddle_m, len, tolerance = 1e-9)
  # Provenance.
  expect_true(all(p$schema_minimal == s$minimal))
  expect_true(all(p$run_id_minimal == "m-run"))
  expect_true(all(p$run_uid_minimal == paste0("uid-", s$minimal)))
  expect_true(all(p$config_hash_minimal == paste0("hash-", s$minimal)))
  expect_true(all(p$link_sha_minimal == "sha"))
  expect_true(all(p$run_id_full == "f-run"))
  expect_false(anyNA(p$built_at))
})

test_that("a second call replaces the group's rows and leaves other groups alone", {
  conn <- skip_if_no_db()
  s <- sp_fixture(conn)
  withr::defer(for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x)))

  suppressMessages(lnk_streams_parent(conn, "TEST", s$full, s$minimal))
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.streams_parent (id_segment, watershed_group_code,
       id_segment_minimal, overlap_m, straddle_m, schema_minimal, run_id_minimal,
       run_id_full) VALUES (1, 'OTHR', 1, 1, 0, 'x', 'x', 'x')", s$full
  ))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.streams SET gradient = 0.09 WHERE id_segment = 1",
    s$minimal
  ))
  suppressMessages(lnk_streams_parent(conn, "TEST", s$full, s$minimal))
  p <- DBI::dbGetQuery(conn, sprintf(
    "SELECT watershed_group_code, count(*) AS n, max(gradient_minimal) FILTER (
       WHERE id_segment_minimal = 1) AS g1
       FROM %s.streams_parent GROUP BY 1 ORDER BY 1", s$full
  ))
  expect_equal(p$watershed_group_code, c("OTHR", "TEST"))
  expect_equal(as.integer(p$n), c(1L, 7L))
  expect_equal(p$g1[2], 0.09)
})

test_that("a minimal cut with no full cut near it is refused", {
  conn <- skip_if_no_db()
  s <- sp_fixture(conn)
  withr::defer(for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x)))
  # Move the full cut 0.6 m above the minimal cut at 100 to 2 m above it.
  DBI::dbExecute(conn, sprintf(
    "UPDATE %1$s.streams SET upstream_route_measure = 102, length_metre = 62
      WHERE id_segment = 2", s$full
  ))
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.streams SET downstream_route_measure = 102, length_metre = 78
      WHERE id_segment = 3", s$full
  ))
  expect_error(
    suppressMessages(lnk_streams_parent(conn, "TEST", s$full, s$minimal)),
    "1 minimal cut.*no full cut within 1.01 m"
  )
  # Refused before the table is created, so it does not exist.
  expect_false(DBI::dbExistsTable(conn, DBI::Id(schema = s$full, table = "streams_parent")))
})

test_that("an open build is refused, on either side", {
  conn <- skip_if_no_db()
  s <- sp_fixture(conn)
  withr::defer(for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x)))
  sp_insert_log(conn, s$minimal, "m-run-2", open = TRUE)
  DBI::dbExecute(conn, sprintf(
    "UPDATE %s.log SET date_start = now() WHERE run_id = 'm-run-2'", s$minimal
  ))
  expect_error(
    suppressMessages(lnk_streams_parent(conn, "TEST", s$full, s$minimal)),
    "newest build of TEST in .*is open"
  )
  expect_error(
    suppressMessages(lnk_streams_parent(conn, "NONE", s$full, s$minimal)),
    "no build of NONE"
  )
})

test_that("a failed insert leaves the group's old rows in place", {
  conn <- skip_if_no_db()
  s <- sp_fixture(conn)
  withr::defer(for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x)))
  suppressMessages(lnk_streams_parent(conn, "TEST", s$full, s$minimal))
  before <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, built_at FROM %s.streams_parent ORDER BY 1", s$full
  ))
  # A full segment shorter than the sliver floor gets no piece, so the insert
  # would leave it out.
  sp_insert_streams(conn, s$full, data.frame(
    id = 8L, wsg = "TEST", blk = 2L, dm = 80, um = 80.005, grad = 0.04
  ))
  expect_error(
    suppressMessages(lnk_streams_parent(conn, "TEST", s$full, s$minimal)),
    "7 rows for 8 full segments"
  )
  after <- DBI::dbGetQuery(conn, sprintf(
    "SELECT id_segment, built_at FROM %s.streams_parent ORDER BY 1", s$full
  ))
  expect_identical(after, before)
})

test_that("a schema is not paired with itself, and arguments are checked", {
  expect_error(
    lnk_streams_parent(fake_conn(), "TEST", "fresh_default", "fresh_default"),
    "two different schemas"
  )
  expect_error(lnk_streams_parent(fake_conn(), "test", "a", "b"), "one watershed group code")
  expect_error(lnk_streams_parent(fake_conn(), "TEST", "a;drop", "b"), "schema")
})

test_that("the table's DDL carries the columns, key and group index", {
  sql <- capture_write(.lnk_streams_parent_create(fake_conn(), "fresh_default"))
  joined <- paste(sql, collapse = "\n")
  expect_match(joined, "CREATE TABLE IF NOT EXISTS fresh_default\\.streams_parent")
  expect_match(joined, "PRIMARY KEY \\(id_segment, watershed_group_code\\)")
  for (col in names(cols_streams_parent)) expect_match(joined, paste0("\\b", col, " "))
  expect_match(
    joined,
    "CREATE INDEX IF NOT EXISTS streams_parent_wsg_idx ON fresh_default\\.streams_parent \\(watershed_group_code\\)"
  )
  # Already there: not re-issued.
  sql2 <- capture_write(.lnk_streams_parent_create(fake_conn(), "fresh_default"),
    query_result = data.frame(indexname = "streams_parent_wsg_idx")
  )
  expect_false(any(grepl("CREATE INDEX", sql2)))
})

test_that("lnk_persist_init() does not create streams_parent", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )
  cfg <- lnk_config("default")
  with_mocked_bindings(
    dbGetQuery = function(conn, sql) data.frame(),
    .package = "DBI",
    lnk_persist_init("mock-conn", cfg, species = c("BT", "CH"))
  )
  expect_true(any(grepl("CREATE TABLE IF NOT EXISTS fresh\\.streams ", captured)))
  expect_false(any(grepl("streams_parent", captured)))
})

test_that("a build re-modelled since the caller judged it is refused", {
  conn <- skip_if_no_db()
  s <- sp_fixture(conn)
  withr::defer(for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x)))
  expect_no_error(suppressMessages(lnk_streams_parent(
    conn, "TEST", s$full, s$minimal,
    run_id_full = "f-run", run_id_minimal = "m-run"
  )))
  expect_error(
    suppressMessages(lnk_streams_parent(
      conn, "TEST", s$full, s$minimal,
      run_id_full = "f-run", run_id_minimal = "m-old"
    )),
    "newest minimal build of TEST is m-run, not the judged m-old"
  )
  expect_error(
    suppressMessages(lnk_streams_parent(
      conn, "TEST", s$full, s$minimal,
      run_id_full = "f-old"
    )),
    "newest full build of TEST is f-run"
  )
})
