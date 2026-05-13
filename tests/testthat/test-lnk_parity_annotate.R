# Tests for lnk_parity_annotate — taxonomy lookup + fallback logic

mk_row <- function(wsg = "ADMS", species = "BT",
                   habitat_type = "spawning", unit = "km",
                   link_value = 100, ref_value = 100,
                   diff_pct = 0) {
  tibble::tibble(wsg = wsg, species = species,
                 habitat_type = habitat_type, unit = unit,
                 link_value = link_value, ref_value = ref_value,
                 diff_pct = diff_pct)
}

# ---------------------------------------------------------------------------
# Field matching: wildcards, scalars, arrays
# ---------------------------------------------------------------------------

test_that(".lnk_field_matches handles wildcards + arrays", {
  expect_true(link:::.lnk_field_matches("ADMS", "*"))
  expect_true(link:::.lnk_field_matches("ADMS", NULL))
  expect_true(link:::.lnk_field_matches("ADMS", "ADMS"))
  expect_true(link:::.lnk_field_matches("ADMS", c("ADMS", "BULK")))
  expect_false(link:::.lnk_field_matches("ADMS", "BULK"))
  expect_false(link:::.lnk_field_matches("ADMS", c("BULK", "PARS")))
})

# ---------------------------------------------------------------------------
# Pattern matching: 4 patterns + NA handling
# ---------------------------------------------------------------------------

test_that(".lnk_pattern_matches dispatches all 4 patterns correctly", {
  # link > bcfp
  expect_true(link:::.lnk_pattern_matches(
    mk_row(link_value = 110, ref_value = 100, diff_pct = 10),
    "link_gt_bcfp"))
  expect_false(link:::.lnk_pattern_matches(
    mk_row(link_value = 90, ref_value = 100, diff_pct = -10),
    "link_gt_bcfp"))

  # link < bcfp
  expect_true(link:::.lnk_pattern_matches(
    mk_row(link_value = 90, ref_value = 100, diff_pct = -10),
    "link_lt_bcfp"))
  expect_false(link:::.lnk_pattern_matches(
    mk_row(link_value = 110, ref_value = 100, diff_pct = 10),
    "link_lt_bcfp"))

  # bcfp_only: link=0, ref>0
  expect_true(link:::.lnk_pattern_matches(
    mk_row(link_value = 0, ref_value = 1000, diff_pct = -100),
    "bcfp_only"))
  expect_false(link:::.lnk_pattern_matches(
    mk_row(link_value = 1, ref_value = 1000, diff_pct = -99.9),
    "bcfp_only"))

  # link_only: link>0, ref=0 or NA
  expect_true(link:::.lnk_pattern_matches(
    mk_row(link_value = 100, ref_value = 0, diff_pct = NA_real_),
    "link_only"))
  expect_true(link:::.lnk_pattern_matches(
    mk_row(link_value = 100, ref_value = NA_real_, diff_pct = NA_real_),
    "link_only"))
  expect_false(link:::.lnk_pattern_matches(
    mk_row(link_value = 0, ref_value = 0, diff_pct = NA_real_),
    "link_only"))
})

test_that(".lnk_pattern_matches rejects NA diff_pct for gt/lt patterns", {
  expect_false(link:::.lnk_pattern_matches(
    mk_row(diff_pct = NA_real_), "link_gt_bcfp"))
  expect_false(link:::.lnk_pattern_matches(
    mk_row(diff_pct = NA_real_), "link_lt_bcfp"))
})

test_that(".lnk_pattern_matches errors on unknown pattern", {
  expect_error(
    link:::.lnk_pattern_matches(mk_row(), "fizz_buzz"),
    "Unknown pattern"
  )
})

# ---------------------------------------------------------------------------
# Entry-level matching: combines field + pattern + diff_range
# ---------------------------------------------------------------------------

test_that(".lnk_entry_matches respects diff_range filter", {
  entry <- list(id = "test", wsg = "ADMS", species = "BT",
                metric = "spawning", pattern = "link_gt_bcfp",
                diff_range = c(50, 100))
  # in range
  expect_true(link:::.lnk_entry_matches(
    mk_row(diff_pct = 75), entry))
  # below min
  expect_false(link:::.lnk_entry_matches(
    mk_row(diff_pct = 25), entry))
  # above max
  expect_false(link:::.lnk_entry_matches(
    mk_row(diff_pct = 150), entry))
  # exact boundary inclusive
  expect_true(link:::.lnk_entry_matches(
    mk_row(diff_pct = 50), entry))
  expect_true(link:::.lnk_entry_matches(
    mk_row(diff_pct = 100), entry))
})

test_that(".lnk_entry_matches errors on malformed diff_range", {
  entry <- list(id = "bad", wsg = "*", species = "*", metric = "*",
                pattern = "link_gt_bcfp", diff_range = c(10))
  expect_error(
    link:::.lnk_entry_matches(mk_row(diff_pct = 50), entry),
    "diff_range must have length 2"
  )
})

