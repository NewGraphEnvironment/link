# Mocked tests for `lnk_presence()`. Constructs presence tibbles
# in-memory; no DB or CSV-load round-trip needed.

mock_presence <- function() {
  tibble::tibble(
    watershed_group_code = c("ADMS", "ELKR", "HORS", "TEST_CH"),
    bt  = c("t", "t", "t", ""),
    ch  = c("t", "",  "t", "t"),
    cm  = c("",  "",  "",  ""),
    co  = c("t", "",  "t", ""),
    ct  = c("t", "t", "",  ""),
    dv  = c("t", "t", "",  ""),
    gr  = c("",  "t", "",  ""),
    ko  = c("",  "",  "",  ""),
    pk  = c("",  "",  "",  ""),
    rb  = c("t", "t", "t", ""),
    sk  = c("t", "",  "t", ""),
    st  = c("",  "",  "",  ""),
    wct = c("",  "t", "",  ""),
    notes = c("", "", "", "")
  )
}

test_that("ADMS basic — group expansion fires for salmon + ct_dv_rb", {
  pres <- lnk_presence(mock_presence(), "ADMS")
  # Raw: bt, ch, co, ct, dv, rb, sk
  # Group-expanded: cm, pk join salmon (since ch/co/sk already present)
  expect_setequal(pres$present,
                  c("bt", "ch", "cm", "co", "ct", "dv", "pk", "rb", "sk"))
  expect_setequal(pres$absent, c("gr", "ko", "st", "wct"))
  expect_equal(pres$aoi, "ADMS")
  expect_equal(nrow(pres$row), 1L)
})

test_that("ELKR — salmon all NULL, no group expansion fires", {
  pres <- lnk_presence(mock_presence(), "ELKR")
  expect_false(pres$is_present("ch"))
  expect_false(pres$is_present("cm"))
  expect_false(pres$is_present("co"))
  expect_false(pres$is_present("pk"))
  expect_false(pres$is_present("sk"))
  # ELKR has BT, CT, DV, GR, RB, WCT
  expect_true(pres$is_present("bt"))
  expect_true(pres$is_present("wct"))
  # ct_dv_rb group: all of ct/dv/rb already present, group expansion is a no-op here
  expect_true(pres$is_present("ct"))
})

test_that("HORS — st absent (ST column blank)", {
  pres <- lnk_presence(mock_presence(), "HORS")
  expect_false(pres$is_present("st"))
  expect_false(pres$is_present("wct"))
  expect_true(pres$is_present("bt"))
  expect_true(pres$is_present("ch"))
})

test_that("TEST_CH — single ch=t spreads to whole salmon group", {
  pres <- lnk_presence(mock_presence(), "TEST_CH")
  # Only ch=t literally; salmon-group expansion makes cm/co/pk/sk present
  for (sp in c("ch", "cm", "co", "pk", "sk")) {
    expect_true(pres$is_present(sp), info = sp)
  }
  # ct_dv_rb all blank, no expansion
  for (sp in c("ct", "dv", "rb")) {
    expect_false(pres$is_present(sp), info = sp)
  }
})

test_that("is_present is vectorised", {
  pres <- lnk_presence(mock_presence(), "ADMS")
  expect_equal(pres$is_present(c("bt", "st", "cm")),
               c(TRUE, FALSE, TRUE))
  expect_equal(pres$is_present(character(0)), logical(0))
})

test_that("groups = list() opt-out — no expansion", {
  pres <- lnk_presence(mock_presence(), "ADMS", groups = list())
  # Without group expansion, cm + pk stay absent (their literal columns are blank)
  expect_false(pres$is_present("cm"))
  expect_false(pres$is_present("pk"))
  expect_true(pres$is_present("ch"))
  expect_true(pres$is_present("sk"))
})

test_that("missing AOI errors with informative message", {
  expect_error(
    lnk_presence(mock_presence(), "NOPE"),
    regexp = "AOI 'NOPE' not in wsg_species_presence"
  )
  expect_error(
    lnk_presence(mock_presence(), "NOPE"),
    regexp = "ADMS"  # known WSGs listed
  )
})

