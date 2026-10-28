# data-raw/pretest.R: the pre-run gate's pick and verdict (link#372).
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the helper is absent and
# these skip; devtools::test() from the source tree runs them.
#
# LNK_TEST_PRETEST_LIB points the tests at a mutant copy of the helper, and
# LNK_TEST_PRETEST_MAP at a mutant copy of the map (proving they fail).

pt_env <- function() {
  p <- Sys.getenv("LNK_TEST_PRETEST_LIB")
  if (!nzchar(p)) {
    p <- normalizePath(testthat::test_path("..", "..", "data-raw", "pretest.R"), mustWork = FALSE)
  }
  testthat::skip_if_not(file.exists(p), "data-raw/pretest.R absent")
  e <- new.env()
  sys.source(p, envir = e)
  e
}

pt_map_path <- function() {
  p <- Sys.getenv("LNK_TEST_PRETEST_MAP")
  if (!nzchar(p)) {
    p <- normalizePath(testthat::test_path("..", "..", "data-raw", "pretest_inputs.csv"),
                       mustWork = FALSE)
  }
  testthat::skip_if_not(file.exists(p), "data-raw/pretest_inputs.csv absent")
  p
}

pt_r_files <- function() {
  d <- testthat::test_path("..", "..", "R")
  testthat::skip_if_not(dir.exists(d), "R/ absent")
  list.files(d, pattern = "\\.R$")
}

test_that("every file in R/ matches a row of the map", {
  e <- pt_env()
  map <- e$pretest_map_read(pt_map_path())
  changed <- data.frame(repo = "link", path = file.path("R", pt_r_files()), stringsAsFactors = FALSE)
  m <- e$pretest_match(changed, map)
  expect_identical(m$unmapped$path, character())
})

test_that("a file mapped none is not reached from wsg_run_one.R's entry points", {
  e <- pt_env()
  map <- e$pretest_map_read(pt_map_path())
  ns <- asNamespace("link")
  skip_if(is.null(attr(get("lnk_pipeline_run", ns), "srcref")),
          "link loaded without srcrefs (not load_all)")
  reached <- e$pretest_reach(ns, e$PRETEST_ENTRIES)
  # The walk must see the pipeline itself, or an empty result passes this test.
  expect_true(all(c("lnk_pipeline_run.R", "lnk_pipeline_prepare.R", "utils.R") %in% reached))
  changed <- data.frame(repo = "link", path = file.path("R", reached), stringsAsFactors = FALSE)
  hits <- e$pretest_match(changed, map)$hits
  none_only <- vapply(split(hits$input, hits$path), function(x) all(x == "none"), logical(1))
  expect_identical(names(none_only)[none_only], character())
})

test_that("pretest_reach follows getFromNamespace calls", {
  e <- pt_env()
  ns <- new.env()
  src <- c("a <- function() b()",
           "b <- function() getFromNamespace(\"c\", \"x\")()",
           "c <- function() 1",
           "d <- function() 2")
  eval(parse(text = src, keep.source = TRUE), envir = ns)
  # srcref files are all the same text connection here, so test the walk by
  # name through a wrapper that maps every function to its own file.
  for (n in c("a", "b", "c", "d")) {
    f <- get(n, ns)
    attr(f, "srcref") <- structure(1L, srcfile = list2env(list(filename = paste0(n, ".R"))))
    assign(n, f, envir = ns)
  }
  expect_identical(e$pretest_reach(ns, "a"), c("a.R", "b.R", "c.R"))
})

test_that("an unmapped file is reported, and {config} matches only the chain", {
  e <- pt_env()
  map <- data.frame(repo = c("link", "link", "fresh"),
                    pattern = c("^R/a\\.R$", "^inst/extdata/configs/{config}/rules\\.yaml$", "^R/f\\.R$"),
                    input = c("segments", "near_river_conn", "none"),
                    why = "w", stringsAsFactors = FALSE)
  changed <- data.frame(repo = c("link", "link", "link", "fresh", "fresh"),
                        path = c("R/a.R", "R/b.R", "inst/extdata/configs/default/rules.yaml",
                                 "R/f.R", "R/a.R"),
                        stringsAsFactors = FALSE)
  m <- e$pretest_match(changed, map, chain = "default")
  expect_identical(m$unmapped$path, c("R/b.R", "R/a.R"))
  expect_identical(m$unmapped$repo, c("link", "fresh"))
  expect_identical(sort(m$hits$input), c("near_river_conn", "none", "segments"))
  m2 <- e$pretest_match(changed[3, ], map, chain = "bcfishpass")
  expect_identical(m2$unmapped$path, "inst/extdata/configs/default/rules.yaml")
  expect_identical(e$pretest_inputs(m$hits), c("near_river_conn", "segments"))
})

