test_that("lnk_preflight_fresh passes against the real required set", {
  skip_if_not_installed("fresh")
  res <- lnk_preflight_fresh(quiet = TRUE)
  expect_true(res$ok)
  expect_length(res$missing, 0L)
  expect_length(res$missing_internal, 0L)
  expect_true(res$version_ok)
})

test_that("lnk_preflight_fresh fails when a required export is absent", {
  skip_if_not_installed("fresh")
  # No mocking needed: this name is absent by construction. The premise is
  # asserted rather than assumed, so a future fresh that DID export it fails
  # here — naming the stale fixture — instead of on the behaviour assertion.
  absent <- "frs_definitely_not_exported_by_fresh"
  expect_false(absent %in% getNamespaceExports(asNamespace("fresh")))

  res <- lnk_preflight_fresh(required = c("frs_wsg_outlets", absent),
                             quiet = TRUE)
  expect_false(res$ok)
  expect_identical(res$missing, absent)
  expect_match(res$message, absent, fixed = TRUE)
})

test_that("lnk_preflight_fresh fails when a required internal is absent", {
  skip_if_not_installed("fresh")
  res <- lnk_preflight_fresh(required_internal = ".frs_not_an_internal",
                             quiet = TRUE)
  expect_false(res$ok)
  expect_identical(res$missing_internal, ".frs_not_an_internal")
})

test_that("lnk_preflight_fresh fails a version floor above the installed", {
  skip_if_not_installed("fresh")
  res <- lnk_preflight_fresh(min_version = "999.0.0", quiet = TRUE)
  expect_false(res$ok)
  expect_false(res$version_ok)
})

test_that("lnk_preflight_fresh reports rather than errors when fresh is absent", {
  # The absent-package branch must return ok = FALSE, not throw — the shell
  # caller needs to distinguish "assertion failed" from "R itself blew up".
  #
  # Mocked at link's own `.lnk_fresh_ns()`, not at `base::asNamespace`:
  # mocking base breaks every other namespace lookup in the file, including
  # testthat's own, and turns this into an error rather than a result.
  local_mocked_bindings(
    .lnk_fresh_ns = function() NULL,
    .lnk_pkg_version_or_na = function(pkg) NA_character_)
  res <- lnk_preflight_fresh(quiet = TRUE)
  expect_false(res$ok)
  expect_true(is.na(res$version))
  expect_setequal(res$missing, .lnk_fresh_required())
  expect_match(res$message, "not installed")
})

test_that("the required set names only symbols fresh actually exports", {
  # Guards a typo in the curated list itself, which would otherwise make the
  # check fail on every host for a reason that has nothing to do with fresh.
  skip_if_not_installed("fresh")
  expect_length(
    setdiff(.lnk_fresh_required(), getNamespaceExports(asNamespace("fresh"))),
    0L)
  expect_true(exists(.lnk_fresh_required_internal(),
                     envir = asNamespace("fresh"), inherits = FALSE))
})

test_that("every fresh:: call site in link is declared as required", {
  # The drift guard. A PR that adds a `fresh::frs_new_thing()` call without
  # declaring it would otherwise ship a check that passes while the pipeline
  # breaks on any host with an older fresh.
  #
  # `.lnk_fresh_callsites()` walks link's own namespace, so it measures the
  # code that will actually run rather than a source directory that does not
  # exist in an installed package.
  callsites <- .lnk_fresh_callsites()
  expect_gt(length(callsites), 0L)   # an empty scan is not a pass
  expect_length(setdiff(callsites, .lnk_fresh_required()), 0L)
})

test_that(".lnk_fresh_callsites finds a symbol used only as a default argument", {
  # lnk_wsg_downstream_check(outlets = fresh::frs_wsg_outlets()) is reachable
  # only through formals(), and it is one of the two symbols link#246 is about.
  # A walker that read bodies alone would miss it and report a clean scan.
  expect_true("frs_wsg_outlets" %in% .lnk_fresh_callsites())
})

test_that(".lnk_fresh_floor parses the pin out of DESCRIPTION", {
  expect_identical(
    .lnk_fresh_floor(list(Imports = "DBI, fresh (>= 0.33.0), yaml")),
    "0.33.0")
  expect_identical(
    .lnk_fresh_floor(list(Imports = "DBI, fresh(>=1.2.3)")),
    "1.2.3")
  expect_identical(.lnk_fresh_floor(list(Imports = "DBI, yaml")), "0.0.0")
  expect_identical(.lnk_fresh_floor(list()), "0.0.0")
})

test_that("link's real DESCRIPTION declares a fresh floor", {
  # If fresh is ever moved back to Suggests or the floor dropped, this fires.
  # The floor is what forces pak to resolve the Remotes pin on the cyphers.
  expect_true(utils::compareVersion(.lnk_fresh_floor(), "0.33.0") >= 0L)
})

test_that("lnk_preflight_fresh validates its arguments", {
  expect_error(lnk_preflight_fresh(required = character(0)))
  expect_error(lnk_preflight_fresh(required = ""))
  expect_error(lnk_preflight_fresh(min_version = ""))
  expect_error(lnk_preflight_fresh(quiet = NA))
})
