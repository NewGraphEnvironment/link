# lnk_config returns a manifest-only object: paths, file declarations,
# pipeline knobs, and provenance. Tabular data is materialized via
# lnk_load_overrides() and tested separately.

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

test_that("lnk_config loads the bundled bcfishpass manifest", {
  cfg <- lnk_config("bcfishpass")

  expect_s3_class(cfg, "lnk_config")
  expect_equal(cfg$name, "bcfishpass")
  expect_true(dir.exists(cfg$dir))

  # Top-level path slots
  expect_true(file.exists(cfg$rules))
  expect_true(file.exists(cfg$dimensions))

  # Manifest-only: no data frames in the result
  expect_null(cfg$overrides)
  expect_null(cfg$habitat_classification)
  expect_null(cfg$observation_exclusions)

  # files: declared entries — each is a list with a resolved path
  expect_type(cfg$files, "list")
  expect_true(length(cfg$files) > 0L)
  for (entry in cfg$files) {
    expect_true("path" %in% names(entry))
    expect_true(file.exists(entry$path))
  }

  # crate-registered entries declare canonical_schema
  expect_true(
    "user_habitat_classification" %in% names(cfg$files))
  expect_equal(
    cfg$files$user_habitat_classification$canonical_schema,
    "bcfp/user_habitat_classification")

  # Pipeline section parsed from manifest
  expect_type(cfg$pipeline, "list")
  expect_true("break_order" %in% names(cfg$pipeline))

  # Species parsed from rules.yaml top-level keys
  expect_type(cfg$species, "character")
  expect_true(length(cfg$species) > 0L)
})

test_that("lnk_config does not shadow bundled names with local directories", {
  # Regression: bare names must resolve to bundled configs even if a
  # directory of the same name exists in the current working directory.
  tmp_parent <- withr::local_tempdir()
  dir.create(file.path(tmp_parent, "bcfishpass"))
  yaml::write_yaml(
    list(name = "decoy",
         rules = "r.yaml",
         dimensions = "d.csv",
         files = list(parameters_fresh = list(path = "p.csv"))),
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
  expect_true(any(grepl("files:", out)))
  expect_true(any(grepl("via crate", out)))
})

test_that("lnk_config errors on missing manifest", {
  tmp <- withr::local_tempdir()
  expect_error(lnk_config(tmp), "config.yaml not found")
})

test_that("lnk_config errors on manifest missing required keys", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(description = "no name"),
    file.path(tmp, "config.yaml"))

  expect_error(lnk_config(tmp), "missing required keys.*name")
})

test_that("lnk_config errors on manifest referencing missing rules file", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(parameters_fresh = list(path = "params.csv"))
    ),
    file.path(tmp, "config.yaml")
  )
  expect_error(lnk_config(tmp), "rules.*references missing file")
})

test_that("lnk_config errors when a files entry is missing path", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(name = "x"), file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(orphan = list(canonical_schema = "bcfp/foo"))
    ),
    file.path(tmp, "config.yaml")
  )
  expect_error(lnk_config(tmp), "missing required.*path")
})

test_that("lnk_config errors when a files entry path is missing", {
  tmp <- withr::local_tempdir()
  yaml::write_yaml(list(name = "x"), file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "x",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(absent = list(path = "nope.csv"))
    ),
    file.path(tmp, "config.yaml")
  )
  expect_error(lnk_config(tmp),
    "files\\$absent\\$path.*references missing file")
})

# -- extends: resolver -------------------------------------------------------

test_that("lnk_config resolves extends: by merging child onto parent", {
  parent_dir <- withr::local_tempdir()
  yaml::write_yaml(list(name = "parent"),
    file.path(parent_dir, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(parent_dir, "dims.csv"),
    row.names = FALSE)
  write.csv(data.frame(a = 1), file.path(parent_dir, "params.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "parent",
      rules = "rules.yaml",
      dimensions = "dims.csv",
      files = list(
        parameters_fresh = list(path = "params.csv"),
        from_parent = list(path = "params.csv")
      ),
      pipeline = list(break_order = c("a", "b"))
    ),
    file.path(parent_dir, "config.yaml")
  )

  child_dir <- withr::local_tempdir()
  write.csv(data.frame(b = 2), file.path(child_dir, "child_only.csv"),
    row.names = FALSE)
  yaml::write_yaml(
    list(
      name = "child",
      extends = parent_dir,
      files = list(
        from_child = list(path = "child_only.csv")
      ),
      pipeline = list(cluster = list(three_phase = TRUE))
    ),
    file.path(child_dir, "config.yaml")
  )

  cfg <- lnk_config(child_dir)
  expect_equal(cfg$name, "child")
  # Inherited files
  expect_true("parameters_fresh" %in% names(cfg$files))
  expect_true("from_parent" %in% names(cfg$files))
  # Inherited rules path resolves against parent dir
  expect_true(file.exists(cfg$rules))
  # Child added a file
  expect_true("from_child" %in% names(cfg$files))
  # Pipeline merged: parent's break_order + child's cluster
  expect_equal(cfg$pipeline$break_order, c("a", "b"))
  expect_equal(cfg$pipeline$cluster$three_phase, TRUE)
})

test_that("lnk_config detects circular extends chains", {
  a_dir <- withr::local_tempdir()
  b_dir <- withr::local_tempdir()
  yaml::write_yaml(list(name = "a", extends = b_dir),
    file.path(a_dir, "config.yaml"))
  yaml::write_yaml(list(name = "b", extends = a_dir),
    file.path(b_dir, "config.yaml"))
  expect_error(lnk_config(a_dir), "Circular `extends:` chain")
})

# -- provenance parsing ------------------------------------------------------

test_that("bundled bcfishpass config exposes a provenance block", {
  cfg <- lnk_config("bcfishpass")
  expect_type(cfg$provenance, "list")
  expect_gt(length(cfg$provenance), 0L)
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
  yaml::write_yaml(list(name = "x"), file.path(tmp, "rules.yaml"))
  write.csv(data.frame(a = 1), file.path(tmp, "dims.csv"),
    row.names = FALSE)
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
  expect_null(cfg$provenance)
})