test_that("the map refuses a bad repo, an empty why and a pattern that does not compile", {
  e <- pt_env()
  f <- withr::local_tempfile(fileext = ".csv")
  w <- function(...) writeLines(c("repo,pattern,input,why", ...), f)
  w("link,^R/a\\.R$,any,ok")
  expect_identical(nrow(e$pretest_map_read(f)), 1L)
  w("lnk,^R/a\\.R$,any,ok")
  expect_error(e$pretest_map_read(f), "repo must be")
  w("link,^R/a\\.R$,any,")
  expect_error(e$pretest_map_read(f), "needs a pattern")
  w("link,^R/(a\\.R$,any,ok")
  expect_error(e$pretest_map_read(f), "does not compile")
})

test_that("each input takes its top groups among those with history, ties by code", {
  e <- pt_env()
  history <- data.frame(wsg = c("AAAA", "BBBB", "CCCC", "DDDD"),
                        minutes = c(1, 9, 3, 2), host = "m1", stringsAsFactors = FALSE)
  values <- list(near_river_conn = data.frame(wsg = c("QUES", "CCCC", "BBBB", "AAAA"),
                                              value = c(99, 5, 5, 1)),
                 dams = data.frame(wsg = c("AAAA", "DDDD"), value = c(NA, 3)))
  p <- e$pretest_pick(values, history, per_input = 2L)
  expect_identical(p$wsg, c("BBBB", "CCCC", "DDDD"))
  expect_identical(p$input, c("near_river_conn", "near_river_conn", "dams"))
  expect_identical(p$rank, c(1L, 2L, 1L))
  expect_error(e$pretest_pick(list(x = data.frame(wsg = "QUES", value = 1)), history),
               "no group with history")
})

test_that("any alone picks the fastest group; none alone picks nothing", {
  e <- pt_env()
  history <- data.frame(wsg = c("AAAA", "BBBB"), minutes = c(4, 0.5), host = "m1",
                        stringsAsFactors = FALSE)
  p <- e$pretest_pick(list(), history, any = TRUE)
  expect_identical(p$wsg, "BBBB")
  expect_identical(p$input, "any")
  expect_identical(nrow(e$pretest_pick(list(), history, any = FALSE)), 0L)
  # any beside a query input adds no group of its own
  p2 <- e$pretest_pick(list(segments = data.frame(wsg = "AAAA", value = 1)), history, any = TRUE)
  expect_identical(p2$wsg, "AAAA")
})

test_that("the bound is k times history with a floor, and the statement bound follows it", {
  e <- pt_env()
  expect_equal(e$pretest_bound(c(0.5, 4, 16.3), k = 3, floor_min = 5), c(5, 12, 48.9))
  expect_error(e$pretest_bound(c(1, NA)), "no history")
  expect_identical(e$pretest_statement_min(c(5, 12.1, 48.9, 0.2), cap = 30), c(5L, 13L, 30L, 1L))
  picks <- data.frame(wsg = c("AAAA", "BBBB", "AAAA"), input = c("x", "y", "y"),
                      value = 1, rank = 1L, stringsAsFactors = FALSE)
  history <- data.frame(wsg = c("AAAA", "BBBB"), minutes = c(2, 7), host = c("m1", "cloud"),
                        stringsAsFactors = FALSE)
  g <- e$pretest_groups(picks, history, k = 3, floor_min = 5)
  expect_identical(g$wsg, c("BBBB", "AAAA"))
  expect_identical(g$inputs, c("y", "x,y"))
  expect_equal(g$bound, c(21, 6))
})

test_that("verdicts: a failed exit, a missing row and a breach each fail the gate", {
  e <- pt_env()
  v <- e$pretest_verdict(exit = c(0L, 1L, 0L, 0L, NA, 124L), run_minutes = c(3, 3, NA, 7, 3, NA),
                         bound = c(5, 5, 5, 5, 5, 5))
  expect_identical(v, c("pass", "failed", "no_row", "bound", "failed", "bound"))
  expect_identical(e$pretest_overall(v), "fail")
  expect_identical(e$pretest_overall(c("pass", "pass")), "pass")
  expect_identical(e$pretest_overall(character()), "fail")
})

