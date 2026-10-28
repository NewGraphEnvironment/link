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
  v <- e$pretest_verdict(exit = c(0L, 1L, 0L, 0L, NA), run_minutes = c(3, 3, NA, 7, 3),
                         bound = c(5, 5, 5, 5, 5))
  expect_identical(v, c("pass", "failed", "no_row", "bound", "failed"))
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
