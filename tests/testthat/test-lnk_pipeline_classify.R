# -- input validation --------------------------------------------------------

test_that("lnk_pipeline_classify rejects invalid inputs", {
  cfg <- lnk_config("bcfishpass")
  expect_error(
    lnk_pipeline_classify("mock", aoi = NULL, cfg = cfg, schema = "w"),
    "aoi must be a single non-empty string"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK",
                           cfg = list(), schema = "w"),
    "cfg must be an lnk_config object"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg,
                           schema = "bad;name"),
    "schema"
  )
  expect_error(
    lnk_pipeline_classify("mock", aoi = "BULK", cfg = cfg,
                           schema = "w",
                           thresholds_csv = "/no/such/file.csv"),
    "thresholds_csv not found"
  )
})

# -- species derivation -----------------------------------------------------

test_that(".lnk_pipeline_classify_species intersects parameters with WSG presence", {
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(
      species_code = c("BT", "CH", "CO", "SK", "ST", "WCT"),
      stringsAsFactors = FALSE
    ),
    wsg_species = data.frame(
      watershed_group_code = "ELKR",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "t",
      stringsAsFactors = FALSE
    )
  ), class = c("lnk_config", "list"))

  expect_setequal(.lnk_pipeline_classify_species(cfg_stub, "ELKR"),
                   c("BT", "WCT"))
})

test_that(".lnk_pipeline_classify_species returns empty when AOI not in WSG table", {
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(species_code = c("BT", "CH")),
    wsg_species = data.frame(
      watershed_group_code = "ADMS",
      bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
      pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
      stringsAsFactors = FALSE
    )
  ), class = c("lnk_config", "list"))
  expect_equal(.lnk_pipeline_classify_species(cfg_stub, "BULK"),
               character(0))
})

test_that(".lnk_pipeline_classify_species returns parameters list when wsg_species missing", {
  cfg_stub <- structure(list(
    parameters_fresh = data.frame(species_code = c("BT", "CH")),
    wsg_species = NULL
  ), class = c("lnk_config", "list"))
  expect_setequal(.lnk_pipeline_classify_species(cfg_stub, "BULK"),
                   c("BT", "CH"))
})

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
  expect_match(joined, "DROP TABLE IF EXISTS fresh.streams_breaks")
  expect_match(joined, "CREATE TABLE fresh.streams_breaks")
  expect_match(joined, "FROM w_bulk.gradient_barriers_raw g")
  expect_match(joined, "FROM w_bulk.falls f")
  expect_match(joined, "FROM w_bulk.barriers_definite d")
  expect_match(joined, "FROM w_bulk.crossings c")
  expect_match(joined, "watershed_group_code = 'BULK'")
  expect_match(joined, "'BARRIER' THEN 'barrier'")
  expect_match(joined, "'POTENTIAL' THEN 'potential'")
  expect_match(joined, "'PASSABLE' THEN 'passable'")
})
