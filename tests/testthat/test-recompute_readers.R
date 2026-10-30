# data-raw/recompute_readers.R: the groups outside a partial run that read it
# (link#274).
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the helper is absent and
# these skip; devtools::test() from the source tree runs them.
#
# LNK_TEST_READERS_LIB points the tests at a mutant copy of the helper.

rr_env <- function() {
  p <- Sys.getenv("LNK_TEST_READERS_LIB")
  if (!nzchar(p)) {
    p <- normalizePath(testthat::test_path("..", "..", "data-raw", "recompute_readers.R"),
                       mustWork = FALSE)
  }
  testthat::skip_if_not(file.exists(p), "data-raw/recompute_readers.R absent")
  e <- new.env()
  sys.source(p, envir = e)
  e
}

rr_deps <- function(...) {
  x <- matrix(c(...), ncol = 3, byrow = TRUE)
  data.frame(wsg = x[, 1], rule = x[, 2], dep = x[, 3])
}

# A reader whose every fact passes, and the expected stamp it is checked against.
rr_expect <- list(config_hash = "sha256:c", fresh_sha = "f1", fresh_version = "0.47.0",
                  crate_version = "0.8.0", fwapg_sha = "w1")
rr_fact <- function(wsg, ...) {
  x <- list(
    wsg = wsg, has_log = TRUE, open = FALSE, config_hash = "sha256:c",
    fresh_sha = "f1", fresh_version = "0.47.0", crate_version = "0.8.0", fwapg_sha = "w1",
    link_dirty = FALSE, fresh_dirty = FALSE,
    link_sha = "abc", path_changed = 0L, downstream = "pass"
  )
  x[names(list(...))] <- list(...)
  as.data.frame(x, stringsAsFactors = FALSE)
}

test_that("a held group outside the run that reads a rebuilt group is a reader", {
  e <- rr_env()
  deps <- rr_deps("GGGG", "line", "DDDD", "HHHH", "line", "DDDD", "KKKK", "line", "XXXX")
  r <- e$readers_outside(deps, run = "DDDD", rebuilt = "DDDD", held = c("DDDD", "GGGG", "HHHH", "KKKK"))
  expect_identical(r$wsg, c("GGGG", "HHHH"))
  expect_identical(r$reads, c("DDDD", "DDDD"))
})

test_that("a group the schema does not hold is never a reader", {
  e <- rr_env()
  deps <- rr_deps("GGGG", "line", "DDDD", "HHHH", "line", "DDDD")
  r <- e$readers_outside(deps, run = "DDDD", rebuilt = "DDDD", held = c("DDDD", "GGGG"))
  expect_identical(r$wsg, "GGGG")
})

test_that("the run's own groups, its SKIPs and its log-row groups are never readers", {
  e <- rr_env()
  deps <- rr_deps("SSSS", "line", "DDDD", "LLLL", "line", "DDDD", "GGGG", "line", "DDDD", "DDDD", "line", "SSSS")
  # S is a SKIP of the run, L a --wsgs= leftover with a log row of the run_uid:
  # the caller passes both in `run`.
  r <- e$readers_outside(deps, run = c("DDDD", "SSSS", "LLLL"), rebuilt = "DDDD",
                         held = c("DDDD", "SSSS", "LLLL", "GGGG"))
  expect_identical(r$wsg, "GGGG")
})

test_that("only a rebuilt group makes a reader: a SKIP's readers are not readers", {
  e <- rr_env()
  deps <- rr_deps("GGGG", "line", "SSSS")
  r <- e$readers_outside(deps, run = c("DDDD", "SSSS"), rebuilt = "DDDD", held = c("DDDD", "SSSS", "GGGG"))
  expect_identical(nrow(r), 0L)
})

test_that("only line-rule rows count", {
  e <- rr_env()
  deps <- rr_deps("GGGG", "owner", "DDDD", "HHHH", "closure", "DDDD")
  r <- e$readers_outside(deps, run = "DDDD", rebuilt = "DDDD", held = c("DDDD", "GGGG", "HHHH"))
  expect_identical(nrow(r), 0L)
})

test_that("one hop: a reader of a reader is not a reader", {
  e <- rr_env()
  # G reads D (in the run); H reads only G (outside it). The recompute writes
  # G's access, never its barrier rows, so H reads nothing that moved.
  deps <- rr_deps("GGGG", "line", "DDDD", "HHHH", "line", "GGGG")
  r <- e$readers_outside(deps, run = "DDDD", rebuilt = "DDDD", held = c("DDDD", "GGGG", "HHHH"))
  expect_identical(r$wsg, "GGGG")
})

