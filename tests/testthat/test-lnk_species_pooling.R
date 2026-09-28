# lnk_species_pooling() (#290). Synthetic species (AAA, BBB, CCC), group
# (GRP) and geography, so no assertion can pass on the shipped BT/DV rows by
# accident: the resolver must know nothing about any real species.

regions_fx <- data.frame(
  watershed_group_code = c("W1", "W2", "W3", "W4"),
  region               = c("North", "North", "South", "South"),
  subregion            = c("Hill", NA, NA, NA),
  stringsAsFactors = FALSE
)

presence_fx <- data.frame(
  watershed_group_code = c("W1", "W2", "W3", "W4"),
  aaa = c("t", "t", "t", ""),
  bbb = c("t", "t", "t", "t"),
  ccc = c("t", "t", "t", "t"),
  notes = "",
  stringsAsFactors = FALSE
)

pool_row <- function(species_code, species_obs, scope_level, scope,
                     pool = "yes") {
  data.frame(species_code = species_code, species_obs = species_obs,
             scope_level = scope_level, scope = scope, pool = pool,
             stringsAsFactors = FALSE)
}

loaded_fx <- function(pooling, groups = NULL) {
  list(species_pooling = pooling, species_groups = groups,
       wsg_species_presence = presence_fx)
}

obs_for <- function(res, w, sp) {
  sort(res$obs_species[res$watershed_group_code == w & res$species_code == sp])
}

test_that("a region row pools in every WSG of the region and nowhere else", {
  res <- lnk_species_pooling(
    loaded_fx(pool_row("AAA", "BBB", "region", "North")),
    aoi = c("W1", "W2", "W3"), species = "AAA", regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), c("AAA", "BBB"))
  expect_identical(obs_for(res, "W2", "AAA"), c("AAA", "BBB"))
  expect_identical(obs_for(res, "W3", "AAA"), "AAA")
})

test_that("unlisted means not pooled, and a species always counts as itself", {
  res <- lnk_species_pooling(
    loaded_fx(pool_row("AAA", "BBB", "region", "North")),
    aoi = "W3", species = c("AAA", "CCC"), regions = regions_fx)
  expect_identical(obs_for(res, "W3", "AAA"), "AAA")
  expect_identical(obs_for(res, "W3", "CCC"), "CCC")
  expect_identical(unique(res$scope_level), "self")
})

test_that("the more specific scope wins: wsg over subregion over region", {
  p <- rbind(pool_row("AAA", "BBB", "region", "North", "yes"),
             pool_row("AAA", "BBB", "subregion", "Hill", "no"),
             pool_row("AAA", "BBB", "wsg", "W1", "yes"))
  res <- lnk_species_pooling(loaded_fx(p), aoi = c("W1", "W2"),
                             species = "AAA", regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), c("AAA", "BBB"))
  expect_identical(res$scope_level[res$watershed_group_code == "W1" &
                                     res$obs_species == "BBB"], "wsg")
  expect_identical(obs_for(res, "W2", "AAA"), c("AAA", "BBB"))

  # without the wsg row, the subregion's "no" beats the region's "yes"
  res2 <- lnk_species_pooling(loaded_fx(p[1:2, ]), aoi = "W1",
                              species = "AAA", regions = regions_fx)
  expect_identical(obs_for(res2, "W1", "AAA"), "AAA")
})

test_that("a group expands on either side of a rule", {
  g <- data.frame(group_code = c("GRP", "GRP"), species_code = c("AAA", "BBB"),
                  stringsAsFactors = FALSE)
  # target is the group: every member admits CCC
  res <- lnk_species_pooling(
    loaded_fx(pool_row("GRP", "CCC", "region", "North"), g),
    aoi = "W1", species = c("AAA", "BBB", "CCC"), regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), c("AAA", "CCC"))
  expect_identical(obs_for(res, "W1", "BBB"), c("BBB", "CCC"))
  expect_identical(obs_for(res, "W1", "CCC"), "CCC")

  # both sides the group: members pool with each other
  res2 <- lnk_species_pooling(
    loaded_fx(pool_row("GRP", "GRP", "region", "North"), g),
    aoi = "W1", species = c("AAA", "BBB"), regions = regions_fx)
  expect_identical(obs_for(res2, "W1", "AAA"), c("AAA", "BBB"))
  expect_identical(obs_for(res2, "W1", "BBB"), c("AAA", "BBB"))
})

