
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
    d$residence[d$species == "CT"] <- "anadromous"
    d
  })
  expect_identical(.lnk_species_residence(cfg, c("bt", "ct"))$anadromous, "ct")
  seen <- NULL
  m_mc <- function(..., species_resident, species_anadromous,
                   species_spawn_only) {
    seen <<- list(resident = species_resident, anadromous = species_anadromous)
    invisible(NULL)
  }
  local_mocked_bindings(lnk_mapping_code = m_mc,
                        .lnk_db_execute = function(...) invisible(0L))
  quote_lit <- function(conn, x) paste0("'", x, "'")
  local_mocked_bindings(dbQuoteLiteral = quote_lit, dbQuoteString = quote_lit,
                        dbGetQuery = function(...) {
                          data.frame(column_name = character(0))
                        },
                        dbWithTransaction = function(conn, code) force(code),
                        .package = "DBI")
  .lnk_mapping_code_persist(conn = NULL, schema = "s", aoi = "ADMS",
                            species = c("BT", "CT"), presence = NULL,
                            cfg = cfg)
  expect_identical(seen, list(resident = "bt", anadromous = "ct"))
})

test_that("a modelled species with no residence, or none of the two values, stops", {
  blank <- copy_bundle_dims("default", function(d) {
    d$residence[d$species == "GR"] <- ""
    d
  })
  expect_error(.lnk_species_residence(blank, c("BT", "GR")),
               "resident or anadromous.*GR")
  odd <- copy_bundle_dims("default", function(d) {
    d$residence[d$species == "BT"] <- "fluvial"
    d
  })
  expect_error(.lnk_species_residence(odd, "BT"), "BT")
  expect_error(.lnk_species_residence(lnk_config("default"), c("BT", "XX")),
               "no row.*XX")
})

# -- lnk_mapping_code(): queries, pivot, presence (link#191, link#351) ---------

# A fake database answering the four reads lnk_mapping_code() makes.
mc_db <- function(access = NULL, habitat = NULL, persist = TRUE) {
  access <- access %||% data.frame(
    id_segment = 1:3, watershed_group_code = "ADMS",
    has_barriers_bt_dnstr = c(FALSE, FALSE, TRUE),
    has_barriers_ch_dnstr = c(FALSE, FALSE, FALSE),
    has_barriers_anthropogenic_dnstr = c(FALSE, TRUE, FALSE),
    has_barriers_pscis_dnstr = FALSE, has_barriers_dams_dnstr = FALSE)
  habitat <- habitat %||% data.frame(
    id_segment = c(1L, 2L, 1L), species_code = c("bt", "bt", "ch"),
    spawning = c(1L, 0L, 0L), rearing = c(0L, 1L, 0L))
  sql_seen <- character(0)
  list(
    sql = function() sql_seen,
    dbGetQuery = function(conn, sql, ...) {
      sql_seen <<- c(sql_seen, sql)
      if (grepl("information_schema.columns", sql)) {
        if (persist) data.frame(x = 1L) else data.frame(x = integer(0))
      } else if (grepl("species_code", sql)) {
        habitat
      } else if (grepl("feature_code", sql)) {
        data.frame(id_segment = 1:3, feature_code = "GA24850000")
      } else {
        access
      }
    })
}
mc_call <- function(db, ...) {
  with_mocked_bindings(
    dbGetQuery = db$dbGetQuery,
    dbQuoteLiteral = function(conn, x, ...) paste0("'", x, "'"),
    dbQuoteString = function(conn, x, ...) paste0("'", x, "'"),
    .package = "DBI",
    lnk_mapping_code(structure(list(), class = "DBIConnection"),
                     table_access = "s.streams_access",
                     table_habitat = "s.streams_habitat_long_vw",
                     table_streams = "s.streams", aoi = "ADMS",
                     species_resident = "bt", species_anadromous = "ch",
                     species_spawn_only = character(0), ...))
}

test_that("presence = NULL derives presence and runs (#351)", {
  db <- mc_db()
  derived <- mc_call(db)
  # bt has habitat, ch has none: ch reads "" everywhere.
  expect_identical(derived$mapping_code_bt,
                   c("SPAWN;NONE", "REAR;MODELLED", ""))
  expect_true(all(derived$mapping_code_ch == ""))
  pres <- lnk_presence(
    data.frame(watershed_group_code = "ADMS", bt = "t", ch = ""), "ADMS",
    groups = list())
  expect_identical(derived, mc_call(mc_db(), presence = pres))
})

test_that("a persist access table is read by group, a working one by segment (#203)", {
  db <- mc_db(persist = TRUE)
  mc_call(db)
  expect_true(any(grepl("FROM s.streams_access WHERE watershed_group_code = 'ADMS'",
                        db$sql(), fixed = TRUE)))
  db2 <- mc_db(persist = FALSE)
  mc_call(db2)
  expect_true(any(grepl("id_segment IN (\n         SELECT id_segment FROM s.streams",
                        db2$sql(), fixed = TRUE)))
})

test_that("an empty access or habitat read stops, naming the table", {
  expect_error(mc_call(mc_db(access = data.frame(id_segment = integer(0)))),
               "s.streams_access empty for WSG ADMS", fixed = TRUE)
  expect_error(mc_call(mc_db(habitat = data.frame(
                 id_segment = integer(0), species_code = character(0),
                 spawning = integer(0), rearing = integer(0)))),
               "s.streams_habitat_long_vw empty for WSG ADMS", fixed = TRUE)
})

test_that("a bundle's residence reaches the exported build with no set passed (#512)", {
  # A bundle holding BT and a sea-run cutthroat row set anadromous: CT reads
  # the anadromous barrier token (any dam downstream), BT the resident one
  # (the next barrier down is not the dam).
  cfg <- copy_bundle_dims("default", function(d) {
    d$residence[d$species == "CT"] <- "anadromous"
    d
  })
  cfg$species <- c("BT", "CT")
  acc <- data.frame(id_segment = 1L, has_barriers_bt_dnstr = FALSE,
                    has_barriers_ct_dnstr = FALSE,
                    has_barriers_anthropogenic_dnstr = TRUE,
                    has_barriers_dams_dnstr = TRUE, dam_dnstr_ind = FALSE)
  hab <- data.frame(id_segment = 1L, spawning_bt = 0, rearing_bt = 0,
                    spawning_ct = 0, rearing_ct = 0)
  fc <- data.frame(id_segment = 1L, feature_code = "X")
  out <- lnk_pipeline_mapping_code(acc, hab, fc, cfg = cfg)
  expect_identical(out$mapping_code_ct, "ACCESS;DAM")
  expect_identical(out$mapping_code_bt, "ACCESS;MODELLED")
  # Without cfg, bcfishpass's sets: CT is in neither, so it is not coded.
  expect_false("mapping_code_ct" %in% names(lnk_pipeline_mapping_code(acc, hab, fc)))
  # A set passed by hand still wins over the bundle.
  out2 <- lnk_pipeline_mapping_code(acc, hab, fc, cfg = cfg,
                                    species_resident = c("bt", "ct"),
                                    species_anadromous = character(0))
  expect_identical(out2$mapping_code_ct, "ACCESS;MODELLED")
})
