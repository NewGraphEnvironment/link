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