test_that("logical-typed columns work (PostgreSQL load shape)", {
  # Postgres boolean columns come back as logical — make sure we accept both forms.
  tbl <- tibble::tibble(
    watershed_group_code = "PG",
    bt  = TRUE,
    ch  = NA,
    cm  = FALSE,
    co  = TRUE,
    ct  = NA,
    dv  = NA,
    gr  = NA,
    ko  = NA,
    pk  = FALSE,
    rb  = NA,
    sk  = TRUE,
    st  = NA,
    wct = NA
  )
  pres <- lnk_presence(tbl, "PG")
  expect_true(pres$is_present("bt"))
  expect_true(pres$is_present("ch"))   # group expansion via co/sk
  expect_true(pres$is_present("cm"))   # group expansion via co/sk
  expect_false(pres$is_present("st"))
  expect_false(pres$is_present("wct"))
})

# -- presence groups from the bundle (#292) ----------------------------------

test_that("each declaring bundle's presence groups equal lnk_presence()'s default", {
  for (b in c("default", "default_tuned", "bcfishpass")) {
    loaded <- lnk_load_overrides(lnk_config(b))
    expect_false(is.null(loaded$presence_groups), info = b)
    expect_identical(.lnk_presence_groups(loaded),
                     eval(formals(lnk_presence)$groups), info = b)
  }
})

test_that("a bundle with no presence_groups falls back to the default", {
  expect_identical(.lnk_presence_groups(list()),
                   eval(formals(lnk_presence)$groups))
})

test_that("presence groups keep file order and lower-case species", {
  loaded <- list(
    presence_groups = data.frame(group_code = c("b", "a", "b"),
                                 species_code = c("CH", "BT", "CO")),
    wsg_species_presence = mock_presence())
  expect_identical(.lnk_presence_groups(loaded),
                   list(b = c("ch", "co"), a = "bt"))
})

test_that("a malformed presence_groups table is refused", {
  pres <- mock_presence()
  pg <- function(g, s) {
    list(presence_groups = data.frame(group_code = g, species_code = s),
         wsg_species_presence = pres)
  }
  expect_error(.lnk_presence_groups(list(presence_groups = data.frame(
    group = "salmon", species_code = "ch"))), "lacks column")
  expect_error(.lnk_presence_groups(pg(character(0), character(0))), "empty")
  expect_error(.lnk_presence_groups(pg(c("salmon", ""), c("ch", "co"))),
               "empty group_code")
  expect_error(.lnk_presence_groups(pg(c("a", "b"), c("ch", "ch"))),
               "more than once: ch")
  expect_error(.lnk_presence_groups(pg("salmon", "chx")),
               "presence table lacks: chx")
})

test_that("the bundle's groups decide promotion and the acc spec (#292)", {
  cfg <- lnk_config("default")
  loaded <- lnk_load_overrides(cfg)
  base <- .lnk_vocabulary_spec_acc(cfg, loaded)
  narrow <- loaded
  narrow$presence_groups <- narrow$presence_groups[
    narrow$presence_groups$species_code != "pk", , drop = FALSE]
  expect_false(identical(base, .lnk_vocabulary_spec_acc(cfg, narrow)))
  expect_error(lnk_vocabulary_resolve(cfg, narrow), "no acc token")
})

test_that("no pipeline path calls lnk_presence() without the bundle's groups", {
  # Source-tree only: an installed package has no R/ or data-raw/.
  root <- testthat::test_path("..", "..")
  skip_if_not(dir.exists(file.path(root, "R")), "source tree not available")
  files <- c(list.files(file.path(root, "R"), "\\.R$", full.names = TRUE),
             file.path(root, "data-raw",
                       c("wsg_recompute_one.R", "habitat_variants_build.R")))
  n <- 0L
  for (f in files) {
    exprs <- tryCatch(parse(f, keep.source = FALSE), error = function(e) NULL)
    expect_false(is.null(exprs), info = f)
    calls <- list()
    walk <- function(e) {
      if (is.call(e)) {
        if (identical(e[[1]], as.name("lnk_presence"))) {
          calls[[length(calls) + 1L]] <<- e
        }
        for (a in as.list(e)[-1]) if (!missing(a)) walk(a)
      }
    }
    for (e in exprs) walk(e)
    for (cl in calls) {
      n <- n + 1L
      expect_true("groups" %in% names(cl),
                  info = paste(basename(f), deparse(cl)[1]))
    }
  }
  expect_gte(n, 5L)
})
