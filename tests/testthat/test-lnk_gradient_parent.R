# The parent gradient (#463): pipeline: gradient: source: parent reads each
# full segment's minimal parent's gradient from <schema_full>.streams_parent.

test_that("a gradient setting is checked when the manifest loads", {
  chk <- link:::.lnk_gradient_check
  ok <- list(source = "parent", minimal_config = "default_minimal",
             schema_full = "fresh_default")
  expect_identical(chk(ok), ok)
  expect_identical(chk(list(source = "segment")), list(source = "segment"))
  expect_error(chk("parent"), "must be a map")
  expect_error(chk(list(source = "fwa")), "source must be segment or parent")
  expect_error(chk(c(ok, list(other = 1))), "unknown key\\(s\\) other")
  expect_error(chk(list(source = "segment", schema_full = "x")),
               "source segment takes no other key")
  expect_error(chk(ok[c("source", "schema_full")]), "needs minimal_config")
  expect_error(chk(ok[c("source", "minimal_config")]), "needs schema_full")
  expect_error(chk(modifyList(ok, list(schema_full = "Fresh_Default"))),
               "schema_full must be one plain lower-case schema name")
  expect_error(chk(modifyList(ok, list(schema_minimal = "a;b"))),
               "schema_minimal must be one plain lower-case schema name")
  expect_error(chk(modifyList(ok, list(minimal_config = c("a", "b")))),
               "minimal_config must be one bundle name")

  # lnk_config() runs it: a bundle with a bad setting does not load.
  dir <- withr::local_tempdir()
  writeLines(c("name: bad_gradient", "extends: default", "pipeline:",
               "  schema: zz_bad", "  gradient:", "    source: sideways"),
             file.path(dir, "config.yaml"))
  expect_error(lnk_config(dir), "source must be segment or parent")
})

test_that("only default_parent resolves grad-parent, and only its grad differs from default", {
  par <- lnk_vocabulary_resolve(lnk_config("default_parent"))
  def <- lnk_vocabulary_resolve(lnk_config("default"))
  expect_identical(par[["grad"]], "grad-parent")
  others <- c("cut", "acc", "flow")
  expect_identical(par[others], def[others])
  expect_identical(link:::.lnk_gradient_source(lnk_config("default")), "segment")
  expect_identical(link:::.lnk_gradient_parent_cut("grad-parent"), "cut-min")
  expect_error(link:::.lnk_gradient_parent_cut("grad-seg"), "names no parent cut")
})

test_that("a parent setting whose minimal config is not a cut-min sibling refuses", {
  cfg <- lnk_config("default_parent")
  with_min <- function(m, ...) {
    cfg$pipeline$gradient <- utils::modifyList(cfg$pipeline$gradient,
                                               list(minimal_config = m, ...))
    cfg
  }
  # default is cut-full-top: gradient=parent;parent_cut=cut-full-top has no row.
  expect_error(lnk_vocabulary_resolve(with_min("default")),
               "no grad token .* has the spec\n  gradient=parent;parent_cut=cut-full-top")
  expect_error(lnk_vocabulary_resolve(with_min("bcfishpass")), "another acc spec")
  expect_error(lnk_vocabulary_resolve(with_min("default_tuned")), "another flow spec")
  expect_error(lnk_vocabulary_resolve(with_min("default_parent")),
               "itself reads a parent gradient")
  expect_error(link:::.lnk_gradient_parent(with_min("default_minimal",
                                                    schema_minimal = "elsewhere")),
               "schema_minimal elsewhere is not minimal_config")
  same <- with_min("default_minimal", schema_minimal = "fresh_default_minimal")
  expect_identical(link:::.lnk_gradient_parent(same)$schema_minimal,
                   "fresh_default_minimal")
})

