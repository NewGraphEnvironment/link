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

# -- habitat thresholds path (#282) -------------------------------------------

test_that(".lnk_habitat_thresholds_csv returns the bundle's own CSV when declared", {
  cfg <- structure(list(
    name = "stub",
    files = list(parameters_habitat_thresholds = list(path = "/x/thresholds.csv"))
  ), class = c("lnk_config", "list"))
  expect_silent(p <- .lnk_habitat_thresholds_csv(cfg))
  expect_identical(p, "/x/thresholds.csv")
})

test_that(".lnk_habitat_thresholds_csv falls back to fresh's copy, loudly", {
  skip_if_not_installed("fresh")
  cfg <- structure(list(name = "stub", files = list()),
                   class = c("lnk_config", "list"))
  expect_message(p <- .lnk_habitat_thresholds_csv(cfg),
                 "declares no files\\$parameters_habitat_thresholds")
  expect_identical(p, system.file("extdata", "parameters_habitat_thresholds.csv",
                                  package = "fresh"))
})

# -- default_tuned: the first shipped thin bundle (#282) ----------------------

test_that("default_tuned extends default and overrides only its thresholds", {
  cfg <- lnk_config("default_tuned")
  def <- lnk_config("default")

  expect_identical(cfg$extends, "default")
  expect_identical(cfg$chain, c(cfg$dir, def$dir))
  expect_identical(cfg$pipeline$schema, "fresh_default_tuned")
  # Its own thresholds, everything else inherited from default.
  expect_identical(cfg$files$parameters_habitat_thresholds$path,
                   file.path(cfg$dir, "parameters_habitat_thresholds.csv"))
  expect_identical(cfg$files$parameters_fresh$path,
                   def$files$parameters_fresh$path)
  expect_identical(cfg$rules, def$rules)
  expect_identical(cfg$pipeline$break_order, def$pipeline$break_order)
  expect_setequal(names(cfg$files), names(def$files))
})

test_that("inherited provenance verifies against the parent's files", {
  # Keys are relative to the bundle that declared them. Resolved against the
  # child's dir they name nothing, and every inherited file reads as missing.
  v <- lnk_config_verify(lnk_config("default_tuned"))
  expect_gt(nrow(v), 1L)
  expect_false(any(v$missing))
  expect_false(any(v$byte_drift | v$shape_drift))
})

test_that("a tuned threshold reaches frs_params; bcfishpass stays put", {
  skip_if_not_installed("fresh")
  bcfp_before <- lnk_config_verify(lnk_config("bcfishpass"))

  tuned_dir <- file.path(withr::local_tempdir(), "tuned")
  dir.create(tuned_dir)
  th <- utils::read.csv(file.path(lnk_config("default_tuned")$dir,
                                  "parameters_habitat_thresholds.csv"),
                        check.names = FALSE)
  th$rear_gradient_max[th$species_code == "CH"] <- 0.0321
  utils::write.csv(th, file.path(tuned_dir, "parameters_habitat_thresholds.csv"),
                   row.names = FALSE, na = "")
  yaml::write_yaml(list(
    name = "tuned", extends = "default",
    files = list(parameters_habitat_thresholds =
                   list(path = "parameters_habitat_thresholds.csv"))),
    file.path(tuned_dir, "config.yaml"))

  p_tuned <- fresh::frs_params(
    csv = .lnk_habitat_thresholds_csv(lnk_config(tuned_dir)))
  p_default <- fresh::frs_params(
    csv = .lnk_habitat_thresholds_csv(lnk_config("default")))
  expect_equal(p_tuned$CH$rear_gradient_max, 0.0321)
  expect_equal(p_default$CH$rear_gradient_max, 0.0549)
  expect_equal(p_tuned$BT, p_default$BT)

  expect_identical(lnk_config_verify(lnk_config("bcfishpass")), bcfp_before)
})

test_that("a bundle can extend a bundle that itself extends (depth 3)", {
  # The middle bundle's rules/dimensions are already absolute after its own
  # merge; prefixing them with its dir again named a path that did not exist.
  leaf <- file.path(withr::local_tempdir(), "leaf")
  dir.create(leaf)
  yaml::write_yaml(list(name = "leaf", extends = "default_tuned"),
                   file.path(leaf, "config.yaml"))
  cfg <- lnk_config(leaf)
  def <- lnk_config("default")
  expect_identical(cfg$rules, def$rules)
  expect_identical(cfg$dimensions, def$dimensions)
  expect_length(cfg$chain, 3L)
  expect_identical(cfg$files$parameters_habitat_thresholds$path,
                   lnk_config("default_tuned")$files$parameters_habitat_thresholds$path)
  v <- lnk_config_verify(cfg)
  expect_false(any(v$missing | v$byte_drift | v$shape_drift))
})
