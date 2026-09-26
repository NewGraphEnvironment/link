# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_classify rejects invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_classify("mock", aoi = NULL, cfg = cfg,
                           loaded = list(), schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK",
                           cfg = list(), loaded = list(), schema = "w"),
    "cfg must be an lnk_config object"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg,
                           loaded = "not-a-list", schema = "w"),
    "loaded must be a named list"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg,
                           loaded = list(), schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg,
                           loaded = list(), schema = "w",
                           thresholds_csv = "/no/such/file.csv"),
    "thresholds_csv not found"
  )
})

# species derivation tests live in test-lnk_pipeline_species.R

# -- streams_breaks SQL shape -----------------------------------------------

test_that(".lnk_pipeline_classify_build_breaks unions all four sources", {
  captured <- character(0)
  local_mocked_bindings(
    .lnk_db_execute = function(conn, sql) {
      captured <<- c(captured, sql)
      invisible(NULL)
    }
  )

  .lnk_pipeline_classify_build_breaks("mock", aoi = "BULK",
                                        schema = "w_bulk")

  joined <- paste(captured, collapse = "\n")
  expect_match(joined, "DROP TABLE IF EXISTS w_bulk.streams_breaks")
  expect_match(joined, "CREATE TABLE w_bulk.streams_breaks")
  expect_match(joined, "FROM w_bulk.gradient_barriers_raw g")
  expect_match(joined, "FROM w_bulk.falls f")
  expect_match(joined, "FROM w_bulk.barriers_definite d")
  expect_match(joined, "FROM w_bulk.crossings c")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "'BARRIER' THEN 'barrier'")
  expect_match(joined, "'POTENTIAL' THEN 'potential'")
  expect_match(joined, "'PASSABLE' THEN 'passable'")
})

# -- thresholds CSV resolution (#282) ----------------------------------------

# Stops at frs_params and reports the csv it was handed, so nothing touches a DB.
capture_thresholds_csv_classify <- function(cfg, ...) {
  local_mocked_bindings(
    .lnk_pipeline_classify_build_breaks = function(...) invisible(NULL)
  )
  local_mocked_bindings(
    frs_params = function(csv = NULL, ...) stop("csv=", csv, call. = FALSE),
    .package = "fresh"
  )
  err <- tryCatch(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                          schema = "w_bulk", species = "BT", ...),
    error = function(e) conditionMessage(e))
  sub("^csv=", "", err)
}

test_that("lnk_pipeline_classify hands frs_params the bundle's own thresholds CSV", {
  csv <- tempfile(fileext = ".csv")
  file.create(csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- list(path = csv)
  expect_identical(capture_thresholds_csv_classify(cfg), csv)
})

test_that("lnk_pipeline_classify falls back to fresh's thresholds when undeclared", {
  skip_if_not_installed("fresh")
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- NULL
  expect_message(got <- capture_thresholds_csv_classify(cfg), "fresh's copy")
  expect_identical(got, system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))
})

test_that("lnk_pipeline_classify: an explicit thresholds_csv wins over the bundle's", {
  bundle_csv <- tempfile(fileext = ".csv")
  explicit_csv <- tempfile(fileext = ".csv")
  file.create(bundle_csv, explicit_csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- list(path = bundle_csv)
  expect_identical(
    capture_thresholds_csv_classify(cfg, thresholds_csv = explicit_csv),
    explicit_csv)
})
