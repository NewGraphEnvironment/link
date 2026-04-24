# data-raw/_targets.R
#
# Pipeline definition for the bcfishpass + default comparison.
# Orchestrates the six lnk_pipeline_* phase helpers across five
# watershed groups for BOTH config bundles and rolls up the per-WSG
# diff tibbles into one compound rollup (rearing_km + lake/wetland ha
# per species per config).
#
# WSGs:
#   ADMS / BULK / BABL / ELKR — numerical-parity WSGs.
#   DEAD (added 2026-04-23 with #44) — end-to-end test for the
#     `barriers_definite_control` filter.
#
# Configs:
#   bcfishpass — validation config, reproduces bcfishpass exactly.
#   default    — NewGraph default, departures from bcfishpass documented
#                in research/default_vs_bcfishpass.md (intermittent
#                streams, wetland rearing, expanded lake rearing,
#                river-polygon cw_min skip, spawn gradient min 0.0025).
#
# Rollup shape: `config`, `wsg`, `species`, `habitat_type`
# ({spawning, rearing, lake_rearing, wetland_rearing}), `unit`
# ({km, ha}), `link_value`, `bcfishpass_value`, `diff_pct`.
#
# Run from the link repo root:
#   Rscript -e 'targets::tar_config_set(script = "data-raw/_targets.R",
#                                        store  = "data-raw/_targets");
#                targets::tar_make()'
# Or from data-raw/:
#   cd data-raw && Rscript -e 'targets::tar_make()'
#
# Single-host constraint: `fresh.streams` is a shared schema, so
# parallel workers on one host would race their base-segments builds.
# Controller serializes with workers = 1. Distributed runs (M4 + M1 via
# crew.cluster) are a follow-up once link#53 lands (per-AOI fresh
# streams path). See planning/active/findings.md.

library(targets)
library(tarchetypes)

source("compare_bcfishpass_wsg.R")

tar_option_set(
  packages = c("link", "fresh", "DBI", "RPostgres", "tibble", "dplyr")
)

wsgs <- c("ADMS", "BULK", "BABL", "ELKR", "DEAD")

list(
  # --- Config bundles ---
  tar_target(cfg_bcfishpass, link::lnk_config("bcfishpass")),
  tar_target(cfg_default,    link::lnk_config("default")),

  # --- Per-WSG comparison: bcfishpass ---
  tar_map(
    values = tibble::tibble(wsg = wsgs),
    tar_target(
      comparison_bcfishpass,
      compare_bcfishpass_wsg(wsg = wsg, config = cfg_bcfishpass)
    )
  ),

  # --- Per-WSG comparison: default ---
  tar_map(
    values = tibble::tibble(wsg = wsgs),
    tar_target(
      comparison_default,
      compare_bcfishpass_wsg(wsg = wsg, config = cfg_default)
    )
  ),

  # --- Unified rollup with config identity ---
  tar_target(
    rollup,
    dplyr::bind_rows(
      bcfishpass = dplyr::bind_rows(
        comparison_bcfishpass_ADMS, comparison_bcfishpass_BULK,
        comparison_bcfishpass_BABL, comparison_bcfishpass_ELKR,
        comparison_bcfishpass_DEAD
      ),
      default = dplyr::bind_rows(
        comparison_default_ADMS, comparison_default_BULK,
        comparison_default_BABL, comparison_default_ELKR,
        comparison_default_DEAD
      ),
      .id = "config"
    )
  )
)
