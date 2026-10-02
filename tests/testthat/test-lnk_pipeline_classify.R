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
capture_th_csv_classify <- function(cfg, ...) {
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
  expect_identical(capture_th_csv_classify(cfg), csv)
})

test_that("lnk_pipeline_classify falls back to fresh's thresholds when undeclared", {
  skip_if_not_installed("fresh")
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- NULL
  expect_message(got <- capture_th_csv_classify(cfg), "fresh's copy")
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
    capture_th_csv_classify(cfg, thresholds_csv = explicit_csv),
    explicit_csv)
})

# -- method table resolution (#286) ------------------------------------------

# Stops at frs_habitat_classify and returns the params_method it was handed.
capture_method_classify <- function(cfg, ...) {
  local_mocked_bindings(
    .lnk_pipeline_classify_build_breaks = function(...) invisible(NULL)
  )
  got <- NULL
  local_mocked_bindings(
    frs_params = function(...) list(),
    frs_habitat_classify = function(..., params_method) {
      got <<- params_method
      stop("captured", call. = FALSE)
    },
    .package = "fresh"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                          schema = "w_bulk", species = "BT", ...),
    "captured")
  got
}

test_that("lnk_pipeline_classify passes the bundle's method table to fresh", {
  csv <- withr::local_tempfile(fileext = ".csv")
  writeLines("watershed_group_code,model\nBULK,mad\nADMS,cw", csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_method <- list(path = csv)
  pm <- capture_method_classify(cfg)
  expect_identical(pm$watershed_group_code, c("BULK", "ADMS"))
  expect_identical(pm$model, c("mad", "cw"))
})

test_that("lnk_pipeline_classify passes a shipped bundle's own method table", {
  cfg <- lnk_config("default")
  pm <- capture_method_classify(cfg)
  shipped <- utils::read.csv(cfg$files$parameters_habitat_method$path,
                             colClasses = "character")
  expect_identical(pm$watershed_group_code, shipped$watershed_group_code)
  expect_true(all(pm$model == "cw"))
})

test_that("lnk_pipeline_classify falls back to fresh's method table when undeclared", {
  skip_if_not_installed("fresh")
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_method <- NULL
  expect_message(pm <- capture_method_classify(cfg), "fresh's copy")
  fresh_pm <- utils::read.csv(system.file("extdata",
    "parameters_habitat_method.csv", package = "fresh"),
    colClasses = "character")
  expect_identical(pm$watershed_group_code, fresh_pm$watershed_group_code)
})

test_that("lnk_pipeline_classify: an explicit method_csv wins over the bundle's", {
  bundle_csv <- withr::local_tempfile(fileext = ".csv")
  explicit_csv <- withr::local_tempfile(fileext = ".csv")
  writeLines("watershed_group_code,model\nBULK,cw", bundle_csv)
  writeLines("watershed_group_code,model\nBULK,mad", explicit_csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_method <- list(path = bundle_csv)
  pm <- capture_method_classify(cfg, method_csv = explicit_csv)
  expect_identical(pm$model, "mad")
})

test_that("lnk_pipeline_classify stops on a missing method_csv", {
  cfg <- lnk_config("default")
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                          schema = "w_bulk", species = "BT",
                          method_csv = "/no/such/method.csv"),
    "method_csv not found")
})

test_that("a watershed group coded NA is a code, not a missing value", {
  # read.csv's default na.strings would turn a group code "NA" into NA, and
  # fresh's match() would then drop it to cw silently.
  csv <- withr::local_tempfile(fileext = ".csv")
  writeLines("watershed_group_code,model\nNA,mad", csv)
  cfg <- lnk_config("default")
  pm <- capture_method_classify(cfg, method_csv = csv)
  expect_identical(pm$watershed_group_code, "NA")
})

# -- stream-order bypass is cw-only (#286) -----------------------------------

# Runs classify end to end with fresh mocked; returns the species
# frs_order_child was called for.
bypass_calls <- function(model) {
  csv <- withr::local_tempfile(fileext = ".csv")
  writeLines(c("watershed_group_code,model", paste0("BULK,", model)), csv)
  local_mocked_bindings(
    .lnk_pipeline_classify_build_breaks = function(...) invisible(NULL)
  )
  called <- character(0)
  bypass_rule <- list(channel_width_min_bypass =
                        list(stream_order_parent_min = 5L))
  local_mocked_bindings(
    frs_params = function(...) {
      list(BT = list(rules = list(rear = list(bypass_rule))))
    },
    frs_habitat_classify = function(...) invisible(NULL),
    frs_order_child = function(conn, ..., species) {
      called <<- c(called, species)
      invisible(NULL)
    },
    .package = "fresh"
  )
  lnk_pipeline_classify("mock", aoi = "BULK", cfg = lnk_config("default"),
                        loaded = list(), schema = "w_bulk", species = "BT",
                        method_csv = csv)
  called
}

test_that("the stream-order rearing bypass runs for a cw group", {
  expect_identical(bypass_calls("cw"), "BT")
})

test_that("the stream-order rearing bypass is skipped for a mad group", {
  # bcfp applies it inside its channel-width branch only.
  expect_identical(bypass_calls("mad"), character(0))
})