test_that("a reader that holds no segment of the path, only a co-held row, is found", {
  e <- rr_env()
  p <- normalizePath(testthat::test_path("..", "..", "data-raw", "logs",
                                         "recompute_early_374", "deps.tsv"), mustWork = FALSE)
  testthat::skip_if_not(file.exists(p), "recompute_early_374/deps.tsv absent")
  deps <- utils::read.delim(p, colClasses = "character", quote = "")
  # KOTL reads KOTR only through rows KOTR holds on KOTL's own segments (three
  # gradient rows on blue line 356570348 in fresh_default, each downstream of a
  # KOTL segment: data-raw/logs/partial_readers_274/coheld.csv). KOTR has no
  # segment on that path, so the owner rule misses the pair and the line rule
  # holds it.
  line <- deps[deps$rule == "line", ]
  owner <- deps[deps$rule == "owner", ]
  expect_true(any(line$wsg == "KOTL" & line$dep == "KOTR"))
  expect_false(any(owner$wsg == "KOTL" & owner$dep == "KOTR"))
  r <- e$readers_outside(deps, run = "KOTR", rebuilt = "KOTR", held = c("KOTL", "KOTR"))
  expect_true("KOTL" %in% r$wsg)
  # The owner rule alone would miss it: the reason the line rule is the one.
  r_owner <- e$readers_outside(transform(owner, rule = "line"), run = "KOTR",
                               rebuilt = "KOTR", held = c("KOTL", "KOTR"))
  expect_false("KOTL" %in% r_owner$wsg)
})

test_that("a compatible reader is recomputed", {
  e <- rr_env()
  r <- data.frame(wsg = "GGGG", reads = "DDDD")
  out <- e$readers_classify(r, missing = character(), facts = rr_fact("GGGG"), expect = rr_expect)
  expect_identical(out$class, "recompute")
  expect_identical(out$reason, "")
})

test_that("a reader of a run group that did not finish waits, whatever else holds", {
  e <- rr_env()
  r <- data.frame(wsg = c("GGGG", "HHHH"), reads = c("DDDD,EEEE", "DDDD"))
  f <- rbind(rr_fact("GGGG", config_hash = "sha256:old"), rr_fact("HHHH"))
  out <- e$readers_classify(r, missing = "EEEE", facts = f, expect = rr_expect)
  expect_identical(out$class, c("waiting", "recompute"))
  expect_match(out$reason[1], "reads_unfinished:EEEE", fixed = TRUE)
})

test_that("each fact the rule tests refuses on its own", {
  e <- rr_env()
  cases <- list(
    no_log = list(has_log = FALSE),
    newest_build_open = list(open = TRUE),
    newest_build_open_unknown = list(open = NA),
    config_differs = list(config_hash = "sha256:old"),
    fresh_differs = list(fresh_sha = "f0"),
    fresh_version_differs = list(fresh_version = "0.46.0"),
    crate_differs = list(crate_version = NA_character_),
    fwapg_differs = list(fwapg_sha = "w0"),
    link_dirty = list(link_dirty = TRUE),
    link_dirty_unknown = list(link_dirty = NA),
    fresh_dirty = list(fresh_dirty = TRUE),
    fresh_dirty_unknown = list(fresh_dirty = NA),
    sha_unresolvable = list(path_changed = NA_integer_),
    path_changed = list(path_changed = 3L),
    downstream_unpersisted = list(downstream = "warn"),
    downstream_unchecked = list(downstream = NA_character_)
  )
  for (nm in names(cases)) {
    f <- do.call(rr_fact, c(list("GGGG"), cases[[nm]]))
    out <- e$readers_classify(data.frame(wsg = "GGGG", reads = "DDDD"), missing = character(),
                              facts = f, expect = rr_expect)
    expect_identical(out$class, "refused", info = nm)
    expect_match(out$reason, sub("_unknown$|_unchecked$", "", nm), info = nm)
  }
})

test_that("a refusal of every reader refuses each, naming why", {
  e <- rr_env()
  r <- data.frame(wsg = c("GGGG", "HHHH"), reads = c("DDDD", "DDDD"))
  f <- rbind(rr_fact("GGGG"), rr_fact("HHHH"))
  out <- e$readers_classify(r, missing = character(), facts = f, expect = rr_expect,
                            refuse_all = "dispatcher_tree_dirty")
  expect_identical(out$class, c("refused", "refused"))
  expect_true(all(grepl("dispatcher_tree_dirty", out$reason)))
})

test_that("a reader with no facts row is refused, not recomputed", {
  e <- rr_env()
  out <- e$readers_classify(data.frame(wsg = "GGGG", reads = "DDDD"), missing = character(),
                            facts = rr_fact("HHHH"), expect = rr_expect)
  expect_identical(out$class, "refused")
  expect_match(out$reason, "no_log")
})