test_that("the fresh pin is read from Remotes, once", {
  e <- pt_env()
  d <- c("Remotes:", "    NewGraphEnvironment/fresh@v0.44.0,", "    NewGraphEnvironment/crate@v0.1.0")
  expect_identical(e$pretest_fresh_pin(d), "v0.44.0")
  expect_error(e$pretest_fresh_pin("Remotes: x/y"), "pins fresh 0 times")
})

test_that("changed files come from git, and a bad ref is an error, not an empty diff", {
  e <- pt_env()
  skip_if(!nzchar(Sys.which("git")), "git absent")
  d <- withr::local_tempdir()
  g <- function(...) system2("git", c("-C", d, ...), stdout = TRUE, stderr = TRUE)
  g("init", "-q")
  g("config", "user.email", "t@t")
  g("config", "user.name", "t")
  dir.create(file.path(d, "R"))
  dir.create(file.path(d, "inst/extdata/configs/default"), recursive = TRUE)
  dir.create(file.path(d, "inst/extdata/configs/bcfishpass"), recursive = TRUE)
  writeLines("a", file.path(d, "R/a.R"))
  writeLines("x", file.path(d, "inst/extdata/configs/default/rules.yaml"))
  writeLines("x", file.path(d, "inst/extdata/configs/bcfishpass/rules.yaml"))
  writeLines("x", file.path(d, "NEWS.md"))
  g("add", "-A")
  g("commit", "-qm", "one")
  g("tag", "v1")
  writeLines("b", file.path(d, "R/a.R"))
  writeLines("b", file.path(d, "R/b.R"))
  writeLines("y", file.path(d, "inst/extdata/configs/default/rules.yaml"))
  writeLines("y", file.path(d, "inst/extdata/configs/bcfishpass/rules.yaml"))
  writeLines("y", file.path(d, "NEWS.md"))
  g("add", "-A")
  g("commit", "-qm", "two")
  g("tag", "v2")
  ch <- e$pretest_changed_link(d, "v1", "v2", chain = "default")
  expect_identical(sort(ch$path), c("R/a.R", "R/b.R", "inst/extdata/configs/default/rules.yaml"))
  expect_error(e$pretest_changed_link(d, "nope", "v2", chain = "default"), "failed")
  fr <- e$pretest_changed_fresh(d, "v1", "v2")
  expect_identical(sort(fr$path), c("R/a.R", "R/b.R"))
  expect_identical(unique(fr$repo), "fresh")
  expect_identical(nrow(e$pretest_changed_fresh(d, "v2", "v2")), 0L)
  expect_error(e$pretest_changed_fresh(d, "v0", "v2"), "failed")
})

test_that("the config chain follows extends", {
  e <- pt_env()
  d <- testthat::test_path("..", "..", "inst", "extdata", "configs")
  skip_if_not(dir.exists(d), "configs absent")
  expect_identical(e$pretest_config_chain(d, "default_tuned"), c("default_tuned", "default"))
  expect_identical(e$pretest_config_chain(d, "default"), "default")
  expect_error(e$pretest_config_chain(d, "nope"), "no config bundle")
})

test_that("every file under inst/extdata, DESCRIPTION and the run's data-raw scripts matches a row", {
  e <- pt_env()
  map <- e$pretest_map_read(pt_map_path())
  root <- testthat::test_path("..", "..")
  skip_if_not(dir.exists(file.path(root, "inst", "extdata")), "inst/extdata absent")
  f <- list.files(file.path(root, "inst", "extdata"), recursive = TRUE)
  f <- c(file.path("inst/extdata", f), "DESCRIPTION",
         grep("^data-raw/", e$PRETEST_LINK_PATHS, value = TRUE))
  bundle <- ifelse(grepl("^inst/extdata/configs/[^/]+/", f),
                   sub("^inst/extdata/configs/([^/]+)/.*$", "\\1", f), "")
  unmapped <- character()
  for (b in unique(bundle)) {
    x <- f[bundle == b]
    m <- e$pretest_match(data.frame(repo = "link", path = x, stringsAsFactors = FALSE), map,
                         chain = if (nzchar(b)) b else character())
    unmapped <- c(unmapped, m$unmapped$path)
  }
  expect_identical(unmapped, character())
})

