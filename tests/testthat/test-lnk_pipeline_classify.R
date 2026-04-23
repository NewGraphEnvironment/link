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