test_that("at equal scope, a species row beats a group row", {
  g <- data.frame(group_code = c("GRP", "GRP"), species_code = c("AAA", "BBB"),
                  stringsAsFactors = FALSE)
  p <- rbind(pool_row("GRP", "GRP", "region", "North", "yes"),
             pool_row("AAA", "BBB", "region", "North", "no"))
  res <- lnk_species_pooling(loaded_fx(p, g), aoi = "W1",
                             species = c("AAA", "BBB"), regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), "AAA")
  expect_identical(obs_for(res, "W1", "BBB"), c("AAA", "BBB"))
})

test_that("a scope beats taxon specificity: a wsg group row beats a region species row", {
  g <- data.frame(group_code = c("GRP", "GRP"), species_code = c("AAA", "BBB"),
                  stringsAsFactors = FALSE)
  p <- rbind(pool_row("AAA", "BBB", "region", "North", "no"),
             pool_row("GRP", "GRP", "wsg", "W1", "yes"))
  res <- lnk_species_pooling(loaded_fx(p, g), aoi = "W1", species = "AAA",
                             regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), c("AAA", "BBB"))
})

test_that("a tie left with a different pool errors, naming both rows", {
  p <- rbind(pool_row("AAA", "BBB", "region", "North", "yes"),
             pool_row("AAA", "BBB", "region", "North", "no"))
  expect_error(
    lnk_species_pooling(loaded_fx(p), aoi = "W1", species = "AAA",
                        regions = regions_fx),
    "conflict.*rows 1, 2")
  # agreeing duplicates are not a conflict
  p$pool <- "yes"
  expect_no_error(lnk_species_pooling(loaded_fx(p), aoi = "W1",
                                      species = "AAA", regions = regions_fx))
})

test_that("the model species must be present in the WSG", {
  res <- lnk_species_pooling(
    loaded_fx(pool_row("AAA", "BBB", "region", "South")),
    aoi = c("W3", "W4"), species = "AAA", regions = regions_fx)
  expect_identical(obs_for(res, "W3", "AAA"), c("AAA", "BBB"))
  expect_identical(obs_for(res, "W4", "AAA"), character(0))
})

test_that("no tracker means no pooling, not an error", {
  res <- lnk_species_pooling(loaded_fx(NULL), aoi = "W1",
                             species = c("AAA", "BBB"), regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), "AAA")
  expect_identical(obs_for(res, "W1", "BBB"), "BBB")
})

test_that("bad rows fail loud", {
  bad <- function(p, g = NULL, re) {
    expect_error(lnk_species_pooling(loaded_fx(p, g), aoi = "W1",
                                     species = "AAA", regions = regions_fx),
                 re)
  }
  bad(pool_row("AAA", "BBB", "basin", "North"), re = "scope_level")
  bad(pool_row("AAA", "BBB", "region", "Nowhere"), re = "Nowhere")
  bad(pool_row("AAA", "BBB", "wsg", "W9"), re = "W9")
  bad(pool_row("AAA", "BBB", "region", "North", "maybe"), re = "pool")
  bad(pool_row("AAA", "ZZZ", "region", "North"), re = "ZZZ")
  bad(pool_row("AAA", NA, "region", "North"), re = "species_obs")
  # a group code that is also a species code
  bad(pool_row("AAA", "BBB", "region", "North"),
      g = data.frame(group_code = "CCC", species_code = "AAA"), re = "CCC")
  # a group inside a group
  bad(pool_row("AAA", "BBB", "region", "North"),
      g = data.frame(group_code = c("GRP", "GR2"), species_code = c("AAA", "GRP")),
      re = "nest")
  expect_error(lnk_species_pooling(loaded_fx(NULL), aoi = "W9",
                                   species = "AAA", regions = regions_fx),
               "W9")
})

