# data-raw/snapshot_bcfp_lib.sh (link#484, link#459): bc2pg retried and held to
# its rows, then the WFS read directly. Stubs on PATH stand in for bcdata, psql,
# curl, ogr2ogr and sleep; a table "exists" while a state file holds its row
# count. data-raw/ is .Rbuildignore'd, so these skip under R CMD check.
#
# LNK_TEST_SNAPSHOT_LIB points the tests at a mutant copy (proving they fail).

sb_lib <- function() {
  p <- Sys.getenv("LNK_TEST_SNAPSHOT_LIB")
  if (!nzchar(p)) {
    p <- normalizePath(testthat::test_path("..", "..", "data-raw", "snapshot_bcfp_lib.sh"),
                       mustWork = FALSE)
  }
  testthat::skip_if_not(file.exists(p), "data-raw/snapshot_bcfp_lib.sh absent")
  p
}

# `bcdata` answers from plan lines, one per call: `fail`, `zero`, or `ok <rows>`.
# `ogr2ogr` (the WFS fallback) the same, from its own plan. `curl` prints the
# WFS count file's content as numberMatched, or nothing when it is absent.
sb_world <- function(bcdata, ogr = character(), wfs_count = NULL, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  bin <- file.path(d, "bin")
  st <- file.path(d, "state")
  dir.create(bin)
  dir.create(st)
  writeLines(bcdata, file.path(d, "bcdata_plan"))
  writeLines(ogr, file.path(d, "ogr_plan"))
  if (!is.null(wfs_count)) writeLines(wfs_count, file.path(d, "wfs_count"))
  stub <- function(name, body) {
    f <- file.path(bin, name)
    writeLines(c("#!/bin/sh", sprintf("D=%s", shQuote(d)), body), f)
    Sys.chmod(f, "755")
  }
  # Takes the plan's next line; writes the table's state file for ok/zero.
  plan_step <- function(plan, tbl_expr) {
    c(sprintf('n=$(cat "$D/%s.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$D/%s.n"', plan, plan),
      sprintf('step=$(sed -n "${n}p" "$D/%s")', plan),
      sprintf('echo "%s $*" >> "$D/calls"', plan),
      sprintf('t=$(echo %s | tr . _)', tbl_expr),
      'case "$step" in',
      '  ok*) echo "${step#ok }" > "$D/state/$t" ;;',
      '  zero) echo 0 > "$D/state/$t" ;;',
      '  *) rm -f "$D/state/$t"; exit 1 ;;',
      'esac')
  }
  stub("bcdata", plan_step("bcdata_plan", "$2"))
  # ogr2ogr's -nln value is the target table.
  stub("ogr2ogr", c('tgt=""; prev=""; for a in "$@"; do [ "$prev" = "-nln" ] && tgt="$a"; prev="$a"; done',
                    plan_step("ogr_plan", "$tgt")))
  stub("psql", c(
    'q=""; prev=""; for a in "$@"; do [ "$prev" = "-c" ] && q="$a"; prev="$a"; done',
    'case "$q" in',
    '  *to_regclass*) t=$(echo "$q" | sed -n "s/.*to_regclass(.\\([a-z_.]*\\).).*/\\1/p" | tr . _)',
    '                 [ -f "$D/state/$t" ] && echo t || echo f ;;',
    '  *"count(*)"*) t=$(echo "$q" | sed -n "s/.*FROM \\([a-z_.]*\\).*/\\1/p" | tr . _); cat "$D/state/$t" ;;',
    '  *"DROP TABLE"*) t=$(echo "$q" | sed -n "s/.*EXISTS \\([a-z_.]*\\);.*/\\1/p" | tr . _); rm -f "$D/state/$t" ;;',
    'esac'))
  stub("curl", c('echo "curl $*" >> "$D/calls"',
                 '[ -f "$D/wfs_count" ] && printf \'<x numberMatched="%s"/>\' "$(cat "$D/wfs_count")"',
                 'exit 0'))
  stub("sleep", 'echo "sleep $*" >> "$D/calls"')
  d
}

sb_run <- function(d, cmd, bash = "bash") {
  script <- file.path(d, "run.sh")
  writeLines(c("set -euo pipefail", 'PSQL="psql postgresql://x -v ON_ERROR_STOP=1"',
               "DATABASE_URL=postgresql://x", "SNAPSHOT_BCFP_BC2PG_BACKOFF=7",
               sprintf(". %s", shQuote(sb_lib())), cmd), script)
  out <- withr::with_envvar(
    c(PATH = paste(file.path(d, "bin"), Sys.getenv("PATH"), sep = ":")),
    suppressWarnings(system2(bash, script, stdout = TRUE, stderr = TRUE)))
  calls <- if (file.exists(file.path(d, "calls"))) readLines(file.path(d, "calls")) else character()
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L, calls = calls,
       n = function(prefix) sum(startsWith(calls, prefix)))
}