# Live fixture: a full network of three segments on one line, a minimal one of
# two, their log rows and the parent join between them.
gp_fixture <- function(conn) {
  base <- paste0("zz_test463_", Sys.getpid())
  s <- list(full = paste0(base, "_f"), minimal = paste0(base, "_m"),
            persist = paste0(base, "_p"), work = paste0(base, "_w"))
  for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x))
  for (x in c(s$full, s$minimal)) {
    DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", x))
    gp_sql(
      conn,
      "CREATE TABLE %s.streams (
         id_segment integer, watershed_group_code varchar(4),
         blue_line_key integer, downstream_route_measure double precision,
         upstream_route_measure double precision, gradient double precision,
         length_metre double precision,
         PRIMARY KEY (id_segment, watershed_group_code))",
      x
    )
    gp_sql(
      conn,
      "CREATE TABLE %s.log (
         run_id text PRIMARY KEY, watershed_group_code varchar(4),
         date_start timestamptz, date_end timestamptz, run_uid text,
         config_hash text, link_sha text, link_dirty boolean, fresh_sha text,
         fresh_dirty boolean, token_cut text, token_acc text, token_grad text,
         token_flow text, species text[])",
      x
    )
  }
  ins <- function(schema, dm, um, grad) {
    vals <- sprintf("(%d, 'TEST', 1, %.6f, %.6f, %.6f, %.6f)", seq_along(dm),
                    dm, um, grad, um - dm)
    gp_sql(conn, "INSERT INTO %s.streams VALUES %s", schema, paste(vals, collapse = ", "))
  }
  ins(s$minimal, c(0, 100), c(100, 250), c(0.01, 0.05))
  ins(s$full, c(0, 40, 100.6), c(40, 100.6, 250), c(0.04, 0.04, 0.04))
  gp_log(conn, s$minimal, "m-run", "cut-min")
  gp_log(conn, s$full, "f-run", "cut-full-top")
  suppressMessages(link::lnk_streams_parent(conn, "TEST", s$full, s$minimal))
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s$work))
  # Working streams as fresh leaves them: gradient generated from the row.
  gp_sql(
    conn,
    "CREATE TABLE %s.streams (
       id_segment integer PRIMARY KEY, blue_line_key integer,
       downstream_route_measure double precision,
       upstream_route_measure double precision, g0 double precision,
       gradient double precision GENERATED ALWAYS AS (g0 * 2) STORED)",
    s$work
  )
  gp_sql(
    conn,
    "INSERT INTO %s.streams VALUES (11, 1, 0, 40, 0.1), (12, 1, 40.0004, 100.6, 0.1),
       (13, 1, 100.6, 249.9995, 0.1)",
    s$work
  )
  s
}

gp_sql <- function(conn, ...) DBI::dbExecute(conn, sprintf(...))

gp_log <- function(conn, schema, run_id, cut, open = FALSE, age = "1 hour") {
  gp_sql(
    conn,
    "INSERT INTO %s.log VALUES ('%s', 'TEST', now() - interval '%s', %s,
       'uid', 'hash', 'sha', FALSE, 'fsha', FALSE, '%s', 'acc-v5', 'grad-seg',
       'q-fwapg', '{BT,CH}')",
    schema, run_id, age, if (open) "NULL" else "now() - interval '1 minute'", cut
  )
}

gp_generated <- function(conn, schema) {
  sql <- sprintf(
    "SELECT is_generated FROM information_schema.columns
      WHERE table_schema = '%s' AND table_name = 'streams' AND column_name = 'gradient'",
    schema
  )
  DBI::dbGetQuery(conn, sql)$is_generated
}

gp_drop <- function(conn, s) {
  for (x in s) DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", x))
}

# default_parent pointed at the fixture's schemas.
gp_cfg <- function(s) {
  cfg <- lnk_config("default_parent")
  cfg$pipeline$schema <- s$persist
  cfg
}

gp_tokens <- c(cut = "cut-full-top", acc = "acc-v5", grad = "grad-parent",
               flow = "q-fwapg")

gp_mock <- function(s, env = parent.frame()) {
  parent <- function(cfg) {
    list(minimal_cfg = NULL, schema_full = s$full, schema_minimal = s$minimal)
  }
  testthat::local_mocked_bindings(.lnk_gradient_parent = parent, .env = env)
}

test_that("a parent build reads rows joined from the newest builds, and names them", {
  conn <- skip_if_no_db()
  s <- gp_fixture(conn)
  withr::defer(gp_drop(conn, s))
  gp_mock(s)
  j <- link:::.lnk_gradient_parent_judge(conn, gp_cfg(s), "TEST", gp_tokens)
  expect_identical(j$run_id_full, "f-run")
  expect_identical(j$run_id_minimal, "m-run")
  expect_equal(j$n_rows, 3)
  expect_match(j$note, sprintf("%s.streams_parent \\(run_id_full f-run, run_id_minimal m-run in %s\\)",
                               s$full, s$minimal))
})

