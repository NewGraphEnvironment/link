# lnk_stamp captures a structured snapshot of every input that
# influences a habitat-classification run. Tests cover the no-DB path,
# stamp_finish workflow, markdown rendering, and validation.

test_that("lnk_stamp rejects non-lnk_config input", {
  expect_error(lnk_stamp(list()), "must be an lnk_config")
  expect_error(lnk_stamp(NULL), "must be an lnk_config")
})

test_that("lnk_stamp rejects bad aoi", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_stamp(cfg, aoi = ""), "non-empty string")
  expect_error(lnk_stamp(cfg, aoi = c("a", "b")), "non-empty string")
})

test_that("lnk_stamp returns lnk_stamp S3 with expected slots", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_s3_class(s, "lnk_stamp")
  expect_setequal(names(s),
    c("config_name", "config_dir", "provenance",
      "software", "db", "run", "result"))
  expect_equal(s$config_name, "bcfishpass")
  expect_equal(s$run$aoi, "ADMS")
  expect_null(s$run$end_time)
  expect_null(s$result)
  expect_null(s$db)  # no conn, db should be NULL
})

test_that("lnk_stamp software slot has link + fresh + R", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_setequal(names(s$software), c("link", "fresh", "R"))
  expect_match(s$software$link$version, "^\\d+\\.\\d+\\.\\d+$")
  expect_match(s$software$R, "^R version")
})

test_that("lnk_stamp provenance slot is the verify tibble", {
  testthat::skip_if_not_installed("digest")
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_s3_class(s$provenance, "data.frame")
  expect_named(s$provenance,
               c("file",
                 "byte_expected", "byte_observed", "byte_drift",
                 "shape_expected", "shape_observed", "shape_drift",
                 "missing"))
  expect_equal(sum(s$provenance$byte_drift), 0L)
  expect_equal(sum(s$provenance$shape_drift), 0L)
})

test_that("lnk_stamp handles config without provenance block", {
  tmp <- withr::local_tempdir()
  file.create(file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"), row.names = FALSE)
  write.csv(data.frame(a = 1), file.path(tmp, "params.csv"),
            row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      files = list(
        rules_yaml = "rules.yaml",
        dimensions_csv = "dims.csv",
        parameters_fresh = "params.csv"
      )
    ),
    file.path(tmp, "config.yaml")
  )
  cfg <- lnk_config(tmp)
  s <- lnk_stamp(cfg, aoi = "TEST")
  expect_null(s$provenance)
})

test_that("lnk_stamp_finish sets end_time and result", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  Sys.sleep(0.05)
  s <- lnk_stamp_finish(s, result = data.frame(x = 1:3))
  expect_true(!is.null(s$run$end_time))
  expect_true(s$run$end_time > s$run$start_time)
  expect_s3_class(s$result, "data.frame")
  expect_equal(nrow(s$result), 3L)
})

test_that("lnk_stamp_finish rejects non-lnk_stamp input", {
  expect_error(lnk_stamp_finish(list()), "must be an lnk_stamp")
})

test_that("format(stamp, 'markdown') produces structured output", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  md <- format(s, "markdown")
  expect_type(md, "character")
  expect_length(md, 1L)
  expect_match(md, "## Run stamp", fixed = TRUE)
  expect_match(md, "AOI: `ADMS`", fixed = TRUE)
  expect_match(md, "### Software", fixed = TRUE)
  expect_match(md, "### Config provenance", fixed = TRUE)
})

test_that("format(stamp, 'markdown') includes ended + elapsed when finished", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  Sys.sleep(0.05)
  s <- lnk_stamp_finish(s)
  md <- format(s, "markdown")
  expect_match(md, "Ended:", fixed = TRUE)
  expect_match(md, "elapsed", fixed = TRUE)
})

test_that("format(stamp) defaults to markdown", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  expect_identical(format(s), format(s, "markdown"))
})

test_that("format(stamp, 'text') runs without error", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  txt <- format(s, "text")
  expect_type(txt, "character")
  expect_match(txt, "<lnk_stamp>", fixed = TRUE)
})

test_that("print.lnk_stamp returns the stamp invisibly", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, aoi = "ADMS")
  out <- capture.output(r <- print(s))
  expect_identical(r, s)
  expect_match(paste(out, collapse = "\n"), "<lnk_stamp>", fixed = TRUE)
})

test_that("lnk_stamp db slot is NULL when conn is NULL", {
  cfg <- lnk_config("bcfishpass")
  s <- lnk_stamp(cfg, conn = NULL, aoi = "ADMS")
  expect_null(s$db)
})

test_that("lnk_stamp db slot is NULL when db_snapshot = FALSE even with conn", {
  cfg <- lnk_config("bcfishpass")
  conn <- structure(list(), class = "DBIConnection")  # mock conn
  s <- lnk_stamp(cfg, conn = conn, aoi = "ADMS", db_snapshot = FALSE)
  expect_null(s$db)
})