load_cmd <- 'bc2pg_load whse_fish.pscis_remediation_svw && echo "PATH=$SNAP_PATH N=$SNAP_N"'

test_that("bc2pg fails once, then loads: two calls, one backoff", {
  d <- sb_world(c("fail", "ok 177"), wfs_count = "177")
  r <- sb_run(d, load_cmd)
  expect_equal(r$status, 0L)
  expect_identical(r$n("bcdata_plan"), 2L)
  expect_identical(r$calls[startsWith(r$calls, "sleep")], "sleep 7")
  expect_match(r$out, "177 rows on attempt 2 of 3", fixed = TRUE)
  expect_match(r$out, "PATH=bcdata bc2pg N=177", fixed = TRUE)
})

test_that("bc2pg exits 0 with 0 rows, then loads: the row check retries it", {
  d <- sb_world(c("zero", "ok 177"), wfs_count = "177")
  r <- sb_run(d, load_cmd)
  expect_equal(r$status, 0L)
  expect_identical(r$n("bcdata_plan"), 2L)
  expect_match(r$out, "attempt 1 of 3 failed (0 rows)", fixed = TRUE)
})

test_that("first attempt loads: one call, no sleep", {
  d <- sb_world("ok 177", wfs_count = "177")
  r <- sb_run(d, load_cmd)
  expect_equal(r$status, 0L)
  expect_identical(r$n("bcdata_plan"), 1L)
  expect_identical(r$n("sleep"), 0L)
  expect_identical(r$n("ogr_plan"), 0L)
})

test_that("every attempt fails and the WFS fails: non-zero, naming the view and the attempts", {
  d <- sb_world(c("fail", "fail", "fail"), ogr = "fail", wfs_count = "177")
  r <- sb_run(d, load_cmd)
  expect_false(r$status == 0L)
  expect_identical(r$n("bcdata_plan"), 3L)
  expect_match(r$out, "FATAL: bc2pg whse_fish.pscis_remediation_svw: 3 attempts, last: exit 1",
               fixed = TRUE)
  # Backoff grows with the attempt; none after the last.
  expect_identical(r$calls[startsWith(r$calls, "sleep")], c("sleep 7", "sleep 14"))
})

test_that("every attempt exits 0 with 0 rows: the row check, not the exit status, fails it", {
  d <- sb_world(c("zero", "zero", "zero"), ogr = "zero")
  r <- sb_run(d, load_cmd)
  expect_false(r$status == 0L)
  expect_match(r$out, "3 attempts, last: 0 rows", fixed = TRUE)
})

test_that("bc2pg spent, the WFS loads: the fallback path is named", {
  d <- sb_world(c("fail", "fail", "fail"), ogr = "ok 19905", wfs_count = "19905")
  r <- sb_run(d, load_cmd)
  expect_equal(r$status, 0L)
  expect_match(r$out, "PATH=WFS fallback N=19905", fixed = TRUE)
  ogr <- r$calls[startsWith(r$calls, "ogr_plan")]
  expect_length(ogr, 1L)
  # GDAL pages the layer itself, sorted on the key (DataBC's GeoServer pages only
  # with a sort), into a table typed like bc2pg's.
  for (s in c("--config OGR_WFS_PAGING_ALLOWED ON", "GEOMETRY_NAME=geom", "MULTIPOINT",
              "EPSG:3005", "pub:WHSE_FISH.PSCIS_REMEDIATION_SVW", "ORDER BY STREAM_CROSSING_ID")) {
    expect_match(ogr, s, fixed = TRUE)
  }
})

test_that("a table short of the WFS's count is a failed attempt", {
  # 10,000 is the cap an unpaged BC WFS GetFeature answers 200 with.
  d <- sb_world(c("ok 10000", "ok 19905"), wfs_count = "19905")
  r <- sb_run(d, load_cmd)
  expect_equal(r$status, 0L)
  expect_match(r$out, "attempt 1 of 3 failed (10000 rows, the WFS reports 19905)", fixed = TRUE)
})

