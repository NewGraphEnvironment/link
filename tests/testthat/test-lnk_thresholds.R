test_that("lnk_thresholds returns default structure", {
  th <- lnk_thresholds()
  expect_type(th, "list")
  expect_named(th, c("high", "moderate", "low"))
  expect_type(th$high, "list")
  expect_type(th$moderate, "list")
  expect_type(th$low, "list")
})

test_that("default thresholds have expected BC values", {
  th <- lnk_thresholds()
  expect_equal(th$high$outlet_drop, 0.6)
  expect_equal(th$high$slope_length, 120)
  expect_equal(th$moderate$outlet_drop, 0.3)
  expect_equal(th$moderate$slope_length, 60)
  expect_length(th$low, 0)
})

test_that("bundled CSV produces same defaults", {
  csv_path <- system.file("extdata", "thresholds_default.csv", package = "link")
  skip_if(csv_path == "", message = "Bundled CSV not found (not installed)")
  th_csv <- lnk_thresholds(csv = csv_path)
  th_default <- lnk_thresholds()
  expect_equal(th_csv, th_default)
})

test_that("CSV overrides code defaults", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c(
    "severity,metric,value",
    "high,outlet_drop,0.9",
    "moderate,custom_metric,42"
  ), tmp)

  th <- lnk_thresholds(csv = tmp)
  expect_equal(th$high$outlet_drop, 0.9)
  # slope_length preserved from code default

  expect_equal(th$high$slope_length, 120)
  # new metric added to moderate
  expect_equal(th$moderate$custom_metric, 42)
})

test_that("inline arguments override CSV and defaults", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c(
    "severity,metric,value",
    "high,outlet_drop,0.9"
  ), tmp)

  th <- lnk_thresholds(csv = tmp, high = list(outlet_drop = 1.0))
  # inline wins over CSV

  expect_equal(th$high$outlet_drop, 1.0)
})

test_that("inline arguments work without CSV", {
  th <- lnk_thresholds(high = list(outlet_drop = 0.8, new_metric = 5))
  expect_equal(th$high$outlet_drop, 0.8)
  expect_equal(th$high$new_metric, 5)
  # slope_length still from defaults
  expect_equal(th$high$slope_length, 120)
})

test_that("low severity can receive thresholds", {
  th <- lnk_thresholds(low = list(outlet_drop = 0.1))
  expect_equal(th$low$outlet_drop, 0.1)
})

# --- Error cases: everything that can go wrong ---

test_that("missing CSV file errors with clear message", {
  expect_error(
    lnk_thresholds(csv = "/nonexistent/path/thresholds.csv"),
    "Thresholds CSV not found"
  )
})

test_that("CSV with missing required columns errors", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c("severity,metric", "high,outlet_drop"), tmp)

  expect_error(
    lnk_thresholds(csv = tmp),
    "missing required columns.*value"
  )
})

test_that("CSV with bad severity levels errors", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c(
    "severity,metric,value",
    "critical,outlet_drop,0.6"
  ), tmp)

  expect_error(
    lnk_thresholds(csv = tmp),
    "invalid severity levels.*critical"
  )
})

test_that("CSV with non-numeric value column errors", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c(
    "severity,metric,value",
    "high,outlet_drop,big"
  ), tmp)

  expect_error(
    lnk_thresholds(csv = tmp),
    "numeric"
  )
})

test_that("CSV with NA values errors", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c(
    "severity,metric,value",
    "high,outlet_drop,NA"
  ), tmp)

  expect_error(
    lnk_thresholds(csv = tmp),
    "numeric"
  )
})

test_that("non-list inline argument errors", {
  expect_error(
    lnk_thresholds(high = 0.6),
    "named list"
  )
})

test_that("unnamed list inline argument errors", {
  expect_error(
    lnk_thresholds(high = list(0.6, 120)),
    "named list"
  )
})

test_that("non-numeric values in inline argument errors", {
  expect_error(
    lnk_thresholds(high = list(outlet_drop = "big")),
    "non-numeric"
  )
})

test_that("NaN in inline argument errors", {
  expect_error(
    lnk_thresholds(high = list(outlet_drop = NaN)),
    "non-finite"
  )
})

test_that("Inf in inline argument errors", {
  expect_error(
    lnk_thresholds(moderate = list(outlet_drop = Inf)),
    "non-finite"
  )
})

test_that("empty CSV produces unchanged defaults", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines("severity,metric,value", tmp)

  th <- lnk_thresholds(csv = tmp)
  expect_equal(th, lnk_thresholds())
})

test_that("multiple severity rows in CSV all applied", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))
  writeLines(c(
    "severity,metric,value",
    "high,outlet_drop,0.7",
    "high,custom_a,10",
    "moderate,outlet_drop,0.4",
    "low,min_width,0.5"
  ), tmp)

  th <- lnk_thresholds(csv = tmp)
  expect_equal(th$high$outlet_drop, 0.7)
  expect_equal(th$high$custom_a, 10)
  expect_equal(th$moderate$outlet_drop, 0.4)
  expect_equal(th$low$min_width, 0.5)
})