# ---------------------------------------------------------------------------
# First-match-wins semantics
# ---------------------------------------------------------------------------

test_that("lnk_parity_annotate respects first-match-wins ordering", {
  entries <- list(
    list(id = "specific", wsg = "ADMS", species = "BT",
         metric = "spawning", pattern = "link_gt_bcfp",
         class = "A", mechanism = "specific entry",
         refs = list("ref1"), status = "INTENTIONAL"),
    list(id = "wildcard", wsg = "*", species = "*", metric = "*",
         pattern = "link_gt_bcfp",
         class = "B", mechanism = "wildcard entry",
         refs = list("ref2"), status = "INTENTIONAL")
  )
  taxonomy <- list(entries = entries)
  out <- lnk_parity_annotate(
    mk_row(link_value = 110, ref_value = 100, diff_pct = 10),
    taxonomy = taxonomy)
  expect_equal(out$taxonomy_id, "specific")
  expect_equal(out$class, "A")
})

test_that("lnk_parity_annotate handles taxonomy entries missing optional fields", {
  entries <- list(
    list(id = "minimal", wsg = "*", species = "*",
         metric = "*", pattern = "link_gt_bcfp")
    # no class, no mechanism, no status, no refs
  )
  taxonomy <- list(entries = entries)
  out <- lnk_parity_annotate(mk_row(diff_pct = 10), taxonomy = taxonomy)
  expect_equal(out$taxonomy_id, "minimal")
  expect_true(is.na(out$class))
  expect_true(is.na(out$mechanism))
  expect_true(is.na(out$status))
  expect_equal(out$refs, "")  # empty paste collapse
})

test_that("lnk_parity_annotate falls through to second entry when first doesn't match", {
  entries <- list(
    list(id = "first", wsg = "BULK", species = "*",
         metric = "*", pattern = "link_gt_bcfp",
         class = "X", mechanism = "first entry",
         refs = list(), status = "INTENTIONAL"),
    list(id = "second", wsg = "ADMS", species = "*",
         metric = "*", pattern = "link_gt_bcfp",
         class = "Y", mechanism = "second entry",
         refs = list(), status = "INTENTIONAL")
  )
  taxonomy <- list(entries = entries)
  out <- lnk_parity_annotate(
    mk_row(wsg = "ADMS", diff_pct = 10),
    taxonomy = taxonomy)
  expect_equal(out$taxonomy_id, "second")
})

# ---------------------------------------------------------------------------
# Fallback classes: UNEXPLAINED, WITHIN_TOLERANCE, NOT_APPLICABLE
# ---------------------------------------------------------------------------

test_that("lnk_parity_annotate tags WITHIN_TOLERANCE for small unmatched residuals", {
  taxonomy <- list(entries = list())  # no entries -> always fall through
  out <- lnk_parity_annotate(
    mk_row(diff_pct = 1.5),  # < tolerance=2
    taxonomy = taxonomy)
  expect_equal(out$class, "WITHIN_TOLERANCE")
  expect_equal(out$status, "CLOSED")
})

test_that("lnk_parity_annotate tags UNEXPLAINED for large unmatched residuals", {
  taxonomy <- list(entries = list())
  out <- lnk_parity_annotate(
    mk_row(diff_pct = 15),  # > tolerance=2
    taxonomy = taxonomy)
  expect_equal(out$class, "UNEXPLAINED")
  expect_equal(out$status, "NEEDS_INVESTIGATION")
})

test_that("lnk_parity_annotate tags NOT_APPLICABLE for NA diff_pct", {
  taxonomy <- list(entries = list())
  out <- lnk_parity_annotate(
    mk_row(diff_pct = NA_real_, ref_value = NA_real_),
    taxonomy = taxonomy)
  expect_equal(out$class, "NOT_APPLICABLE")
  expect_true(is.na(out$status))
})

test_that("lnk_parity_annotate respects custom tolerance", {
  taxonomy <- list(entries = list())
  out_strict <- lnk_parity_annotate(
    mk_row(diff_pct = 1.5),
    taxonomy = taxonomy, tolerance = 1)
  expect_equal(out_strict$class, "UNEXPLAINED")  # 1.5 > 1

  out_loose <- lnk_parity_annotate(
    mk_row(diff_pct = 1.5),
    taxonomy = taxonomy, tolerance = 5)
  expect_equal(out_loose$class, "WITHIN_TOLERANCE")  # 1.5 < 5
})

# ---------------------------------------------------------------------------
# Input column name normalization (library shape vs data-raw wrapper shape)
# ---------------------------------------------------------------------------

