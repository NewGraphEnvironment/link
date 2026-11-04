# data-raw/streams_parent.R: the pair guard for lnk_streams_parent() (#444).
#
# data-raw/ is .Rbuildignore'd, so under R CMD check the helper is absent and
# these skip; devtools::test() from the source tree runs them.

spb_repo <- function() {
  normalizePath(testthat::test_path("..", ".."), mustWork = FALSE)
}

spb_env <- function() {
  dr <- file.path(spb_repo(), "data-raw")
  testthat::skip_if_not(file.exists(file.path(dr, "streams_parent.R")),
                        "data-raw/streams_parent.R absent")
  e <- new.env()
  sys.source(file.path(dr, "pretest.R"), envir = e)
  sys.source(file.path(dr, "streams_parent.R"), envir = e)
  e
}

# A pair that joins: two groups, each built on both sides.
spb_pair <- function() {
  side <- function(s, schema, cut, sha) {
    data.frame(side = s, schema = schema, wsg = c("BULK", "SETN"),
               run_id = paste0(s, 1:2), run_uid = "u", date_start = Sys.time(),
               date_end = Sys.time(), config_name = if (s == "full") "default" else "default_minimal",
               config_hash = paste0("h-", s), link_sha = sha, link_dirty = FALSE,
               fresh_sha = "f1", fresh_dirty = FALSE, token_cut = cut,
               token_acc = "acc-v5", token_grad = "grad-seg", token_flow = "q-fwapg",
               species = c("BT,CH", "CO,ST"), stringsAsFactors = FALSE)
  }
  rbind(side("full", "fresh_default", "cut-full-top", "sha_f"),
        side("minimal", "fresh_default_minimal", "cut-min", "sha_m"))
}

test_that("a pair built alike joins", {
  e <- spb_env()
  expect_identical(e$streams_parent_rows_why(spb_pair()), "")
})

test_that("each way a pair can differ refuses, naming why", {
  e <- spb_env()
  set <- function(col, i, v) {
    function(p) {
      p[[col]][i] <- v
      p
    }
  }
  drop <- function(i) function(p) p[-i, ]
  cases <- list(
    list(set("date_end", 2, NA), "open builds.*SETN"),
    list(set("link_dirty", 1, TRUE), "dirty or unknown tree.*BULK"),
    list(set("link_dirty", 3, NA), "dirty or unknown tree.*BULK"),
    list(set("fresh_dirty", 4, TRUE), "dirty or unknown tree.*SETN"),
    list(set("fresh_sha", 3:4, NA), "no fresh sha"),
    list(set("fresh_sha", 3:4, "f2"), "fresh_sha differs"),
    list(set("token_acc", 3:4, "acc-v4"), "token_acc differs"),
    list(set("token_grad", 1:2, "grad-parent"), "token_grad differs"),
    list(set("token_flow", 1:2, "q-wet-fill"), "token_flow differs"),
    list(set("species", 4, "CO"), "species differ: SETN"),
    list(set("token_cut", 3:4, "cut-full-top"), "not cut at cut-min"),
    list(set("token_cut", 1:2, "cut-min"), "not cut at a cut-full-\\* token"),
    list(set("config_hash", 2, "other"), "fresh_default holds 2 values of config_hash"),
    list(set("link_sha", 4, "sha_x"), "fresh_default_minimal holds 2 values of link_sha"),
    list(set("config_name", 1, "bcfishpass"), "2 values of config_name"),
    list(drop(4), "built on one side only: SETN"),
    list(drop(1:4), "no builds")
  )
  for (cs in cases) {
    expect_match(e$streams_parent_rows_why(cs[[1]](spb_pair())), cs[[2]])
  }
})

test_that("the code between the two builds is judged as the gate judges it", {
  e <- spb_env()
  map <- e$pretest_map_read(file.path(spb_repo(), "data-raw", "pretest_inputs.csv"))
  pin <- function(tag) c("Remotes:", paste0("    NewGraphEnvironment/fresh@", tag))
  changed <- character()
  fresh_tag <- c(a = "v0.52.0", b = "v0.52.0")
  e$pretest_git <- function(dir, args) pin(fresh_tag[[if (grepl("^a:", args[2])) "a" else "b"]])
  e$pretest_changed_link <- function(repo, since, until, chain) {
    data.frame(repo = rep("link", length(changed)), path = changed, stringsAsFactors = FALSE)
  }
  why <- function(reached = "lnk_pipeline_run.R") {
    e$streams_parent_code_why("repo", "a", "b", map, "default", reached)
  }
  changed <- "DESCRIPTION"
  expect_identical(why(), "")
  changed <- "R/lnk_pipeline_break.R"
  expect_match(why(), "on the modelling path: R/lnk_pipeline_break.R")
  changed <- "R/not_a_file_the_map_names.txt"
  expect_match(why(), "unmapped: R/not_a_file_the_map_names.txt")
  # A file mapped none that the modelling path reaches after all.
  changed <- "R/lnk_rollup_wsg.R"
  expect_identical(why(), "")
  expect_match(why(c("lnk_pipeline_run.R", "lnk_rollup_wsg.R")), "on the modelling path: R/lnk_rollup_wsg.R")
  expect_match(why(character()), "no reach")
  changed <- "DESCRIPTION"
  fresh_tag[["b"]] <- "v0.53.0"
  expect_match(why(), "pins fresh v0.52.0 at one build and v0.53.0")
})

test_that("on this clone, the provincial pair passes and a pair across a break change refuses", {
  e <- spb_env()
  repo <- spb_repo()
  has <- function(sha) {
    isTRUE(tryCatch({
      e$pretest_git(repo, c("cat-file", "-e", paste0(sha, "^{commit}")))
      TRUE
    }, error = function(err) FALSE))
  }
  skip_if_not(has("193cb8aa") && has("4dfbfa49"), "the provincial pair's commits are not in this clone")
  map <- e$pretest_map_read(file.path(repo, "data-raw", "pretest_inputs.csv"))
  chain <- c("default_minimal", "default")
  reached <- "lnk_pipeline_run.R"
  expect_identical(e$streams_parent_code_why(repo, "193cb8aa", "4dfbfa49", map, chain, reached), "")
  brk <- e$pretest_git(repo, c("log", "-1", "--format=%H", "193cb8aa", "--", "R/lnk_pipeline_break.R"))
  skip_if_not(length(brk) == 1L && has(paste0(brk, "^")), "no parent of the last break change")
  expect_match(e$streams_parent_code_why(repo, paste0(brk, "^"), brk, map, chain, reached),
               "R/lnk_pipeline_break.R")
})
