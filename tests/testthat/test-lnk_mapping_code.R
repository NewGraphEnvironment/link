
# -- Residence from dimensions.csv (link#189) -----------------------------------

copy_bundle_dims <- function(bundle, edit = NULL) {
  cfg <- lnk_config(bundle)
  d <- utils::read.csv(cfg$dimensions, stringsAsFactors = FALSE,
                       check.names = FALSE, colClasses = "character",
                       na.strings = character())
  if (!is.null(edit)) d <- edit(d)
  path <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  utils::write.csv(d, path, row.names = FALSE)
  cfg$dimensions <- path
  cfg
}

test_that("residence from dimensions.csv reproduces the sets coded before #189", {
  for (b in c("default", "bcfishpass")) {
    cfg <- lnk_config(b)
    sp <- utils::read.csv(cfg$dimensions)$species
    got <- .lnk_species_residence(cfg, sp)
    old <- .lnk_species_residence(NULL, sp)
    expect_identical(got, old, info = b)
    expect_setequal(got$spawn_only, c("cm", "pk"))
  }
  expect_identical(.lnk_species_residence(NULL, c("BT", "GR", "CH", "PK")),
                   list(resident = c("bt", "gr"), anadromous = c("ch", "pk"),
                        spawn_only = "pk"))
})

test_that("a bundle without the column falls back, and the sets follow species order", {
  cfg <- copy_bundle_dims("default", function(d) d[, names(d) != "residence"])
  expect_identical(.lnk_species_residence(cfg, c("CT", "CO")),
                   .lnk_species_residence(NULL, c("CT", "CO")))
  expect_identical(.lnk_species_residence(lnk_config("default"), character(0)),
                   list(resident = character(0), anadromous = character(0),
                        spawn_only = character(0)))
})

test_that("CT set anadromous reads the anadromous barrier sets", {
  cfg <- copy_bundle_dims("default", function(d) {
    d$residence[d$species == "CT"] <- "anadromous"; d
  })
  expect_identical(.lnk_species_residence(cfg, c("bt", "ct"))$anadromous, "ct")
  seen <- NULL
  local_mocked_bindings(
    lnk_mapping_code = function(..., species_resident, species_anadromous,
                                species_spawn_only) {
      seen <<- list(resident = species_resident,
                    anadromous = species_anadromous)
      invisible(NULL)
    },
    .lnk_db_execute = function(...) invisible(0L))
  local_mocked_bindings(
    dbQuoteLiteral = function(conn, x) paste0("'", x, "'"),
    dbQuoteString = function(conn, x) paste0("'", x, "'"),
    dbGetQuery = function(...) data.frame(column_name = character(0)),
    dbWithTransaction = function(conn, code) force(code),
    .package = "DBI")
  .lnk_mapping_code_persist(conn = NULL, schema = "s", aoi = "ADMS",
                            species = c("BT", "CT"), presence = NULL,
                            cfg = cfg)
  expect_identical(seen, list(resident = "bt", anadromous = "ct"))
})

test_that("a modelled species with no residence, or none of the two values, stops", {
  blank <- copy_bundle_dims("default", function(d) {
    d$residence[d$species == "GR"] <- ""; d
  })
  expect_error(.lnk_species_residence(blank, c("BT", "GR")),
               "resident or anadromous.*GR")
  odd <- copy_bundle_dims("default", function(d) {
    d$residence[d$species == "BT"] <- "fluvial"; d
  })
  expect_error(.lnk_species_residence(odd, "BT"), "BT")
  expect_error(.lnk_species_residence(lnk_config("default"), c("BT", "XX")),
               "no row.*XX")
})
