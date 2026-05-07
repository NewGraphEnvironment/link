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