test_that("each way a parent read can be stale or mismatched refuses", {
  conn <- skip_if_no_db()
  s <- gp_fixture(conn)
  withr::defer(gp_drop(conn, s))
  gp_mock(s)
  judge <- function(cfg = gp_cfg(s), tokens = gp_tokens) {
    link:::.lnk_gradient_parent_judge(conn, cfg, "TEST", tokens)
  }
  sql <- function(...) DBI::dbExecute(conn, sprintf(...))
  # Each case changes the fixture, checks the refusal, and undoes the change.
  expect_refusal <- function(change, undo, pattern) {
    change()
    expect_error(judge(), pattern)
    undo()
    expect_silent(judge())
  }
  expect_refusal(function() gp_log(conn, s$full, "f-run2", "cut-full-top", age = "1 minute"),
                 function() sql("DELETE FROM %s.log WHERE run_id = 'f-run2'", s$full),
                 "full re-modelled since the join")
  expect_refusal(function() gp_log(conn, s$minimal, "m-run2", "cut-min", age = "1 minute"),
                 function() sql("DELETE FROM %s.log WHERE run_id = 'm-run2'", s$minimal),
                 "minimal re-modelled since the join")
  expect_refusal(function() gp_log(conn, s$full, "f-open", "cut-full-top", open = TRUE, age = "1 minute"),
                 function() sql("DELETE FROM %s.log WHERE run_id = 'f-open'", s$full),
                 "is open")
  expect_refusal(function() sql("UPDATE %s.log SET link_dirty = TRUE", s$minimal),
                 function() sql("UPDATE %s.log SET link_dirty = FALSE", s$minimal),
                 "dirty or unknown tree")
  expect_refusal(function() sql("UPDATE %s.log SET fresh_sha = 'other'", s$minimal),
                 function() sql("UPDATE %s.log SET fresh_sha = 'fsha'", s$minimal),
                 "fresh_sha differs")
  expect_refusal(function() sql("UPDATE %s.log SET species = '{BT}'", s$minimal),
                 function() sql("UPDATE %s.log SET species = '{BT,CH}'", s$minimal),
                 "species differ")
  expect_refusal(function() sql("UPDATE %s.log SET token_cut = 'cut-full-ssf-all'", s$full),
                 function() sql("UPDATE %s.log SET token_cut = 'cut-full-top'", s$full),
                 "has token_cut cut-full-ssf-all, not cut-full-top")
  expect_refusal(function() sql("UPDATE %s.log SET token_cut = 'cut-full-top'", s$minimal),
                 function() sql("UPDATE %s.log SET token_cut = 'cut-min'", s$minimal),
                 "has token_cut cut-full-top, not cut-min")
  expect_refusal(function() sql("UPDATE %s.log SET token_acc = 'acc-v4'", s$minimal),
                 function() sql("UPDATE %s.log SET token_acc = 'acc-v5'", s$minimal),
                 "has token_acc acc-v4, not acc-v5")
  expect_refusal(function() sql("UPDATE %s.log SET token_grad = 'grad-parent'", s$full),
                 function() sql("UPDATE %s.log SET token_grad = 'grad-seg'", s$full),
                 "has token_grad grad-parent, not grad-seg")
  expect_refusal(function() sql("UPDATE %s.streams_parent SET overlap_m = overlap_m + 1 WHERE id_segment = 2", s$full),
                 function() sql("UPDATE %s.streams_parent SET overlap_m = overlap_m - 1 WHERE id_segment = 2", s$full),
                 "1 rows off the segment's length")
  expect_refusal(function() sql("UPDATE %s.streams_parent SET schema_minimal = 'elsewhere'", s$full),
                 function() sql("UPDATE %s.streams_parent SET schema_minimal = '%s'", s$full, s$minimal),
                 "joined on another minimal schema: elsewhere")
  expect_refusal(function() sql("UPDATE %s.streams SET id_segment = 9 WHERE id_segment = 3", s$full),
                 function() sql("UPDATE %s.streams SET id_segment = 3 WHERE id_segment = 9", s$full),
                 "1 segments without a row; 1 rows without a segment")

  # The persist schema is never one the parents are read from.
  cfg <- gp_cfg(s)
  cfg$pipeline$schema <- s$full
  expect_error(judge(cfg), "is the full schema the parent gradient is read from")
  cfg$pipeline$schema <- s$minimal
  expect_error(judge(cfg), "is the minimal schema")
  testthat::local_mocked_bindings(.lnk_gradient_parent = function(cfg) {
    list(minimal_cfg = NULL, schema_full = s$full, schema_minimal = s$full)
  })
  expect_error(judge(), "schema_full and the minimal schema are both")
})

test_that("a parent read refuses when the table is absent", {
  conn <- skip_if_no_db()
  s <- gp_fixture(conn)
  withr::defer(gp_drop(conn, s))
  gp_mock(s)
  DBI::dbExecute(conn, sprintf("DROP TABLE %s.streams_parent", s$full))
  expect_error(link:::.lnk_gradient_parent_judge(conn, gp_cfg(s), "TEST", gp_tokens),
               "the table does not exist")
})

