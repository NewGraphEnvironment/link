# -- arg validation (no DB needed) -------------------------------------------

test_that("lnk_wsg_resolve rejects non-lnk_config cfg", {
  loaded_stub <- list(wsg_species_presence = data.frame(
    watershed_group_code = "ELKR",
    bt = "t", ch = "f", cm = "f", co = "f", ct = "f", dv = "f",
    pk = "f", rb = "f", sk = "f", st = "f", wct = "f",
    stringsAsFactors = FALSE
  ))
  expect_error(lnk_wsg_resolve(list(species = "BT"), loaded_stub),
               "cfg must be an lnk_config object")
})

test_that("lnk_wsg_resolve rejects non-list loaded", {
  cfg_stub <- structure(list(species = "BT"),
                        class = c("lnk_config", "list"))
  expect_error(lnk_wsg_resolve(cfg_stub, "not-a-list"),
               "loaded must be a named list")
})

test_that("lnk_wsg_resolve rejects malformed wsgs", {
  cfg_stub <- structure(list(species = "BT"),
                        class = c("lnk_config", "list"))
  loaded_stub <- list(wsg_species_presence = data.frame(
    watershed_group_code = "ELKR", bt = "t", stringsAsFactors = FALSE
  ))
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, wsgs = 1:3),
               "wsgs must be NULL or a non-empty character vector")
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, wsgs = character(0)),
               "wsgs must be NULL or a non-empty character vector")
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, wsgs = c("BULK", NA)),
               "wsgs must be NULL or a non-empty character vector")
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, wsgs = c("BULK", "")),
               "wsgs must be NULL or a non-empty character vector")
})

test_that("lnk_wsg_resolve rejects malformed expand", {
  cfg_stub <- structure(list(species = "BT"),
                        class = c("lnk_config", "list"))
  loaded_stub <- list(wsg_species_presence = data.frame(
    watershed_group_code = "ELKR", bt = "t", stringsAsFactors = FALSE
  ))
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, "BULK", expand = "yes"),
               "expand must be a single logical")
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, "BULK",
                               expand = c(TRUE, FALSE)),
               "expand must be a single logical")
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub, "BULK", expand = NA),
               "expand must be a single logical")
})

test_that("lnk_wsg_resolve rejects missing/empty wsg_species_presence", {
  cfg_stub <- structure(list(species = "BT"),
                        class = c("lnk_config", "list"))
  expect_error(lnk_wsg_resolve(cfg_stub, list()),
               "wsg_species_presence is missing or empty")
  empty_wp <- list(wsg_species_presence = data.frame(
    watershed_group_code = character(0),
    bt = character(0), stringsAsFactors = FALSE
  ))
  expect_error(lnk_wsg_resolve(cfg_stub, empty_wp),
               "wsg_species_presence is missing or empty")
})

test_that("lnk_wsg_resolve rejects missing species columns", {
  cfg_stub <- structure(list(species = c("BT", "GR")),
                        class = c("lnk_config", "list"))
  loaded_stub <- list(wsg_species_presence = data.frame(
    watershed_group_code = "ELKR", bt = "t", stringsAsFactors = FALSE
    # no `gr` column
  ))
  expect_error(lnk_wsg_resolve(cfg_stub, loaded_stub),
               "missing species columns: gr")
})

# -- stub-based province + strict modes (no DB) ------------------------------

# Stub row order DELIBERATELY NOT alphabetical so the province-mode sort
# is actually exercised (otherwise removing `sort()` from the function
# wouldn't break the test).
.wsg_stub <- function() {
  cfg <- structure(list(species = c("BT", "WCT")),
                   class = c("lnk_config", "list"))
  loaded <- list(wsg_species_presence = data.frame(
    watershed_group_code = c("CCCC", "AAAA", "BBBB"),
    bt  = c("t",    "f",    "f"),
    wct = c("f",    "t",    "f"),
    stringsAsFactors = FALSE
  ))
  list(cfg = cfg, loaded = loaded)
}

test_that("lnk_wsg_resolve province mode returns species-positive WSGs sorted", {
  s <- .wsg_stub()
  # Unsorted-result without sort() would be c("CCCC", "AAAA") (row order)
  expect_identical(lnk_wsg_resolve(s$cfg, s$loaded), c("AAAA", "CCCC"))
})

test_that("lnk_wsg_resolve strict mode preserves caller order when all WSGs are species-positive", {
  s <- .wsg_stub()
  # Caller-supplied order preserved (no sort in strict mode); no drops.
  expect_identical(
    lnk_wsg_resolve(s$cfg, s$loaded, wsgs = c("CCCC", "AAAA"), expand = FALSE),
    c("CCCC", "AAAA")
  )
})

test_that("lnk_wsg_resolve strict mode messages on dropped species-less WSGs", {
  s <- .wsg_stub()
  expect_message(
    res <- lnk_wsg_resolve(s$cfg, s$loaded,
                           wsgs = c("CCCC", "BBBB"), expand = FALSE),
    "dropped 1 species-less WSG"
  )
  expect_identical(res, "CCCC")
})

test_that("lnk_wsg_resolve strict mode upper-cases focal codes", {
  s <- .wsg_stub()
  expect_identical(
    lnk_wsg_resolve(s$cfg, s$loaded,
                    wsgs = c("cccc", "aaaa"), expand = FALSE),
    c("CCCC", "AAAA")
  )
})

# -- live DB (closure mode) --------------------------------------------------

test_that("lnk_wsg_resolve closure mode returns PARS+BULK 15-WSG closure DS-first", {
  skip_if_no_db()
  cfg    <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  expected <- c(
    "KISP", "KLUM", "LKEL", "LSKE", "MSKE", "USKE",
    "BULK", "FINA", "LBTN", "LPCE", "MORR", "PARA", "PCEA", "UPCE",
    "PARS"
  )
  expect_identical(
    lnk_wsg_resolve(cfg, loaded, wsgs = c("PARS", "BULK")),
    expected
  )
})

test_that("lnk_wsg_resolve province mode returns the full bundle-species list", {
  skip_if_no_db()
  cfg    <- lnk_config("bcfishpass")
  loaded <- lnk_load_overrides(cfg)
  res <- lnk_wsg_resolve(cfg, loaded)
  expect_true(length(res) >= 200L)
  expect_identical(res, sort(res))
  # Spot-check a few known bundle-species WSGs are present
  expect_true(all(c("BULK", "PARS", "ADMS") %in% res))
})