test_that("a short table stays short when the WFS re-count is unreadable", {
  # First count 19905 against a 10,000-row table; the re-count then fails. The
  # same flakiness that truncates a load can blank the second answer.
  d <- sb_world(c("ok 10000", "ok 10000", "ok 10000"), ogr = "ok 10000")
  # curl answers 19905 once, then nothing.
  writeLines(c("#!/bin/sh", sprintf("D=%s", shQuote(d)),
               'echo "curl $*" >> "$D/calls"',
               'n=$(cat "$D/curl.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$D/curl.n"',
               '[ "$(( n % 2 ))" = 1 ] && printf \'<x numberMatched="19905"/>\'',
               'exit 0'), file.path(d, "bin", "curl"))
  r <- sb_run(d, load_cmd)
  expect_false(r$status == 0L)
  expect_match(r$out, "10000 rows, the WFS reports 19905 (re-count unreadable)", fixed = TRUE)
})

test_that("with no readable WFS count, any rows are whole", {
  d <- sb_world("ok 5")
  r <- sb_run(d, load_cmd)
  expect_equal(r$status, 0L)
  expect_identical(r$n("bcdata_plan"), 1L)
})

test_that("a bad attempts setting refuses rather than loading nothing", {
  d <- sb_world("ok 5")
  r <- sb_run(d, paste("SNAPSHOT_BCFP_BC2PG_ATTEMPTS=0", load_cmd))
  expect_false(r$status == 0L)
  expect_identical(r$n("bcdata_plan"), 0L)
})

test_that("snapshot_bcfp.sh uses only the two-argument --config form", {
  # GDAL 3.8 reads `--config KEY=VALUE` as a datasource name (link#459).
  p <- normalizePath(testthat::test_path("..", "..", "data-raw", "snapshot_bcfp.sh"),
                     mustWork = FALSE)
  skip_if_not(file.exists(p))
  for (f in c(p, sb_lib())) {
    src <- readLines(f)
    expect_false(any(grepl("--config [A-Z_]+=", src)), info = f)
  }
})

test_that("the library parses under macOS /bin/bash 3.2", {
  skip_if_not(file.exists("/bin/bash"))
  out <- suppressWarnings(system2("/bin/bash", c("-n", sb_lib()), stdout = TRUE, stderr = TRUE))
  expect_null(attr(out, "status"))
  d <- sb_world(c("fail", "ok 177"), wfs_count = "177")
  r <- sb_run(d, load_cmd, bash = "/bin/bash")
  expect_equal(r$status, 0L)
})

# ---- cabd_load() (link#494): one column layout whatever GDAL creates ----------

# Stubs for the call's shape: psql logs each -c and each script on stdin, and
# answers the layout query from a file; ogr2ogr logs its arguments.
cabd_world <- function(layout = "ogc_fid,geom", env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  bin <- file.path(d, "bin")
  dir.create(bin)
  writeLines(layout, file.path(d, "layout"))
  stub <- function(name, body) {
    f <- file.path(bin, name)
    writeLines(c("#!/bin/sh", sprintf("D=%s", shQuote(d)), body), f)
    Sys.chmod(f, "755")
  }
  stub("psql", c(
    'q=""; prev=""; for a in "$@"; do [ "$prev" = "-c" ] && q="$a"; prev="$a"; done',
    'if [ -z "$q" ]; then { echo "psql<<"; cat; echo "<<psql"; } >> "$D/calls"; exit 0; fi',
    'echo "psql -c $q" >> "$D/calls"',
    'case "$q" in *string_agg*) cat "$D/layout" ;; esac'))
  stub("ogr2ogr", 'echo "ogr2ogr $*" >> "$D/calls"')
  d
}

cabd_cmd <- "cabd_load https://x/dams OGRGeoJSON cabd.dams cabd.dams_load"