test_that("malformed input fails closed", {
  e <- rr_env()
  expect_error(e$readers_outside(data.frame(a = 1), run = "DDDD", rebuilt = "DDDD", held = "GGGG"))
  expect_error(e$readers_outside(rr_deps("GGGG", "line", "bad"), run = "DDDD", rebuilt = "DDDD",
                                 held = "GGGG"))
  expect_error(e$readers_classify(data.frame(wsg = "GGGG"), missing = character(),
                                  facts = rr_fact("GGGG"), expect = rr_expect))
  expect_error(e$readers_classify(data.frame(wsg = "GGGG", reads = "DDDD"), missing = character(),
                                  facts = rr_fact("GGGG"), expect = list(config_hash = "x")))
})

test_that("no readers gives an empty table with the columns", {
  e <- rr_env()
  r <- e$readers_outside(rr_deps("GGGG", "line", "DDDD"), run = c("DDDD", "GGGG"), rebuilt = "DDDD",
                         held = c("DDDD", "GGGG"))
  out <- e$readers_classify(r, missing = character(), facts = rr_fact("GGGG")[0, ],
                            expect = rr_expect)
  expect_identical(names(out), c("wsg", "class", "reason", "reads"))
  expect_identical(nrow(out), 0L)
})

# The early recompute's audit (data-raw/recompute_audit.R) over a reader the
# final set started: its dependencies in the run are judged like any group's.
rr_audit <- function(conn, reader_start, mode) {
  p <- normalizePath(testthat::test_path("..", "..", "data-raw", "recompute_audit.R"),
                     mustWork = FALSE)
  testthat::skip_if_not(file.exists(p), "data-raw/recompute_audit.R absent")
  sc <- paste0("lnk_test_readers_", Sys.getpid())
  DBI::dbExecute(conn, "SET client_min_messages TO warning")
  DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc))
  link:::.lnk_log_create_tables(conn, sc)
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", sc)))
  uid <- "20261030_000000-0000abcd"
  DBI::dbExecute(conn, sprintf(paste(
    "INSERT INTO %s.log (run_id, watershed_group_code, date_start, date_end, run_uid)",
    "VALUES ('d', 'DDDD', '2026-10-30 01:00+00', '2026-10-30 02:00+00', '%s')"
  ), sc, uid))
  DBI::dbExecute(conn, sprintf(paste(
    "INSERT INTO %s.log_recompute (recompute_id, watershed_group_code, date_start, date_end, run_uid)",
    "VALUES ('rd', 'DDDD', '2026-10-30 02:10+00', '2026-10-30 02:11+00', '%s'),",
    "('rg', 'GGGG', '%s', '2026-10-30 03:00+00', '%s')"
  ), sc, uid, reader_start, uid))
  d <- withr::local_tempdir(.local_envir = parent.frame())
  writeLines(c("wsg\trule\tdep", "GGGG\tline\tDDDD"), file.path(d, "deps.tsv"))
  writeLines(c("wsg\thost\tskip\trun_uid", sprintf("DDDD\tdispatcher\tno\t%s", uid)),
             file.path(d, "run_wsgs.tsv"))
  ep <- as.numeric(as.POSIXct(reader_start, tz = "UTC"))
  writeLines(sprintf("GGGG\t%s %d\t%s\t1", reader_start, ep, mode), file.path(d, "launched.tsv"))
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(
    p, sc, uid, file.path(d, "deps.tsv"), file.path(d, "run_wsgs.tsv"),
    file.path(d, "state.tsv"), file.path(d, "launched.tsv"), file.path(d, "audit.tsv")
  ), stdout = TRUE, stderr = TRUE))
  list(status = attr(out, "status") %||% 0L, out = paste(out, collapse = "\n"),
       tab = utils::read.delim(file.path(d, "audit.tsv"), colClasses = "character"))
}

test_that("the audit passes a reader the final set started after its run group landed", {
  conn <- skip_if_no_db()
  a <- rr_audit(conn, "2026-10-30 02:30:00", "final")
  expect_equal(a$status, 0L, info = a$out)
  expect_identical(a$tab$verdict[a$tab$wsg == "GGGG"], "ok")
})

test_that("the audit catches a reader started before its run group landed", {
  conn <- skip_if_no_db()
  a <- rr_audit(conn, "2026-10-30 01:30:00", "early")
  expect_equal(a$status, 1L, info = a$out)
  expect_identical(a$tab$verdict[a$tab$wsg == "GGGG"], "EARLY")
})
