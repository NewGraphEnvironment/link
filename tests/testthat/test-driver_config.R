# The data-raw drivers refuse to run without an explicit config (link#278), and
# the three that write persist tables refuse a bundle other than bcfishpass with
# no LNK_SCHEMA. data-raw/ is .Rbuildignore'd, so under R CMD check the scripts
# are absent and these skip; devtools::test() from the source tree runs them.
# LNK_TEST_DRIVER_DIR points the tests at a mutant copy of data-raw/ (proving
# they fail). Mutate only the shell drivers that way: a mutant R driver that
# accepts a config connects to the local fwapg and models for real.

driver_path <- function(name) {
  d <- Sys.getenv("LNK_TEST_DRIVER_DIR",
                  testthat::test_path("..", "..", "data-raw"))
  p <- normalizePath(file.path(d, name), mustWork = FALSE)
  testthat::skip_if_not(file.exists(p), paste0("data-raw/", name, " absent"))
  p
}

# Run an R driver with no database reached (the refusals come before load_all).
run_r_driver <- function(name, args = character(), env = character()) {
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"), c(shQuote(driver_path(name)), args),
    stdout = TRUE, stderr = TRUE, env = c("LNK_SCHEMA=", env)))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

run_sh_driver <- function(name, args = character(), env = character()) {
  bash <- hosts_bash()
  testthat::skip_if_not(nzchar(bash), "no bash >= 5.1 found")
  out <- suppressWarnings(system2(
    bash, c(shQuote(driver_path(name)), args),
    stdout = TRUE, stderr = TRUE, env = env))
  list(out = paste(out, collapse = "\n"), status = attr(out, "status") %||% 0L)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

test_that("each R driver with no config exits non-zero and says the config is required", {
  cases <- list(
    list("wsg_run_one.R", "DEAD"),
    list("wsg_recompute_one.R", "DEAD"),
    list("study_area_wsgs.R", "DEAD"),
    list("study_area_compare.R", c("o.csv", "DEAD")),
    list("host_stamp.R", character()),
    list("barriers_views_build.R", character()),
    list("study_area_buckets.R", character()),
    list("access_disagree_349.R", character())
  )
  for (cs in cases) {
    r <- run_r_driver(cs[[1]], cs[[2]])
    expect_gt(r$status, 0L, label = cs[[1]])
    expect_match(r$out, "config is required", fixed = TRUE, info = cs[[1]])
  }
})

test_that("the variants drivers need --base", {
  for (nm in c("habitat_variants_build.R", "habitat_variants_score.R")) {
    r <- run_r_driver(nm)
    expect_gt(r$status, 0L, label = nm)
    expect_match(r$out, "config is required", fixed = TRUE, info = nm)
  }
})

test_that("parity_crosssection.R needs LNK_CONFIG, and LNK_SCHEMA for a non-bcfishpass one", {
  r <- run_r_driver("parity_crosssection.R", env = "LNK_CONFIG=")
  expect_gt(r$status, 0L)
  expect_match(r$out, "config is required", fixed = TRUE)
})

test_that("the persist-writing drivers refuse a non-bcfishpass config with no LNK_SCHEMA", {
  for (nm in c("wsg_run_one.R", "wsg_recompute_one.R", "barriers_views_build.R")) {
    args <- if (nm == "barriers_views_build.R") "default" else c("DEAD", "default")
    r <- run_r_driver(nm, args)
    expect_gt(r$status, 0L, label = nm)
    expect_match(r$out, "LNK_SCHEMA is required", fixed = TRUE, info = nm)
  }
})

test_that("each shell driver with no config exits non-zero and says it is required", {
  r <- run_sh_driver("study_area_run.sh")
  expect_gt(r$status, 0L)
  expect_match(r$out, "--config=<bundle> is required", fixed = TRUE)

  for (nm in c("recompute_parity.sh", "recompute_sweep.sh")) {
    r <- run_sh_driver(nm, "LKEL")
    expect_gt(r$status, 0L, label = nm)
    expect_match(r$out, "config is required", fixed = TRUE, info = nm)
    r <- run_sh_driver(nm, c("LKEL", "default"))
    expect_gt(r$status, 0L, label = nm)
    expect_match(r$out, "LNK_SCHEMA is required", fixed = TRUE, info = nm)
  }

  out <- suppressWarnings(system2(
    "bash", shQuote(driver_path("cypher_prep.sh")), stdout = TRUE, stderr = TRUE,
    env = c("CYPHER_PREP_STAGE=all", "CYPHER_PREP_CONFIG=")))
  expect_gt(attr(out, "status") %||% 0L, 0L)
  expect_match(paste(out, collapse = "\n"), "CYPHER_PREP_CONFIG is required", fixed = TRUE)
})

test_that("the study-area driver's refusal comes before its focal-count check", {
  r <- run_sh_driver("study_area_run.sh", "--preflight-only")
  expect_match(r$out, "--config=<bundle> is required", fixed = TRUE)
  expect_no_match(r$out, "need exactly", fixed = TRUE)
})
