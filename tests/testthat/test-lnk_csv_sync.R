# The weekly sync (data-raw/sync_bcfishpass_csvs.R) keeps every file a
# bundle copies from bcfishpass byte for byte, and never lets a change that
# moves an output token merge by itself (#429).

bundle_dir <- function(name) {
  system.file("extdata", "configs", name, package = "link", mustWork = TRUE)
}

test_that("every CSV a synced bundle keeps under overrides/ is provenanced", {
  for (b in c("bcfishpass", "default")) {
    dir <- bundle_dir(b)
    prov <- yaml::read_yaml(file.path(dir, "config.yaml"))$provenance
    on_disk <- file.path("overrides",
                         list.files(file.path(dir, "overrides"),
                                    pattern = "\\.csv$"))
    expect_identical(setdiff(on_disk, names(prov)), character(0),
                     info = b)
  }
})

test_that("every files: entry declared as a bcfishpass copy is synced", {
  for (b in c("bcfishpass", "default")) {
    dir <- bundle_dir(b)
    man <- yaml::read_yaml(file.path(dir, "config.yaml"))
    targets <- link:::.lnk_sync_targets(man$provenance)
    for (key in names(man$files)) {
      e <- man$files[[key]]
      if (identical(e$source, "bcfp")) {
        expect_true(e$path %in% targets, info = paste(b, key))
      }
    }
  }
})

test_that("the copies the sync must cover are all targets in both bundles", {
  stems <- c("cabd_additions", "cabd_blkey_xref", "cabd_exclusions",
             "cabd_passability_status_updates", "dfo_known_sockeye_lakes",
             "observation_exclusions", "pscis_modelledcrossings_streams_xref",
             "user_barriers_definite", "user_barriers_definite_control",
             "user_crossings_misc", "user_habitat_classification",
             "user_modelled_crossing_fixes", "user_pscis_barrier_status",
             "wcrp_watersheds")
  copies <- paste0("overrides/", stems, ".csv")
  for (b in c("bcfishpass", "default")) {
    prov <- yaml::read_yaml(file.path(bundle_dir(b), "config.yaml"))$provenance
    expect_identical(setdiff(copies, link:::.lnk_sync_targets(prov)),
                     character(0), info = b)
  }
  # bcfishpass's presence table is a copy there; default's is link's own.
  prov_b <- yaml::read_yaml(file.path(bundle_dir("bcfishpass"),
                                      "config.yaml"))$provenance
  prov_d <- yaml::read_yaml(file.path(bundle_dir("default"),
                                      "config.yaml"))$provenance
  expect_true("overrides/wsg_species_presence.csv" %in%
                link:::.lnk_sync_targets(prov_b))
  expect_false("overrides/wsg_species_presence.csv" %in%
                 link:::.lnk_sync_targets(prov_d))
})

test_that("drift kind ranks shape over review over byte over none", {
  k <- link:::.lnk_sync_drift_kind
  expect_identical(k(byte = FALSE, shape = FALSE, review = FALSE), "none")
  expect_identical(k(byte = TRUE, shape = FALSE, review = FALSE), "byte")
  expect_identical(k(byte = TRUE, shape = FALSE, review = TRUE), "review")
  expect_identical(k(byte = TRUE, shape = TRUE, review = TRUE), "shape")
  expect_identical(k(byte = FALSE, shape = FALSE, review = TRUE), "review")
})

test_that("a trial write reports a moved token spec and leaves the bundle alone", {
  src <- bundle_dir("bcfishpass")
  rel <- "overrides/wsg_species_presence.csv"
  before <- readBin(file.path(src, rel), "raw", file.size(file.path(src, rel)))
  lines <- readLines(file.path(src, rel))
  i <- grep("^ADMS,", lines)
  lines[i] <- sub("^ADMS,t,", "ADMS,,", lines[i])
  new <- charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))

  tr <- link:::.lnk_sync_trial(src, stats::setNames(list(new), rel))
  expect_null(tr$error)
  expect_identical(tr$moved, "acc")
  expect_true(startsWith(tr$after[["acc"]], "sha256:"))
  expect_identical(readBin(file.path(src, rel), "raw",
                           file.size(file.path(src, rel))), before)
})

test_that("a trial write that changes no token spec moves nothing", {
  src <- bundle_dir("bcfishpass")
  rel <- "overrides/cabd_passability_status_updates.csv"
  bytes <- readBin(file.path(src, rel), "raw", file.size(file.path(src, rel)))
  tr <- link:::.lnk_sync_trial(src, stats::setNames(list(bytes), rel))
  expect_null(tr$error)
  expect_identical(tr$moved, character(0))
})

test_that("a trial write that breaks loading is reported, not raised", {
  src <- bundle_dir("bcfishpass")
  rel <- "overrides/wsg_species_presence.csv"
  lines <- readLines(file.path(src, rel))
  # Drop a group the overlay names: the bundle no longer loads.
  lines <- lines[!grepl("^PARS,", lines)]
  new <- charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
  tr <- link:::.lnk_sync_trial(src, stats::setNames(list(new), rel))
  expect_match(tr$error, "PARS")
})

test_that("an overlay row upstream now agrees with is reported redundant", {
  tmp <- withr::local_tempdir()
  base <- file.path(tmp, "p.csv")
  ovl <- file.path(tmp, "p_overlay.csv")
  writeLines(c("watershed_group_code,bt,ko", "ADMS,t,t", "BULK,,"), base)
  writeLines(c("watershed_group_code,column,value,reason,issue",
               "ADMS,ko,t,adopted upstream,#1",
               "BULK,ko,t,still ours,#1",
               "BULK,ch,t,column upstream lacks,#1"), ovl)
  red <- link:::.lnk_sync_overlay_redundant(base, ovl)
  expect_identical(red$watershed_group_code, "ADMS")
  expect_identical(red$column, "ko")
})

test_that("a trial write that loads only with a warning is reported", {
  # read.csv() truncates at a stray quote and only warns: a copy that loads
  # short must not pass as clean (code-check round 3).
  src <- bundle_dir("bcfishpass")
  rel <- "overrides/observation_exclusions.csv"
  lines <- readLines(file.path(src, rel))
  n <- length(lines)
  lines <- c(lines[seq_len(n - 3L)],
             paste0(lines[[n - 3L]], "\"unterminated"),
             lines[(n - 2L):n])
  new <- charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
  tr <- link:::.lnk_sync_trial(src, stats::setNames(list(new), rel))
  expect_match(tr$error, "warned:")
})
