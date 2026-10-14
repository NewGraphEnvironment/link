# Habitat export (#308)

test_that("the column contract parses and names every documented column", {
  cols <- link:::.lnk_export_cols()
  expect_identical(names(cols)[1:3], c("blue_line_key",
                                       "downstream_route_measure",
                                       "upstream_route_measure"))
  expect_true(all(cols %in% c("integer", "double", "string", "logical")))
  expect_true(all(c("mad_m3s", "mad_m3s_source", "accessible", "spawning",
                    "rearing", "lake_rearing", "wetland_rearing",
                    "accessible_ratio_gradient", "spawning_ratio_cw",
                    "spawning_ratio_mad", "spawning_ratio_gradient",
                    "rearing_ratio_cw", "rearing_ratio_mad",
                    "rearing_ratio_gradient") %in% names(cols)))
  expect_false(anyDuplicated(names(cols)) > 0)
})

test_that("conform refuses a wrong type, a reordered column and an NA flag", {
  cols <- c(a = "integer", accessible = "logical")
  ok <- data.frame(a = 1L, accessible = TRUE)
  # the key and flag checks need the real names; test type/order only here
  expect_error(link:::.lnk_export_conform(data.frame(a = 1, accessible = TRUE),
                                          cols), "wrong type")
  expect_error(link:::.lnk_export_conform(ok[2:1], cols), "column contract")
})

test_that("rows join on the full key, read FALSE for an absent species, and ratio on logged thresholds", {
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)

  adms <- link:::.lnk_export_rows(conn, schema, "ADMS", "BT",
                                  export_run(conn, schema, "ADMS"))
  # two segments, not four: BULK shares id_segment 1 and 2
  expect_identical(nrow(adms), 2L)
  expect_identical(adms$spawning, c(TRUE, FALSE))
  expect_identical(adms$mad_m3s, c(0.5, 0.5))
  expect_identical(adms$mad_m3s_source, c("modelled", "modelled"))
  expect_equal(adms$spawning_ratio_cw, c(4 / 2, NA))
  expect_equal(adms$spawning_ratio_mad, c(0.5 / 0.25, 0.5 / 0.25))
  expect_equal(adms$spawning_ratio_gradient, c(0.02 / 0.05, 0.20 / 0.05))
  expect_equal(adms$rearing_ratio_gradient, c(0.02 / 0.10, 0.20 / 0.10))
  expect_equal(adms$accessible_ratio_gradient, c(0.02 / 0.25, 0.20 / 0.25))
  # a blank threshold in the logged text snapshot is NULL, not 0
  expect_true(all(is.na(adms$rearing_ratio_cw)))

  bulk <- link:::.lnk_export_rows(conn, schema, "BULK", "BT",
                                  export_run(conn, schema, "BULK"))
  expect_identical(nrow(bulk), 2L)
  for (f in c("accessible", "spawning", "rearing", "lake_rearing",
              "wetland_rearing")) {
    expect_identical(bulk[[f]], c(FALSE, FALSE), info = f)
  }
  expect_identical(bulk$mad_m3s, c(40, NA))

  # a build that logged no thresholds gives NA ratios, not a fallback
  lfra <- link:::.lnk_export_rows(conn, schema, "LFRA", "BT",
                                  export_run(conn, schema, "LFRA"))
  expect_true(is.na(lfra$spawning_ratio_cw))
  expect_equal(lfra$accessible_ratio_gradient, 0.01 / 0.25)
  expect_identical(lfra$wetland_rearing, TRUE)
})

test_that("a species the schema has no table for reads FALSE everywhere", {
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  x <- link:::.lnk_export_rows(conn, schema, "ADMS", "CO",
                               export_run(conn, schema, "ADMS"))
  expect_identical(nrow(x), 2L)
  expect_false(any(x$accessible | x$spawning | x$rearing))
  expect_true(all(is.na(x$spawning_ratio_cw)))
})

test_that("a fanned-out discharge join is refused", {
  conn <- skip_if_no_db()
  schema <- local_export_fixture(conn)
  local_export_discharge(schema)
  DBI::dbExecute(conn, sprintf(
    "INSERT INTO %s.discharge VALUES (101, 0.6)", schema))
  expect_error(
    link:::.lnk_export_rows(conn, schema, "ADMS", "BT",
                            export_run(conn, schema, "ADMS")),
    "fanned out")
})
