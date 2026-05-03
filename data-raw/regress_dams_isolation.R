#!/usr/bin/env Rscript
# #103 isolation test — run HARR with dams ON vs OFF on current HEAD,
# diff rollups. Goal: prove prep_dams has zero effect on habitat
# classification output (architectural parallel-data invariant).
#
# Pre-#103 baseline contamination: the cached `comparison_*` targets
# were last built May 1 06:48 — before #96 (falls in break_order),
# #97 (frs_order_child), and 31b9 (default-bundle SK methodology)
# shipped. So the 4-WSG regress vs that cache surfaces ~1km segmentation
# drift across many rows that has nothing to do with #103.

suppressPackageStartupMessages({
  library(dplyr)
})

setwd("/Users/airvine/Projects/repo/link/data-raw")
source("compare_bcfishpass_wsg.R")

cfg <- link::lnk_config("bcfishpass")

cat("=== HARR with dams OFF (conn_tunnel = NULL) ===\n")
t0 <- Sys.time()
off <- compare_bcfishpass_wsg(wsg = "HARR", config = cfg, dams = FALSE)
cat(sprintf("(%.1fs)\n\n", as.numeric(Sys.time() - t0, units = "secs")))

cat("=== HARR with dams ON (conn_tunnel = conn_ref) ===\n")
t0 <- Sys.time()
on  <- compare_bcfishpass_wsg(wsg = "HARR", config = cfg, dams = TRUE)
cat(sprintf("(%.1fs)\n\n", as.numeric(Sys.time() - t0, units = "secs")))

key <- c("wsg", "species", "habitat_type", "unit")
off_s <- dplyr::arrange(off, dplyr::across(dplyr::all_of(key)))
on_s  <- dplyr::arrange(on,  dplyr::across(dplyr::all_of(key)))

byte_identical <- isTRUE(all.equal(off_s, on_s,
                                   tolerance = 0,
                                   check.attributes = FALSE))
near_equal <- isTRUE(all.equal(off_s, on_s,
                               tolerance = 1e-12,
                               check.attributes = FALSE))

cat(sprintf("byte-identical=%s\n", byte_identical))
cat(sprintf("near-equal(1e-12)=%s\n", near_equal))

if (!near_equal) {
  cat("\n--- diff rows ---\n")
  diffs <- off_s |>
    dplyr::full_join(on_s, by = key, suffix = c("_off", "_on")) |>
    dplyr::mutate(
      eq = (link_value_off == link_value_on |
              (is.na(link_value_off) & is.na(link_value_on))) &
           (bcfishpass_value_off == bcfishpass_value_on |
              (is.na(bcfishpass_value_off) & is.na(bcfishpass_value_on)))
    ) |>
    dplyr::filter(!eq) |>
    dplyr::select(dplyr::all_of(key), link_value_off, link_value_on,
                  bcfishpass_value_off, bcfishpass_value_on)
  print(diffs, n = 50)
}

cat(sprintf("\nVERDICT: %s\n",
  if (near_equal) "PASS — #103 has zero effect on rollup. Dams data is parallel."
  else            "FAIL — dams data is leaking into habitat classification."))