pt_git_repo <- function(e) {
  testthat::skip_if(!nzchar(Sys.which("git")), "git absent")
  d <- withr::local_tempdir(.local_envir = parent.frame())
  g <- function(...) system2("git", c("-C", d, ...), stdout = TRUE, stderr = TRUE)
  g("init", "-q")
  g("config", "user.email", "t@t")
  g("config", "user.name", "t")
  dir.create(file.path(d, "R"))
  dir.create(file.path(d, "inst/extdata/configs/default"), recursive = TRUE)
  dir.create(file.path(d, "inst/extdata/configs/bcfishpass"), recursive = TRUE)
  commit <- function(files, msg) {
    for (nm in names(files)) writeLines(files[[nm]], file.path(d, nm))
    g("add", "-A")
    g("commit", "-qm", shQuote(msg))
    g("rev-parse", "HEAD")
  }
  list(dir = d, commit = commit)
}

test_that("a gate record holds across commits that touch only none files", {
  e <- pt_env()
  r <- pt_git_repo(e)
  run <- r$commit(list("R/a.R" = "a", "R/v.R" = "v", DESCRIPTION = "1"), "last run")
  gated <- r$commit(list("R/a.R" = "a2"), "gated")
  bump <- r$commit(list(DESCRIPTION = "2", "R/v.R" = "v2",
                        "inst/extdata/configs/bcfishpass/rules.yaml" = "x"), "bump")
  map <- data.frame(repo = "link",
                    pattern = c("^R/a\\.R$", "^R/v\\.R$", "^DESCRIPTION$",
                                "^inst/extdata/configs/{config}/rules\\.yaml$"),
                    input = c("segments", "none", "none", "segments"), why = "w",
                    stringsAsFactors = FALSE)
  rec <- function(...) {
    x <- list(run_at = as.POSIXct("2026-10-28 12:00", tz = "UTC"), config_name = "default",
              link_sha = gated, link_dirty = FALSE, fresh_sha = "f1", since_sha = run,
              until_sha = gated, verdict = "pass", notes = NA_character_)
    x[names(list(...))] <- list(...)
    as.data.frame(x, stringsAsFactors = FALSE)
  }
  chk <- function(records, head = bump, fresh = "f1", hist = run) {
    e$pretest_record_check(records, "default", head, fresh, hist, r$dir, map, "default")
  }
  expect_true(chk(rec())$ok)
  expect_match(chk(rec()[0, ])$why, "no gate record")
  expect_match(chk(rec(verdict = "fail", notes = "QUES bound"))$why, "failed: QUES bound")
  expect_match(chk(rec(link_dirty = TRUE))$why, "dirty")
  expect_match(chk(rec(), fresh = "f2")$why, "installed is")
  expect_match(chk(rec(since_sha = gated))$why, "range starts")
  expect_match(chk(rec(config_name = "bcfishpass"))$why, "no gate record for config default")
  # a newer fail overrides an older pass
  both <- rbind(rec(), rec(run_at = as.POSIXct("2026-10-28 13:00", tz = "UTC"), verdict = "fail",
                           notes = "x"))
  expect_false(chk(both)$ok)
  # override rows are the run's, not the gate's
  ovr <- rbind(rec(), rec(run_at = as.POSIXct("2026-10-28 13:00", tz = "UTC"), verdict = "override"))
  expect_true(chk(ovr)$ok)
  # a modelling-path change after the gate voids it
  moved <- r$commit(list("R/a.R" = "a3"), "moved")
  expect_match(chk(rec(), head = moved)$why, "on the modelling path: R/a.R")
  unm <- r$commit(list("R/new.R" = "n"), "new file")
  expect_match(chk(rec(), head = unm)$why, "unmapped: R/new.R")
  expect_error(chk(rec(link_sha = "0000000000000000000000000000000000000000")), "failed")
})

test_that("the default --since is the earliest newest build, and dirty history refuses", {
  e <- pt_env()
  h <- data.frame(wsg = c("OKAN", "ADMS", "BULK"), link_sha = c("b", "a", "a"),
                  link_dirty = FALSE,
                  date_start = as.POSIXct(c("2026-10-24", "2026-10-23 08:00", "2026-10-23 09:00"),
                                          tz = "UTC"), stringsAsFactors = FALSE)
  expect_identical(e$pretest_since_default(h), "a")
  h$link_dirty[1] <- TRUE
  expect_error(e$pretest_since_default(h), "dirty tree \\(OKAN\\)")
  expect_error(e$pretest_since_default(h[0, ]), "no history row")
})

