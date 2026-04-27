# lnk_config loads and validates config bundles under
# inst/extdata/configs/<name>/ (or any custom directory containing a
# config.yaml manifest).

test_that("lnk_config rejects invalid input", {
  expect_error(lnk_config(NULL), "single string")
  expect_error(lnk_config(c("a", "b")), "single string")
  expect_error(lnk_config(123), "single string")
})

test_that("lnk_config errors when bundle not found", {
  expect_error(
    lnk_config("definitely_not_a_real_config"),
    "No config bundle found"
  )
})

test_that("lnk_config loads the bundled bcfishpass variant", {
  cfg <- lnk_config("bcfishpass")

  expect_s3_class(cfg, "lnk_config")
  expect_equal(cfg$name, "bcfishpass")
  expect_true(dir.exists(cfg$dir))

  # Required file paths
  expect_true(file.exists(cfg$rules_yaml))
  expect_true(file.exists(cfg$dimensions_csv))

  # Required CSV tibbles
  expect_s3_class(cfg$parameters_fresh, "data.frame")
  expect_gt(nrow(cfg$parameters_fresh), 0)

  # Overrides list
  expect_type(cfg$overrides, "list")
  expect_true(all(vapply(cfg$overrides, is.data.frame, logical(1))))

  # Pipeline section from manifest
  expect_type(cfg$pipeline, "list")
  expect_true("break_order" %in% names(cfg$pipeline))
})

test_that("lnk_config does not shadow bundled names with local directories", {
  # Regression: bare names must resolve to bundled configs even if a
  # directory of the same name exists in the current working directory.
  # The old resolver checked `dir.exists(name)` first and silently used
  # the local dir.
  tmp_parent <- withr::local_tempdir()
  dir.create(file.path(tmp_parent, "bcfishpass"))
  # Write a decoy manifest so, if shadowed, the test would see "decoy"
  yaml::write_yaml(
    list(name = "decoy",
         files = list(rules_yaml = "r", dimensions_csv = "d",
                      parameters_fresh = "p")),
    file.path(tmp_parent, "bcfishpass", "config.yaml")
  )

  withr::with_dir(tmp_parent, {
    cfg <- lnk_config("bcfishpass")
    expect_equal(cfg$name, "bcfishpass")
    expect_false(grepl(normalizePath(tmp_parent), cfg$dir, fixed = TRUE))
  })
})

test_that("lnk_config errors on path that does not exist", {
  expect_error(
    lnk_config("./no/such/directory"),
    "No config directory found at path"
  )
})

test_that("lnk_config accepts a custom path", {
  bundled <- system.file("extdata", "configs", "bcfishpass", package = "link")
  cfg <- lnk_config(bundled)

  expect_s3_class(cfg, "lnk_config")
  expect_equal(cfg$name, "bcfishpass")
})

test_that("lnk_config prints a readable summary", {
  cfg <- lnk_config("bcfishpass")
  out <- capture.output(print(cfg))

  expect_match(out[1], "^<lnk_config> bcfishpass")
  expect_true(any(grepl("rules:", out)))
  expect_true(any(grepl("overrides:", out)))
})

test_that("lnk_config errors on missing manifest", {
  tmp <- withr::local_tempdir()
  # No config.yaml written
  expect_error(lnk_config(tmp), "config.yaml not found")
})

test_that("lnk_config errors on manifest missing required keys", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(description = "no name"),
    file.path(tmp, "config.yaml"))

  expect_error(lnk_config(tmp), "missing required keys.*name")
})

test_that("lnk_config errors on manifest missing required files entries", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(
    list(name = "x", files = list(rules_yaml = "r.yaml")),
    file.path(tmp, "config.yaml")
  )

  expect_error(lnk_config(tmp),
    "missing required entries.*dimensions_csv.*parameters_fresh")
})

test_that("lnk_config errors on manifest referencing missing file", {
  tmp <- withr::local_tempdir()
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
  # None of the referenced files exist

  expect_error(lnk_config(tmp),
    "references missing file")
})

test_that("lnk_config errors when an override file is missing", {
  tmp <- withr::local_tempdir()
  # Write valid required files
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
      ),
      overrides = list(
        missing_one = "overrides/nope.csv"
      )
    ),
    file.path(tmp, "config.yaml")
  )

  expect_error(lnk_config(tmp),
    "overrides.*references missing file")
})

# -- provenance parsing ------------------------------------------------------

test_that("bundled bcfishpass config exposes a provenance block", {
  cfg <- lnk_config("bcfishpass")
  expect_type(cfg$provenance, "list")
  expect_gt(length(cfg$provenance), 0L)
  # Each entry is a named list with at minimum `checksum`
  for (entry in cfg$provenance) {
    expect_true("checksum" %in% names(entry))
    expect_match(entry$checksum, "^sha256:[0-9a-f]{64}$")
  }
})

test_that("bundled default config exposes a provenance block", {
  cfg <- lnk_config("default")
  expect_type(cfg$provenance, "list")
  expect_gt(length(cfg$provenance), 0L)
})

test_that("cfg$provenance is NULL when manifest omits the block", {
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
  expect_null(cfg$provenance)
})
