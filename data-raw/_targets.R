# data-raw/_targets.R
#
# Pipeline definition for the bcfishpass comparison. Orchestrates the
# six lnk_pipeline_* phase helpers across the four validated watershed
# groups and rolls up the per-WSG diff tibbles into one aggregate.
#
# Run from the link repo root:
#   Rscript -e 'targets::tar_config_set(script = "data-raw/_targets.R",
#                                        store  = "data-raw/_targets");
#                targets::tar_make()'
# Or from data-raw/:
#   cd data-raw && Rscript -e 'targets::tar_make()'
#
# Visualize the DAG:
#   Rscript -e 'targets::tar_config_set(script = "data-raw/_targets.R",
#                                        store  = "data-raw/_targets");
#                targets::tar_visnetwork()'
#
# Single-host constraint: `fresh.streams` is a shared schema, so parallel
# workers on one host would race their base-segments builds. Controller
# serializes with workers = 1. Distributed runs (M4 + M1 via
# crew.cluster) are a follow-up once a fresh-side per-AOI output path
# is supported (see link planning/active/findings.md).

library(targets)
library(tarchetypes)

source("compare_bcfishpass_wsg.R")

# Synchronous execution (no crew controller). `fresh.streams` is a shared
# schema — parallel workers on one host would race their base-segments
# builds — so we serialize. Distributed runs (M4 + M1 via
# crew_controller_group) will reintroduce crew once fresh supports a
# per-AOI output path. See planning/active/findings.md.
tar_option_set(
  packages = c("link", "fresh", "DBI", "RPostgres", "tibble", "dplyr")
)

wsgs <- c("ADMS", "BULK", "BABL", "ELKR")

list(
  tar_target(cfg, link::lnk_config("bcfishpass")),

  tar_map(
    values = tibble::tibble(wsg = wsgs),
    tar_target(
      comparison,
      compare_bcfishpass_wsg(wsg = wsg, config = cfg)
    )
  ),

  tar_target(
    rollup,
    dplyr::bind_rows(
      comparison_ADMS, comparison_BULK,
      comparison_BABL, comparison_ELKR
    )
  )
)