test_that("lnk_parity_annotate accepts bcfishpass_value column name", {
  taxonomy <- list(entries = list())
  rollup <- tibble::tibble(
    wsg = "ADMS", species = "BT", habitat_type = "spawning",
    unit = "km", link_value = 100, bcfishpass_value = 100,
    diff_pct = 0)
  out <- lnk_parity_annotate(rollup, taxonomy = taxonomy)
  expect_true("ref_value" %in% names(out))
  expect_equal(out$ref_value, 100)
})

test_that("lnk_parity_annotate accepts ref_value column name", {
  taxonomy <- list(entries = list())
  rollup <- tibble::tibble(
    wsg = "ADMS", species = "BT", habitat_type = "spawning",
    unit = "km", link_value = 100, ref_value = 100, diff_pct = 0)
  out <- lnk_parity_annotate(rollup, taxonomy = taxonomy)
  expect_true("ref_value" %in% names(out))
})

test_that("lnk_parity_annotate errors when required columns are missing", {
  taxonomy <- list(entries = list())
  bad <- tibble::tibble(wsg = "ADMS", species = "BT", diff_pct = 0)
  expect_error(
    lnk_parity_annotate(bad, taxonomy = taxonomy),
    "missing required columns"
  )
})

# ---------------------------------------------------------------------------
# YAML file path
# ---------------------------------------------------------------------------

test_that("lnk_parity_annotate reads taxonomy from YAML path", {
  tmp <- tempfile(fileext = ".yml")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(c(
    "entries:",
    "  - id: smoke-yaml",
    "    wsg: '*'",
    "    species: '*'",
    "    metric: '*'",
    "    pattern: link_gt_bcfp",
    "    class: SMOKE",
    "    mechanism: yaml round-trip",
    "    refs: [smoke]",
    "    status: INTENTIONAL"
  ), tmp)
  out <- lnk_parity_annotate(mk_row(diff_pct = 10), taxonomy = tmp)
  expect_equal(out$taxonomy_id, "smoke-yaml")
  expect_equal(out$class, "SMOKE")
  expect_equal(out$refs, "smoke")
})

test_that("lnk_parity_annotate writes CSV when `to` is set", {
  taxonomy <- list(entries = list())
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  out <- lnk_parity_annotate(
    mk_row(diff_pct = 1.5),
    taxonomy = taxonomy, to = tmp)
  expect_true(file.exists(tmp))
  csv <- utils::read.csv(tmp, stringsAsFactors = FALSE)
  expect_equal(csv$class, "WITHIN_TOLERANCE")
})

# ---------------------------------------------------------------------------
# Multi-row rollup — different rows hit different entries / fallbacks
# ---------------------------------------------------------------------------

test_that("lnk_parity_annotate annotates a multi-row rollup correctly", {
  taxonomy <- list(entries = list(
    list(id = "asymmetry", wsg = "*", species = "*",
         metric = c("lake_rearing", "wetland_rearing"),
         pattern = "bcfp_only",
         class = "MEASUREMENT_ASYMMETRY",
         mechanism = "centerline vs polygon",
         refs = list("doc"), status = "INTENTIONAL")
  ))
  rollup <- dplyr::bind_rows(
    mk_row(habitat_type = "lake_rearing", link_value = 0,
           ref_value = 100, diff_pct = -100),
    mk_row(habitat_type = "spawning", link_value = 105,
           ref_value = 100, diff_pct = 5),
    mk_row(habitat_type = "rearing", link_value = 100.5,
           ref_value = 100, diff_pct = 0.5),
    mk_row(habitat_type = "rearing", link_value = 100,
           ref_value = NA_real_, diff_pct = NA_real_)
  )
  out <- lnk_parity_annotate(rollup, taxonomy = taxonomy)
  expect_equal(out$class[1], "MEASUREMENT_ASYMMETRY")
  expect_equal(out$class[2], "UNEXPLAINED")        # 5% > tol
  expect_equal(out$class[3], "WITHIN_TOLERANCE")   # 0.5% < tol
  expect_equal(out$class[4], "NOT_APPLICABLE")     # NA diff_pct
})

# ---------------------------------------------------------------------------
# Real bundled YAML round-trip
# ---------------------------------------------------------------------------

test_that("lnk_parity_annotate works against the bundled taxonomy YAML", {
  yml_path <- file.path("..", "..", "research",
                         "bcfp_divergence_taxonomy.yml")
  skip_if_not(file.exists(yml_path),
              "bundled taxonomy YAML not present in test working dir")

  # MEASUREMENT_ASYMMETRY: lake_rearing with link=0, ref>0
  rollup <- mk_row(species = "BT", habitat_type = "lake_rearing",
                   unit = "ha", link_value = 0, ref_value = 14290,
                   diff_pct = -100)
  out <- lnk_parity_annotate(rollup, taxonomy = yml_path)
  expect_equal(out$class, "MEASUREMENT_ASYMMETRY")
  expect_equal(out$taxonomy_id, "lake-wetland-polygon-asymmetry")
})
