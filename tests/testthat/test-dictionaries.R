# Contract tests for the config data dictionaries.
#
# `data-raw/audit_configs.R` is the pre-trifecta gate, but `data-raw/` is
# .Rbuildignore'd — it never runs for an installed package or in CI. These
# tests are the durable guard: the dictionaries must stay in lockstep with
# the CSVs they describe, or a silently-undocumented column ships.
#
# The `owner` partition encoded here is not a local judgement call. It was
# settled by NewGraphEnvironment/fresh#129 (shipped fresh 0.12.7): fresh owns
# the network-engine params (access + cluster geometry); link owns the
# fish-passage interpretation params (`observation_*`), which were deleted
# from fresh's own parameters_fresh.csv because "fish passage interpretation
# belongs in link, not the network engine".

cfg_dir <- function() system.file("extdata", "configs", package = "link")

bundle_names <- function() basename(list.dirs(cfg_dir(), recursive = FALSE))

read_csv_plain <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

# `nzchar(NA)` is TRUE, so a bare nzchar() check would wave through an NA
# cell — exactly the half-authored row these tests exist to catch.
filled <- function(x) !is.na(x) & nzchar(trimws(x))

dict_read <- function(stem) {
  read_csv_plain(file.path(cfg_dir(), paste0("dictionary_", stem, ".csv")))
}

bundle_cols <- function(bundle, stem) {
  names(read_csv_plain(file.path(cfg_dir(), bundle, paste0(stem, ".csv"))))
}

# Union of a stem's columns across every bundle. Bundles legitimately carry
# different column subsets (bcfishpass's dimensions.csv omits two columns the
# default bundles use), so the dictionary is checked against the union, not
# against any single bundle.
bundle_cols_union <- function(stem) {
  unique(unlist(lapply(bundle_names(), bundle_cols, stem = stem)))
}

# -- dictionary_dimensions ---------------------------------------------------

test_that("dictionary_dimensions has the expected shape", {
  d <- dict_read("dimensions")

  expect_true(all(c("column", "type", "group", "applies_to",
                    "default_when_absent", "description", "emits",
                    "related") %in% names(d)))
  expect_false(any(duplicated(d$column)))
  expect_true(all(filled(d$column)))
  expect_true(all(filled(d$description)))
})

test_that("dictionary_dimensions covers every bundle's dimensions.csv", {
  d <- dict_read("dimensions")

  for (b in bundle_names()) {
    undocumented <- setdiff(bundle_cols(b, "dimensions"), d$column)
    expect_identical(
      undocumented, character(0),
      info = sprintf("bundle %s has undocumented dimensions columns: %s",
                     b, paste(undocumented, collapse = ", "))
    )
  }
})

test_that("dictionary_dimensions has no rows for columns that do not exist", {
  d <- dict_read("dimensions")
  expect_setequal(d$column, bundle_cols_union("dimensions"))
})

# -- dictionary_parameters_fresh ---------------------------------------------

test_that("dictionary_parameters_fresh has the expected shape", {
  d <- dict_read("parameters_fresh")

  expect_true(all(c("column", "type", "group", "owner", "consumed_by",
                    "default_when_absent", "description",
                    "related") %in% names(d)))
  expect_false(any(duplicated(d$column)))
  expect_true(all(filled(d$column)))
  expect_true(all(filled(d$description)))
  expect_true(all(filled(d$consumed_by)))
})

test_that("dictionary_parameters_fresh covers every bundle's parameters_fresh.csv", {
  d <- dict_read("parameters_fresh")

  for (b in bundle_names()) {
    undocumented <- setdiff(bundle_cols(b, "parameters_fresh"), d$column)
    expect_identical(
      undocumented, character(0),
      info = sprintf("bundle %s has undocumented parameters_fresh columns: %s",
                     b, paste(undocumented, collapse = ", "))
    )
  }
})

test_that("dictionary_parameters_fresh has no rows for columns that do not exist", {
  d <- dict_read("parameters_fresh")
  expect_setequal(d$column, bundle_cols_union("parameters_fresh"))
})

# -- the fresh <-> link ownership partition (fresh#129) ----------------------

test_that("every parameters_fresh column declares a valid owner", {
  # Domain check only. Asserting set-equality here would conflate "no bogus
  # owner value" with "both owners are in use" — the link side is pinned by
  # the next test, and a failure there should not also fire here.
  d <- dict_read("parameters_fresh")
  expect_true(all(filled(d$owner)))
  expect_true(all(d$owner %in% c("fresh", "link")))
})

test_that("link owns exactly the observation_* interpretation columns", {
  d <- dict_read("parameters_fresh")

  link_owned <- d$column[d$owner == "link"]
  expect_setequal(link_owned, grep("^observation_", d$column, value = TRUE))
})

test_that("fresh-owned columns match fresh's canonical parameters_fresh.csv", {
  # Cross-package: fresh is Suggests (>= 0.32.0). The contract is that link's
  # bundles are fresh's column set plus link-owned extensions — a column fresh
  # adds that link is missing means link's copy may no longer load through
  # frs_habitat(). Mirrors data-raw/audit_configs.R section 3b.
  skip_if_not_installed("fresh")

  canonical <- system.file("extdata", "parameters_fresh.csv", package = "fresh")
  skip_if(!nzchar(canonical), "fresh's bundled parameters_fresh.csv not found")

  d <- dict_read("parameters_fresh")
  expect_setequal(d$column[d$owner == "fresh"],
                  names(read_csv_plain(canonical)))
})
