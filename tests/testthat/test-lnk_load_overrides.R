# lnk_load_overrides materializes the data files declared in a
# config's files: map. Crate-registered entries dispatch through
# crate::crt_ingest(); others fall through to extension-based local
# reads (csv today).

test_that("lnk_load_overrides returns one tibble per files entry", {
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)

  expect_type(loaded, "list")
  expect_setequal(names(loaded), names(cfg$files))
  expect_true(all(vapply(loaded, inherits, logical(1), what = "data.frame")))
  expect_true(all(vapply(loaded, inherits, logical(1), what = "tbl_df")))
})

test_that("lnk_load_overrides routes user_habitat_classification via crate", {
  cfg <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)

  uhc <- loaded$user_habitat_classification
  # Canonical wide shape (post-2026-04-26 bcfishpass)
  expect_true("species_code" %in% names(uhc))
  expect_true(all(c("spawning", "rearing") %in% names(uhc)))
})

test_that("lnk_load_overrides accepts a name string for ergonomic call", {
  loaded <- lnk_load_overrides("bcfishpass")
  expect_type(loaded, "list")
  expect_true("user_habitat_classification" %in% names(loaded))
})

test_that("lnk_load_overrides rejects non-config arguments", {
  expect_error(lnk_load_overrides(list()),
    "cfg must be an lnk_config or a config name/path")
  expect_error(lnk_load_overrides(42),
    "cfg must be an lnk_config or a config name/path")
})

test_that("local fallback reads CSV via extension dispatch", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(name = "x"), file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1, b = 2), file.path(tmp, "dims.csv"),
    row.names = FALSE)
  write.csv(data.frame(z = 99), file.path(tmp, "test.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(test = list(path = "test.csv"))
    ),
    file.path(tmp, "config.yaml")
  )
  loaded <- lnk_load_overrides(lnk_config(tmp))
  expect_true(inherits(loaded$test, "tbl_df"))
  expect_equal(loaded$test$z, 99)
})

test_that("local fallback errors on unsupported extension", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(name = "x"), file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"),
    row.names = FALSE)
  file.create(file.path(tmp, "weird.parquet"))
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(weird = list(path = "weird.parquet"))
    ),
    file.path(tmp, "config.yaml")
  )
  expect_error(lnk_load_overrides(lnk_config(tmp)),
    "Unsupported file extension 'parquet'")
})

test_that("invalid canonical_schema format errors loud", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(name = "x"), file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"),
    row.names = FALSE)
  write.csv(data.frame(a = 1), file.path(tmp, "data.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(bad = list(path = "data.csv",
                              canonical_schema = "no_slash"))
    ),
    file.path(tmp, "config.yaml")
  )
  expect_error(lnk_load_overrides(lnk_config(tmp)),
    "canonical_schema.*must be '<source>/<file_name>'")
})
