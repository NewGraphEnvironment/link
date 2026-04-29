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