test_that("cabd_load stages the API, then rebuilds the table in one transaction", {
  d <- cabd_world()
  r <- sb_run(d, cabd_cmd)
  expect_equal(r$status, 0L)
  calls <- paste(r$calls, collapse = "\n")
  # The staging table is dropped first and loaded by ogr2ogr; the target is not.
  expect_match(r$calls[1], "psql -c DROP TABLE IF EXISTS cabd.dams_load;", fixed = TRUE)
  ogr <- r$calls[startsWith(r$calls, "ogr2ogr")]
  expect_length(ogr, 1L)
  expect_match(ogr, "-nln cabd.dams_load", fixed = TRUE)
  expect_match(ogr, "https://x/dams OGRGeoJSON", fixed = TRUE)
  expect_false(grepl("OGR_TRUNCATE", ogr, fixed = TRUE))
  # One script: drop without CASCADE, rebuild with the attribute list read from
  # the catalog (no field named in it), key and index, staging dropped, commit.
  s <- sub("(?s).*psql<<\n(.*)\n<<psql.*", "\\1", calls, perl = TRUE)
  expect_match(s, "^BEGIN;", perl = TRUE)
  expect_match(s, "COMMIT;$", perl = TRUE)
  expect_match(s, "DROP TABLE IF EXISTS cabd.dams;", fixed = TRUE)
  expect_false(grepl("CASCADE", s, fixed = TRUE))
  expect_match(s, "attname NOT IN ('ogc_fid', 'geom')", fixed = TRUE)
  expect_match(s, "SELECT ogc_fid, geom, %s FROM cabd.dams_load", fixed = TRUE)
  expect_match(s, "ADD PRIMARY KEY (ogc_fid)", fixed = TRUE)
  expect_match(s, "DROP TABLE cabd.dams_load;", fixed = TRUE)
  expect_false(grepl("cabd_id", s, fixed = TRUE))
})

test_that("cabd_load refuses a table that does not start ogc_fid, geom", {
  d <- cabd_world(layout = "ogc_fid,cabd_id")
  r <- sb_run(d, cabd_cmd)
  expect_false(r$status == 0L)
  expect_match(r$out, "FATAL: cabd.dams loaded with columns starting 'ogc_fid,cabd_id'", fixed = TRUE)
})

test_that("cabd_load fails when ogr2ogr fails, before touching the table", {
  d <- cabd_world()
  writeLines(c("#!/bin/sh", "exit 1"), file.path(d, "bin", "ogr2ogr"))
  r <- sb_run(d, cabd_cmd)
  expect_false(r$status == 0L)
  expect_false(any(grepl("psql<<", r$calls, fixed = TRUE)))
})

# Live: the local docker fwapg (writable), a schema of the test's own, and the
# real psql. Skips with no database or no psql / ogr2ogr on PATH.
cabd_live <- function(env = parent.frame()) {
  conn <- tryCatch(
    DBI::dbConnect(RPostgres::Postgres(), dbname = "fwapg", host = "localhost",
                   port = 5432L, user = "postgres", password = "postgres"),
    error = function(e) NULL)
  if (is.null(conn)) testthat::skip("no local fwapg on localhost:5432")
  withr::defer(DBI::dbDisconnect(conn), envir = env)
  for (b in c("psql", "ogr2ogr")) {
    if (!nzchar(Sys.which(b))) testthat::skip(paste(b, "not on PATH"))
  }
  s <- paste0("zz_lnk_test_cabd494_", Sys.getpid())
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", s))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA %s CASCADE", s)), envir = env)
  list(conn = conn, schema = s, url = "postgresql://postgres:postgres@localhost:5432/fwapg")
}