test_that("changed link files leave out bundles outside the chain", {
  e <- pt_env()
  r <- pt_git_repo(e)
  a <- r$commit(list("R/a.R" = "a", DESCRIPTION = "1"), "one")
  b <- r$commit(list("inst/extdata/configs/bcfishpass/rules.yaml" = "x",
                     "inst/extdata/configs/default/rules.yaml" = "y", DESCRIPTION = "2",
                     "NEWS.md" = "n"), "two")
  ch <- e$pretest_changed_link(r$dir, a, b, chain = "default")
  expect_identical(sort(ch$path), c("DESCRIPTION", "inst/extdata/configs/default/rules.yaml"))
})

test_that("pretest_check.R clears a run only on a passing record, and an override row is not one", {
  conn <- skip_if_no_db()
  info <- DBI::dbGetInfo(conn)
  skip_if_not(identical(info$host, "localhost") && identical(info$dbname, "fwapg"),
              "needs the local docker fwapg")
  root <- normalizePath(testthat::test_path("..", ".."))
  script <- file.path(root, "data-raw", "pretest_check.R")
  skip_if_not(file.exists(script), "data-raw/pretest_check.R absent")
  skip_if(!nzchar(Sys.which("psql")), "psql absent")
  head_sha <- system2("git", c("-C", root, "rev-parse", "HEAD"), stdout = TRUE)
  schema <- paste0("zz_test372_", Sys.getpid())
  DBI::dbExecute(conn, sprintf("CREATE SCHEMA %s", schema))
  withr::defer(DBI::dbExecute(conn, sprintf("DROP SCHEMA IF EXISTS %s CASCADE", schema)))
  check <- function(fresh = "f1") {
    out <- suppressWarnings(system2("Rscript", c(shQuote(script), "--config=default",
                                                 paste0("--schema=", schema),
                                                 paste0("--head=", head_sha),
                                                 paste0("--fresh-sha=", fresh)),
                                    stdout = TRUE, stderr = TRUE))
    list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"),
         out = paste(out, collapse = " "))
  }
  r <- check()
  expect_identical(r$status, 1L)
  expect_match(r$out, "log_pretest does not exist")

  # The override row the driver writes on --pretest-note: recorded, never a gate.
  psql <- function(sql_file, ...) {
    v <- c(...)
    system2("psql", c("-h", "localhost", "-U", "postgres", "-d", "fwapg", "-X", "-q",
                      "-v", "ON_ERROR_STOP=1", as.vector(rbind("-v", shQuote(paste0(names(v), "=", v)))),
                      "-f", shQuote(sql_file)),
            env = "PGPASSWORD=postgres", stdout = TRUE, stderr = TRUE)
  }
  psql(file.path(root, "data-raw", "pretest_override.sql"), schema = schema, config = "default",
       sha = head_sha, note = "it's urgent", uid = "20261028_000000-test")
  n <- DBI::dbGetQuery(conn, sprintf("SELECT verdict, notes FROM %s.log_pretest", schema))
  expect_identical(n$verdict, "override")
  expect_identical(n$notes, "run_uid 20261028_000000-test: it's urgent")
  r <- check()
  expect_identical(r$status, 1L)
  expect_match(r$out, "no gate record for config default")

  cols <- paste("run_at, config_name, link_sha, link_dirty, fresh_sha, since_sha, until_sha,",
                "scratch, k, floor_min, per_input, groups, verdict, notes")
  vals <- "$1, 'default', $2, false, $3, $2, $2, 's', 3, 5, 2, 'AAAA:pass', $4, NULL"
  ins_sql <- sprintf("INSERT INTO %s.log_pretest (%s) VALUES (%s)", schema, cols, vals)
  ins <- function(verdict, fresh, at) {
    DBI::dbExecute(conn, ins_sql, params = list(as.POSIXct(at, tz = "UTC"), head_sha, fresh, verdict))
  }
  ins("pass", "f1", "2026-10-28 10:00")
  r <- check()
  expect_identical(r$status, 0L)
  expect_match(r$out, "gate passed at")
  r <- check(fresh = "f2")
  expect_identical(r$status, 1L)
  expect_match(r$out, "installed is")
  ins("fail", "f1", "2026-10-28 11:00")
  r <- check()
  expect_identical(r$status, 1L)
  expect_match(r$out, "newest gate record failed")
})
