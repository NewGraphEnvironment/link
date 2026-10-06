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

# -- habitat model per watershed group (#299) ---------------------------------

test_that(".lnk_wsg_model resolves each group, unlisted groups on cw", {
  skip_if_not_installed("fresh")
  pm <- data.frame(watershed_group_code = c("ADMS", "BULK"),
                   model = c("mad", "cw"), stringsAsFactors = FALSE)
  expect_identical(.lnk_wsg_model(pm, c("BULK", "ADMS", "ZZZZ")),
                   c("cw", "mad", "cw"))
})

test_that(".lnk_wsg_model rejects a model other than cw or mad", {
  skip_if_not_installed("fresh")
  pm <- data.frame(watershed_group_code = "ADMS", model = "MAD")
  expect_error(.lnk_wsg_model(pm, "ADMS"), "must be \"cw\" or \"mad\"")
})

test_that(".lnk_habitat_method_read keeps a group coded NA as a code", {
  csv <- withr::local_tempfile(fileext = ".csv")
  writeLines("watershed_group_code,model\nNA,mad", csv)
  pm <- .lnk_habitat_method_read(csv)
  expect_identical(pm$watershed_group_code, "NA")
  skip_if_not_installed("fresh")
  expect_identical(.lnk_wsg_model(pm, "NA"), "mad")
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

test_that("default_tuned differs from default only in the #284 and #302 cells", {
  # Every other value was examined and kept (research/habitat_thresholds.md);
  # a cell outside this list changing is an untracked calibration.
  rd <- function(cfg) {
    utils::read.csv(cfg$files$parameters_habitat_thresholds$path,
                    check.names = FALSE, stringsAsFactors = FALSE)
  }
  tuned <- rd(lnk_config("default_tuned"))
  def <- rd(lnk_config("default"))
  expect_identical(names(tuned), names(def))
  expect_identical(tuned$species_code, def$species_code)

  changed <- which(!mapply(identical, tuned, def))
  diffs <- do.call(rbind, lapply(names(tuned)[changed], function(col) {
    i <- which(!mapply(identical, tuned[[col]], def[[col]]))
    data.frame(species_code = tuned$species_code[i], column = col,
               default = def[[col]][i], tuned = tuned[[col]][i])
  }))
  diffs <- diffs[order(diffs$species_code, diffs$column), ]
  rownames(diffs) <- NULL
  # #302: observed MAD minima, against default's width-converted ones (#307).
  # Both bundles leave the maxima open, so only the minima differ.
  mad <- data.frame(
    species_code = c(rep("BT", 2), rep("GR", 2), "KO", rep("RB", 2)),
    column = c("rear_mad_min", "spawn_mad_min", "rear_mad_min", "spawn_mad_min",
               "spawn_mad_min", "rear_mad_min", "spawn_mad_min"),
    default = c(0.021, 0.041, 0.021, 0.2, 0.041, 0.021, 0.041),
    tuned = c(0.078, 0.078, 0.97, 0.96, 0.57, 0.019, 0.011))
  want <- rbind(data.frame(species_code = "BT", column = "rear_gradient_max",
                           default = 0.1049, tuned = 0.1349), mad)
  want <- want[order(want$species_code, want$column), ]
  rownames(want) <- NULL
  expect_equal(diffs, want)
})

test_that("default's MAD ranges for BT, GR, KO and RB are its width minima converted (#307)", {
  # Median mad_m3s at each width minimum (data-raw/query_width_mad_equivalent.R),
  # floored to two significant figures; maxima open. KO rears in lakes only.
  th <- utils::read.csv(lnk_config("default")$files$parameters_habitat_thresholds$path,
                        stringsAsFactors = FALSE)
  rownames(th) <- th$species_code
  cols <- c("spawn_mad_min", "spawn_mad_max", "rear_mad_min", "rear_mad_max")
  want <- data.frame(
    spawn_mad_min = c(0.041, 0.2, 0.041, 0.041),
    spawn_mad_max = 9999,
    rear_mad_min = c(0.021, 0.021, NA, 0.021),
    rear_mad_max = c(9999, 9999, NA, 9999),
    row.names = c("BT", "GR", "KO", "RB"))
  expect_equal(th[rownames(want), cols], want)
  # No half-open range in any row: fresh tests BETWEEN min AND max.
  for (st in c("spawn", "rear")) {
    expect_identical(is.na(th[[paste0(st, "_mad_min")]]),
                     is.na(th[[paste0(st, "_mad_max")]]), info = st)
  }
})

test_that("inherited provenance verifies against the parent's files", {
  # Keys are relative to the bundle that declared them. Resolved against the
  # child's dir they name nothing, and every inherited file reads as missing.
  v <- lnk_config_verify(lnk_config("default_tuned"))
  expect_gt(nrow(v), 1L)
  expect_false(any(v$missing))
  expect_false(any(v$byte_drift | v$shape_drift))
})

test_that("every shipped bundle's provenance verifies clean", {
  bundles <- basename(list.dirs(system.file("extdata", "configs",
                                            package = "link"),
                                recursive = FALSE))
  expect_gt(length(bundles), 0L)
  for (b in bundles) {
    v <- lnk_config_verify(lnk_config(b))
    expect_false(any(v$missing), info = b)
    expect_false(any(v$byte_drift | v$shape_drift), info = b)
  }
})

test_that("the method table is frozen, not enrolled in csv-sync (#286)", {
  # data-raw/sync_bcfishpass_csvs.R syncs (and auto-merges) every bcfishpass
  # bundle entry whose source is exactly the bcfishpass repo URL. A cw -> mad
  # flip upstream would then change the model of `default` with no review.
  for (b in c("bcfishpass", "default", "default_extrabreaks",
              "default_rearbreaks")) {
    src <- lnk_config(b)$provenance[["parameters_habitat_method.csv"]]$source
    expect_false(is.null(src), info = b)
    expect_false(identical(src, "https://github.com/smnorris/bcfishpass"),
                 info = b)
  }
})

test_that("a tuned threshold reaches frs_params; bcfishpass stays put", {
  skip_if_not_installed("fresh")
  bcfp_before <- lnk_config_verify(lnk_config("bcfishpass"))

  tuned_dir <- file.path(withr::local_tempdir(), "tuned")
  dir.create(tuned_dir)
  # Start from default's thresholds: default_tuned's own carry calibrated
  # CH/BT values (#284), so BT would differ before this test changes anything.
  th <- utils::read.csv(file.path(lnk_config("default")$dir,
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

test_that("a relative extends: resolves against the child bundle, not the cwd", {
  root <- withr::local_tempdir()
  base <- file.path(root, "base")
  leaf <- file.path(root, "leaf")
  dir.create(base)
  dir.create(leaf)
  file.copy(file.path(lnk_config("default")$dir, "config.yaml"), base)
  m <- yaml::read_yaml(file.path(base, "config.yaml"))
  # Point the copied manifest's files back at the bundled default.
  def <- lnk_config("default")
  m$rules <- def$rules
  m$dimensions <- def$dimensions
  m$files <- lapply(def$files, function(f) f["path"])
  m$provenance <- NULL
  yaml::write_yaml(m, file.path(base, "config.yaml"))
  yaml::write_yaml(list(name = "leaf", extends = "../base"),
                   file.path(leaf, "config.yaml"))

  elsewhere <- withr::local_tempdir()
  cfg <- withr::with_dir(elsewhere, lnk_config(leaf))
  expect_identical(cfg$chain[[2]], normalizePath(base))
})
