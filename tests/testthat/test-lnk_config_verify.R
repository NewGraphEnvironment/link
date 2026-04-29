# lnk_config_verify recomputes byte + shape checksums for every
# provenanced file and reports drift on each axis. Tests use temp
# config bundles to control the file state precisely.

skip_if_no_digest <- function() {
  testthat::skip_if_not_installed("digest")
}

# Helper: build a tmp config dir with a known rules.yaml file + a
# provenance entry referencing the file's actual byte and shape
# checksums. Returns the tmp dir path. By default the rules.yaml file
# has a single header line "alpha" — `header` controls that line.
.build_tmp_cfg <- function(header = "alpha") {
  skip_if_no_digest()
  tmp <- withr::local_tempdir(.local_envir = parent.frame())
  rules_path <- file.path(tmp, "rules.yaml")
  dims_path  <- file.path(tmp, "dims.csv")
  params_path <- file.path(tmp, "params.csv")

  writeLines(header, rules_path)
  write.csv(data.frame(a = 1), dims_path, row.names = FALSE)
  write.csv(data.frame(a = 1), params_path, row.names = FALSE)

  rules_byte <- digest::digest(file = rules_path, algo = "sha256")
  rules_shape <- link:::.lnk_shape_fingerprint(rules_path)

  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(
        parameters_fresh = list(path = "params.csv")
      ),
      provenance = list(
        rules.yaml = list(
          source         = "test (hand-authored)",
          checksum       = paste0("sha256:", rules_byte),
          shape_checksum = rules_shape
        )
      )
    ),
    file.path(tmp, "config.yaml")
  )
  tmp
}

VERIFY_COLS <- c("file",
                 "byte_expected", "byte_observed", "byte_drift",
                 "shape_expected", "shape_observed", "shape_drift",
                 "missing")

test_that("lnk_config_verify returns clean tibble when no drift", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg()
  cfg <- lnk_config(tmp)
  v <- lnk_config_verify(cfg)
  expect_s3_class(v, "data.frame")
  expect_named(v, VERIFY_COLS)
  expect_equal(nrow(v), 1L)
  expect_false(v$byte_drift)
  expect_false(v$shape_drift)
  expect_false(v$missing)
  expect_equal(v$byte_expected, v$byte_observed)
  expect_equal(v$shape_expected, v$shape_observed)
})

test_that("byte drift detected when file content changes (header preserved)", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg(header = "alpha")
  cfg <- lnk_config(tmp)
  # Append a row but keep the header line — byte changes, shape doesn't
  cat("alpha\nbeta\n", file = file.path(tmp, "rules.yaml"))
  expect_warning(v <- lnk_config_verify(cfg), "drifted")
  expect_true(v$byte_drift)
  expect_false(v$shape_drift)
})

test_that("shape drift detected when header line changes", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg(header = "alpha")
  cfg <- lnk_config(tmp)
  # Change the header — both byte and shape drift
  writeLines("alpha,beta", file.path(tmp, "rules.yaml"))
  expect_warning(v <- lnk_config_verify(cfg), "drifted")
  expect_true(v$byte_drift)
  expect_true(v$shape_drift)
})

test_that("strict = TRUE errors on either drift kind", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg(header = "alpha")
  cfg <- lnk_config(tmp)
  cat("alpha\nbeta\n", file = file.path(tmp, "rules.yaml"))  # byte only
  expect_error(lnk_config_verify(cfg, strict = TRUE), "drifted")

  tmp2 <- .build_tmp_cfg(header = "alpha")
  cfg2 <- lnk_config(tmp2)
  writeLines("renamed", file.path(tmp2, "rules.yaml"))  # both
  expect_error(lnk_config_verify(cfg2, strict = TRUE), "drifted")
})

test_that("missing file flips both drift columns and sets missing = TRUE", {
  skip_if_no_digest()
  tmp <- .build_tmp_cfg()
  cfg <- lnk_config(tmp)
  file.remove(file.path(tmp, "rules.yaml"))
  expect_warning(v <- lnk_config_verify(cfg))
  expect_true(v$missing)
  expect_true(v$byte_drift)
  expect_true(v$shape_drift)
  expect_true(is.na(v$byte_observed))
  expect_true(is.na(v$shape_observed))
})

test_that("provenance without shape_checksum: shape_drift stays FALSE", {
  # Older bundles that have only `checksum:` and no `shape_checksum:`
  # field stay backward-compatible — verify just doesn't flag shape
  # drift since there's no recorded shape to compare against.
  skip_if_no_digest()
  tmp <- withr::local_tempdir()
  rules_path <- file.path(tmp, "rules.yaml")
  writeLines("alpha", rules_path)
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"), row.names = FALSE)
  write.csv(data.frame(a = 1), file.path(tmp, "params.csv"), row.names = FALSE)
  rules_byte <- digest::digest(file = rules_path, algo = "sha256")
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(
        parameters_fresh = list(path = "params.csv")
      ),
      provenance = list(
        rules.yaml = list(
          source = "test (legacy, no shape)",
          checksum = paste0("sha256:", rules_byte)
        )
      )
    ),
    file.path(tmp, "config.yaml")
  )
  cfg <- lnk_config(tmp)
  v <- lnk_config_verify(cfg)
  expect_false(v$byte_drift)
  expect_true(is.na(v$shape_expected))
  expect_false(v$shape_drift)
})

test_that("returns empty tibble when no provenance block", {
  tmp <- withr::local_tempdir()
  file.create(file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"), row.names = FALSE)
  write.csv(data.frame(a = 1), file.path(tmp, "params.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(parameters_fresh = list(path = "params.csv"))
    ),
    file.path(tmp, "config.yaml")
  )
  cfg <- lnk_config(tmp)
  v <- lnk_config_verify(cfg)
  expect_s3_class(v, "data.frame")
  expect_equal(nrow(v), 0L)
  expect_named(v, VERIFY_COLS)
})

test_that("rejects non-lnk_config input", {
  expect_error(lnk_config_verify(list()), "must be an lnk_config")
  expect_error(lnk_config_verify(NULL), "must be an lnk_config")
})

test_that("rejects non-logical strict", {
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
  expect_equal(sum(v$byte_drift), 0L)
  expect_equal(sum(v$shape_drift), 0L)
  expect_equal(sum(v$missing), 0L)
})

test_that("bundled default config has no drift in shipped state", {
  skip_if_no_digest()
  cfg <- lnk_config("default")
  v <- lnk_config_verify(cfg)
  expect_equal(sum(v$byte_drift), 0L)
  expect_equal(sum(v$shape_drift), 0L)
  expect_equal(sum(v$missing), 0L)
})

test_that(".lnk_shape_fingerprint returns NA for empty file", {
  tmp <- withr::local_tempfile()
  file.create(tmp)
  expect_true(is.na(link:::.lnk_shape_fingerprint(tmp)))
})

test_that(".lnk_shape_fingerprint normalizes trailing whitespace", {
  tmp1 <- withr::local_tempfile()
  tmp2 <- withr::local_tempfile()
  writeLines("a,b,c", tmp1)
  writeLines("a,b,c   ", tmp2)  # trailing spaces
  expect_equal(link:::.lnk_shape_fingerprint(tmp1),
               link:::.lnk_shape_fingerprint(tmp2))
})