cabd_live_run <- function(lv, cmd, path = NULL) {
  script <- tempfile(fileext = ".sh")
  on.exit(unlink(script))
  writeLines(c("set -euo pipefail", sprintf("DATABASE_URL=%s", lv$url),
               'PSQL="psql $DATABASE_URL -v ON_ERROR_STOP=1"',
               sprintf(". %s", shQuote(sb_lib())), cmd), script)
  envs <- if (is.null(path)) character() else c(PATH = paste(path, Sys.getenv("PATH"), sep = ":"))
  out <- withr::with_envvar(envs, suppressWarnings(
    system2("bash", script, stdout = TRUE, stderr = TRUE)))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

cabd_shape <- function(lv, tbl) {
  cols <- DBI::dbGetQuery(lv$conn, sprintf(
    "SELECT attname, format_type(atttypid, atttypmod) AS type FROM pg_attribute
      WHERE attrelid = '%s'::regclass AND attnum > 0 AND NOT attisdropped ORDER BY attnum", tbl))
  list(cols = paste(cols$attname, cols$type, sep = ":"),
       md5 = link:::.lnk_table_content_md5(lv$conn, tbl),
       fid = DBI::dbGetQuery(lv$conn, sprintf(
         "SELECT count(*)::int AS n, min(ogc_fid) AS lo, max(ogc_fid) AS hi FROM %s", tbl)))
}

test_that("cabd_load: a geom-last staging table becomes ogc_fid, geom, then the rest in order", {
  lv <- cabd_live()
  # GDAL lays a table out geom-last only on its first load into a database, so
  # an ogr2ogr stub builds that staging table through the real psql.
  bin <- withr::local_tempdir()
  writeLines(c("#!/bin/sh",
               'tgt=""; prev=""; for a in "$@"; do [ "$prev" = "-nln" ] && tgt="$a"; prev="$a"; done',
               sprintf('psql %s -v ON_ERROR_STOP=1 -q -c "CREATE TABLE $tgt (ogc_fid serial PRIMARY KEY, cabd_id varchar, height_m float8, geom geometry(Point, 4326)); INSERT INTO $tgt (cabd_id, height_m, geom) VALUES (\'a1\', 3.5, ST_SetSRID(ST_MakePoint(-123.1, 49.2), 4326)), (\'b2\', NULL, ST_SetSRID(ST_MakePoint(-120.5, 50.7), 4326));"', lv$url)),
             file.path(bin, "ogr2ogr"))
  Sys.chmod(file.path(bin, "ogr2ogr"), "755")
  tbl <- paste0(lv$schema, ".dams")
  r <- cabd_live_run(lv, sprintf("cabd_load src lyr %s %s.dams_load", tbl, lv$schema), path = bin)
  expect_equal(r$status, 0L, info = r$out)
  sh <- cabd_shape(lv, tbl)
  expect_identical(sh$cols, c("ogc_fid:integer", "geom:geometry(Point,4326)",
                              "cabd_id:character varying", "height_m:double precision"))
  expect_identical(sh$fid$n, 2L)
  expect_true(is.na(DBI::dbGetQuery(lv$conn, sprintf("SELECT to_regclass('%s.dams_load') AS x",
                                                     lv$schema))$x))
  idx <- DBI::dbGetQuery(lv$conn, sprintf(
    "SELECT indexname FROM pg_indexes WHERE schemaname = '%s' AND tablename = 'dams' ORDER BY 1",
    lv$schema))$indexname
  expect_identical(idx, c("dams_geom_geom_idx", "dams_pkey"))
})

test_that("cabd_load gives one table from no table, a geom-last one and its own", {
  # In a database GDAL has loaded into before, its own layout is geom second,
  # so the old call passes this test too; the new-host case (GDAL's geom-last
  # first load) is the stub test above. This one holds the rebuild to one table
  # whatever the table it replaces.
  lv <- cabd_live()
  src <- normalizePath(testthat::test_path("fixtures", "cabd_494", "dams.geojson"))
  tbl <- paste0(lv$schema, ".dams")
  cmd <- sprintf("cabd_load %s dams %s %s.dams_load", shQuote(src), tbl, lv$schema)
  r <- cabd_live_run(lv, cmd)
  expect_equal(r$status, 0L, info = r$out)
  first <- cabd_shape(lv, tbl)
  expect_identical(first$cols[1:2], c("ogc_fid:integer", "geom:geometry(Point,4326)"))
  expect_identical(first$fid, data.frame(n = 3L, lo = 1L, hi = 3L))
  # The same dams with geom last, as a new host's first load left them.
  rest <- setdiff(sub(":.*", "", first$cols), c("ogc_fid", "geom"))
  DBI::dbExecute(lv$conn, sprintf("CREATE TABLE %s.last AS SELECT ogc_fid, %s, geom FROM %s",
                                  lv$schema, paste(rest, collapse = ", "), tbl))
  DBI::dbExecute(lv$conn, sprintf("DROP TABLE %s", tbl))
  DBI::dbExecute(lv$conn, sprintf("ALTER TABLE %s.last RENAME TO dams", lv$schema))
  expect_false(identical(link:::.lnk_table_content_md5(lv$conn, tbl), first$md5))
  for (i in 1:2) {
    r <- cabd_live_run(lv, cmd)
    expect_equal(r$status, 0L, info = r$out)
    expect_identical(cabd_shape(lv, tbl), first)
  }
})

test_that("cabd_load refuses, leaving the table, when a view depends on it", {
  lv <- cabd_live()
  src <- normalizePath(testthat::test_path("fixtures", "cabd_494", "dams.geojson"))
  tbl <- paste0(lv$schema, ".dams")
  cmd <- sprintf("cabd_load %s dams %s %s.dams_load", shQuote(src), tbl, lv$schema)
  expect_equal(cabd_live_run(lv, cmd)$status, 0L)
  DBI::dbExecute(lv$conn, sprintf("CREATE VIEW %s.v AS SELECT cabd_id FROM %s", lv$schema, tbl))
  r <- cabd_live_run(lv, cmd)
  expect_false(r$status == 0L)
  expect_match(r$out, "other objects depend on it", fixed = TRUE)
  expect_identical(DBI::dbGetQuery(lv$conn, sprintf("SELECT count(*)::int AS n FROM %s", tbl))$n, 3L)
})