test_that("the parent gradient replaces a generated working gradient, segment for segment", {
  conn <- skip_if_no_db()
  s <- gp_fixture(conn)
  withr::defer(gp_drop(conn, s))
  gp_mock(s)
  j <- link:::.lnk_gradient_parent_judge(conn, gp_cfg(s), "TEST", gp_tokens)
  n <- suppressMessages(link:::.lnk_gradient_parent_apply(conn, "TEST", s$work, j))
  expect_equal(n, 3)
  sql_got <- sprintf("SELECT id_segment, gradient FROM %s.streams ORDER BY id_segment", s$work)
  got <- DBI::dbGetQuery(conn, sql_got)
  expect_equal(got$gradient, c(0.01, 0.01, 0.05))
  expect_identical(gp_generated(conn, s$work), "NEVER")
})

test_that("a build whose segments are not the full build's is refused before the swap", {
  conn <- skip_if_no_db()
  s <- gp_fixture(conn)
  withr::defer(gp_drop(conn, s))
  gp_mock(s)
  j <- link:::.lnk_gradient_parent_judge(conn, gp_cfg(s), "TEST", gp_tokens)
  apply <- function() link:::.lnk_gradient_parent_apply(conn, "TEST", s$work, j)
  sql <- function(...) DBI::dbExecute(conn, sprintf(...))
  untouched <- function() {
    expect_identical(gp_generated(conn, s$work), "ALWAYS")
  }
  # A start 2 mm off: segment 12 matches none, and full segment 2 none.
  sql("UPDATE %s.streams SET downstream_route_measure = 40.002 WHERE id_segment = 12", s$work)
  expect_error(apply(), "1 working segments match none; 1 .* segments match none")
  untouched()
  sql("UPDATE %s.streams SET downstream_route_measure = 40 WHERE id_segment = 12", s$work)
  # An extra segment: the counts differ.
  sql("INSERT INTO %s.streams VALUES (14, 1, 250, 260, 0.1)", s$work)
  expect_error(apply(), "4 working segments against 3")
  untouched()
  sql("DELETE FROM %s.streams WHERE id_segment = 14", s$work)
  # Two working segments at one position, none at another: equal counts, and
  # one full segment matched twice.
  sql("UPDATE %s.streams SET downstream_route_measure = 0, upstream_route_measure = 40
        WHERE id_segment = 12", s$work)
  expect_error(apply(), "1 [a-z0-9_]+ segments match none; a segment matches more than one")
  untouched()
  sql("UPDATE %s.streams SET downstream_route_measure = 40, upstream_route_measure = 100.6
        WHERE id_segment = 12", s$work)
  # A full segment with no parent row.
  sql("DELETE FROM %s.streams_parent WHERE id_segment = 3", s$full)
  expect_error(apply(), "1 .* segments have no parent row")
  untouched()
})

test_that("the parent table's state is counted per group, as --verify and a build read it", {
  conn <- skip_if_no_db()
  s <- gp_fixture(conn)
  withr::defer(gp_drop(conn, s))
  st <- link:::.lnk_streams_parent_state(conn, s$full)
  expect_equal(nrow(st), 1L)
  expect_identical(st$wsg, "TEST")
  expect_equal(unlist(st[c("n_segments", "n_no_row", "n_rows", "n_no_segment", "n_length_off")]),
               c(n_segments = 3, n_no_row = 0, n_rows = 3, n_no_segment = 0, n_length_off = 0))
  expect_identical(st$run_id_full, "f-run")
  expect_identical(st$run_id_minimal, "m-run")
  expect_identical(st$schema_minimal, s$minimal)
  # A group asked for that the schema does not hold reads zeros, not no row.
  st2 <- link:::.lnk_streams_parent_state(conn, s$full, c("TEST", "NONE"))
  expect_equal(st2$n_segments[st2$wsg == "NONE"], 0)
  expect_equal(st2$n_rows[st2$wsg == "NONE"], 0)
  DBI::dbExecute(conn, sprintf("DELETE FROM %s.streams_parent WHERE id_segment = 1", s$full))
  DBI::dbExecute(conn, sprintf("UPDATE %s.streams_parent SET straddle_m = 5 WHERE id_segment = 2", s$full))
  st3 <- link:::.lnk_streams_parent_state(conn, s$full)
  expect_equal(st3$n_no_row, 1)
  expect_equal(st3$n_length_off, 1)
  expect_null(link:::.lnk_streams_parent_state(conn, s$minimal))
})
