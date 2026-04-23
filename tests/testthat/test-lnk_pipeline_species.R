# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_species rejects invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_pipeline_species(list(), "BULK"),
               "cfg must be an lnk_config object")
  expect_error(lnk_pipeline_species(cfg, NULL),
               "aoi must be a single non-empty string")
  expect_error(lnk_pipeline_species(cfg, ""),
               "aoi must be a single non-empty string")
  expect_error(lnk_pipeline_species(cfg, c("BULK", "ADMS")),
               "aoi must be a single non-empty string")
})

# -- intersect semantics -----------------------------------------------------

test_that("lnk_pipeline_species intersects cfg$species with AOI presence", {
  cfg_stub <- structure(list(
    species = c("BT", "CH", "CO", "SK", "ST", "WCT"),
    wsg_species = data.frame(
      watershed_group_code = "ELKR",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "t",
      stringsAsFactors = FALSE
    )
  ), class = c("lnk_config", "list"))
  expect_setequal(lnk_pipeline_species(cfg_stub, "ELKR"),
                   c("BT", "WCT"))
})

test_that("lnk_pipeline_species returns empty when AOI not in WSG table", {
  cfg_stub <- structure(list(
    species = c("BT", "CH"),
    wsg_species = data.frame(
      watershed_group_code = "ADMS",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    )
  ), class = c("lnk_config", "list"))
  expect_equal(lnk_pipeline_species(cfg_stub, "BULK"), character(0))
})

test_that("lnk_pipeline_species returns cfg$species unfiltered when wsg_species is NULL", {
  cfg_stub <- structure(list(
    species = c("BT", "CH"),
    wsg_species = NULL
  ), class = c("lnk_config", "list"))
  expect_setequal(lnk_pipeline_species(cfg_stub, "BULK"),
                   c("BT", "CH"))
})

test_that("lnk_pipeline_species falls back to parameters_fresh when cfg$species missing", {
  cfg_stub <- structure(list(
    species = NULL,
    parameters_fresh = data.frame(species_code = c("BT", "CH")),
    wsg_species = NULL
  ), class = c("lnk_config", "list"))
  expect_setequal(lnk_pipeline_species(cfg_stub, "BULK"),
                   c("BT", "CH"))
})

# -- live bundle --------------------------------------------------------------

test_that("lnk_pipeline_species works against the bundled bcfishpass config", {
  cfg <- lnk_config("bcfishpass")

  adms <- lnk_pipeline_species(cfg, "ADMS")
  expect_setequal(adms, c("BT", "CH", "CO", "SK"))

  bulk <- lnk_pipeline_species(cfg, "BULK")
  expect_true(all(c("BT", "CH", "CO", "SK", "ST") %in% bulk))
})
