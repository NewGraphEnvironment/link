# lnk_config_verify recomputes sha256 of every provenanced file and
# reports drift. Tests use temp config bundles to control the file
# state precisely.

skip_if_no_digest <- function() {
  testthat::skip_if_not_installed("digest")
}

# Helper: build a tmp config dir with a known file + a provenance entry
# referencing the file's actual sha256. Returns the tmp dir path.
.build_tmp_cfg <- function(content = "alpha\n") {
  skip_if_no_digest()
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  rules_path <- file.path(tmp, "rules.yaml")
  dims_path  <- file.path(tmp, "dims.csv")
  params_path <- file.path(tmp, "params.csv")

  writeLines(content, rules_path)
  write.csv(data.frame(a = 1), dims_path, row.names = FALSE)
  write.csv(data.frame(a = 1), params_path, row.names = FALSE)

  rules_sha <- digest::digest(file = rules_path, algo = "sha256")

  yaml::write_yaml(
    list(
      name = "x",
      files = list(
        rules_yaml = "rules.yaml",
        dimensions_csv = "dims.csv",
        parameters_fresh = "params.csv"
      ),
      provenance = list(
        rules.yaml = list(
          source = "test (hand-authored)",
          checksum = paste0("sha256:", rules_sha)
        )
      )
    ),
    file.path(tmp, "config.yaml")
  )
  tmp
}

test_that("lnk_config_verify returns clean tibble when no drift", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg()
  cfg <- lnk_config(tmp)
  v <- lnk_config_verify(cfg)
  expect_s3_class(v, "data.frame")
  expect_named(v, c("file", "expected", "observed", "drift", "missing"))
  expect_equal(nrow(v), 1L)
  expect_false(v$drift)
  expect_false(v$missing)
  expect_equal(v$expected, v$observed)
})

test_that("lnk_config_verify detects drift when file mutates", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg()
  # Mutate the file after manifest is recorded
  writeLines("changed\n", file.path(tmp, "rules.yaml"))
  cfg <- lnk_config(tmp)
  expect_warning(v <- lnk_config_verify(cfg), "drifted from recorded")
  expect_equal(nrow(v), 1L)
  expect_true(v$drift)
  expect_false(v$missing)
})

test_that("lnk_config_verify strict = TRUE errors on drift", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg()
  writeLines("changed\n", file.path(tmp, "rules.yaml"))
  cfg <- lnk_config(tmp)
  expect_error(lnk_config_verify(cfg, strict = TRUE),
               "drifted from recorded")
})

test_that("lnk_config_verify flags missing files", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg()
  cfg <- lnk_config(tmp)
  # Remove file AFTER lnk_config has loaded — lnk_config requires files
  # at load time, but lnk_config_verify is called later so files may
  # have been removed in the meantime.
  file.remove(file.path(tmp, "rules.yaml"))
  expect_warning(v <- lnk_config_verify(cfg))
  expect_true(v$missing)
  expect_true(v$drift)
  expect_true(is.na(v$observed))
})

test_that("lnk_config_verify returns empty tibble when no provenance block", {
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
  v <- lnk_config_verify(cfg)
  expect_s3_class(v, "data.frame")
  expect_equal(nrow(v), 0L)
  expect_named(v, c("file", "expected", "observed", "drift", "missing"))
})

test_that("lnk_config_verify rejects non-lnk_config input", {
  expect_error(lnk_config_verify(list()), "must be an lnk_config")
  expect_error(lnk_config_verify(NULL), "must be an lnk_config")
})

test_that("lnk_config_verify rejects non-logical strict", {
  cfg <- lnk_config("bcfishpass")
  expect_error(lnk_config_verify(cfg, strict = "yes"),
               "single TRUE or FALSE")
  expect_error(lnk_config_verify(cfg, strict = NA),
               "single TRUE or FALSE")
})

test_that("bundled bcfishpass config has no drift in shipped state", {
  skip_if_no_digest()
  cfg <- lnk_config("bcfishpass")
  v <- lnk_config_verify(cfg)
  expect_equal(sum(v$drift), 0L)
  expect_equal(sum(v$missing), 0L)
})

test_that("bundled default config has no drift in shipped state", {
  skip_if_no_digest()
  cfg <- lnk_config("default")
  v <- lnk_config_verify(cfg)
  expect_equal(sum(v$drift), 0L)
  expect_equal(sum(v$missing), 0L)
})