test_that("a repeated or differently cased WSG yields its rows once", {
  res <- lnk_species_pooling(
    loaded_fx(pool_row("AAA", "BBB", "region", "North")),
    aoi = c("W1", "W1", "w1"), species = c("AAA", "aaa"), regions = regions_fx)
  expect_identical(nrow(res), 2L)
})

test_that("an unknown model species errors rather than reading as absent", {
  expect_error(lnk_species_pooling(loaded_fx(NULL), aoi = "W1",
                                   species = "AAX", regions = regions_fx),
               "AAX")
})

test_that("a malformed region lookup fails loud", {
  r <- rbind(regions_fx, regions_fx[1, ])
  expect_error(lnk_species_pooling(loaded_fx(NULL), aoi = "W1",
                                   species = "AAA", regions = r), "unique")
  r <- regions_fx
  r$watershed_group_code[2] <- NA
  expect_error(lnk_species_pooling(loaded_fx(NULL), aoi = "W1",
                                   species = "AAA", regions = r), "NA")
  expect_error(lnk_species_pooling(loaded_fx(NULL), aoi = "W1",
                                   species = "AAA",
                                   regions = regions_fx[c("watershed_group_code",
                                                          "region")]),
               "subregion")
})

test_that("codes and scopes are matched case- and whitespace-insensitively", {
  res <- lnk_species_pooling(
    loaded_fx(pool_row(" aaa", "bbb ", "Region", " north")),
    aoi = "w1", species = "aaa", regions = regions_fx)
  expect_identical(obs_for(res, "W1", "AAA"), c("AAA", "BBB"))
})

test_that("obs_year_max is carried from the winning row, NA when empty", {
  p <- rbind(pool_row("AAA", "BBB", "region", "North"),
             pool_row("AAA", "BBB", "wsg", "W1"))
  p$obs_year_max <- c("1994", "")
  res <- lnk_species_pooling(loaded_fx(p), aoi = c("W1", "W2"),
                             species = "AAA", regions = regions_fx)
  y <- function(w) res$obs_year_max[res$watershed_group_code == w &
                                      res$obs_species == "BBB"]
  # W1: the wsg row wins and has no limit; W2: the region row's 1994
  expect_identical(y("W1"), NA_integer_)
  expect_identical(y("W2"), 1994L)
  expect_true(all(is.na(res$obs_year_max[res$scope_level == "self"])))
  expect_type(res$obs_year_max, "integer")
})

test_that("tied rows that disagree on obs_year_max error; bad years are refused", {
  p <- rbind(pool_row("AAA", "BBB", "region", "North"),
             pool_row("AAA", "BBB", "region", "North"))
  p$obs_year_max <- c("1994", "2000")
  expect_error(lnk_species_pooling(loaded_fx(p), aoi = "W1", species = "AAA",
                                   regions = regions_fx), "obs_year_max")
  for (bad in c("199x", "1994.5", "3000")) {
    q <- pool_row("AAA", "BBB", "region", "North")
    q$obs_year_max <- bad
    expect_error(lnk_species_pooling(loaded_fx(q), aoi = "W1", species = "AAA",
                                     regions = regions_fx), "obs_year_max")
  }
})

test_that("the shipped default bundle resolves over every region", {
  cfg <- lnk_config("default")
  loaded <- suppressWarnings(lnk_load_overrides(cfg))
  regions <- utils::read.csv(system.file("extdata", "wsg_regions.csv",
                                         package = "link"),
                             stringsAsFactors = FALSE)
  res <- lnk_species_pooling(loaded, aoi = regions$watershed_group_code,
                             species = unique(toupper(
                               loaded$parameters_fresh$species_code)))
  expect_true(all(c("watershed_group_code", "species_code", "obs_species",
                    "scope_level", "scope", "rule", "obs_year_max") %in%
                    names(res)))
  # every row that pools is traced to a tracker row
  pooled <- res[res$scope_level != "self", ]
  expect_gt(nrow(pooled), 0)
  expect_false(anyNA(pooled$rule))
  expect_true(all(pooled$species_code != pooled$obs_species))
})
