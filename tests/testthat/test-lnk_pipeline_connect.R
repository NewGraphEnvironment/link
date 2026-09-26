# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_connect rejects invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_connect("mock", aoi = NULL, cfg = cfg,
                          loaded = list(), schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_connect("mock", aoi = "BULK",
                          cfg = list(), loaded = list(), schema = "w"),
    "cfg must be an lnk_config object"
  )
  expect_error(
    lnk_pipeline_connect("mock", aoi = "BULK", cfg = cfg,
                          loaded = "not-a-list", schema = "w"),
    "loaded must be a named list"
  )
  expect_error(
    lnk_pipeline_connect("mock", aoi = "BULK", cfg = cfg,
                          loaded = list(), schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_connect("mock", aoi = "BULK", cfg = cfg,
                          loaded = list(), schema = "w",
                          thresholds_csv = "/no/such/file.csv"),
    "thresholds_csv not found"
  )
})

test_that("lnk_pipeline_connect errors when species cannot be resolved", {
  cfg_stub <- structure(list(
    rules = system.file("extdata", "configs", "bcfishpass",
                         "rules.yaml", package = "link")
  ), class = c("lnk_config", "list"))
  loaded_stub <- list(
    parameters_fresh = data.frame(species_code = c("BT", "CH")),
    wsg_species_presence = data.frame(
      watershed_group_code = "ADMS",
      bt = "f", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    )
  )

  expect_error(
    lnk_pipeline_connect("mock", aoi = "BULK", cfg = cfg_stub,
                          loaded = loaded_stub, schema = "w_bulk"),
    "No species resolved"
  )
})

# -- thresholds CSV resolution (#282) ----------------------------------------

# Stops at frs_params and reports the csv it was handed, so nothing touches a DB.
capture_th_csv_connect <- function(cfg, ...) {
  local_mocked_bindings(
    .lnk_pipeline_classify_build_breaks = function(...) invisible(NULL)
  )
  local_mocked_bindings(
    frs_params = function(csv = NULL, ...) stop("csv=", csv, call. = FALSE),
    .package = "fresh"
  )
  err <- tryCatch(
    lnk_pipeline_connect("mock", aoi = "BULK", cfg = cfg, loaded = list(),
                          schema = "w_bulk", species = "BT", ...),
    error = function(e) conditionMessage(e))
  sub("^csv=", "", err)
}

test_that("lnk_pipeline_connect hands frs_params the bundle's own thresholds CSV", {
  csv <- tempfile(fileext = ".csv")
  file.create(csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- list(path = csv)
  expect_identical(capture_th_csv_connect(cfg), csv)
})

test_that("lnk_pipeline_connect falls back to fresh's thresholds when undeclared", {
  skip_if_not_installed("fresh")
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- NULL
  expect_message(got <- capture_th_csv_connect(cfg), "fresh's copy")
  expect_identical(got, system.file("extdata",
    "parameters_habitat_thresholds.csv", package = "fresh"))
})

test_that("lnk_pipeline_connect: an explicit thresholds_csv wins over the bundle's", {
  bundle_csv <- tempfile(fileext = ".csv")
  explicit_csv <- tempfile(fileext = ".csv")
  file.create(bundle_csv, explicit_csv)
  cfg <- lnk_config("default")
  cfg$files$parameters_habitat_thresholds <- list(path = bundle_csv)
  expect_identical(
    capture_th_csv_connect(cfg, thresholds_csv = explicit_csv),
    explicit_csv)
})
