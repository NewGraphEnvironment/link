# data-raw/rule_flexibility_demo.R
#
# Phase 3 of link#69: proof artifact for `research/rule_flexibility.md`.
#
# Runs the BABL × CO pipeline under three configs by swapping ONLY
# `dimensions.csv` cells. Saves the rollup tibble and rules.yaml
# CO blocks for the research doc.
#
# Each config is a clone of the default bundle with a small set of
# cells flipped. The demo proves that every methodology dial is a
# CSV cell — no buried emission rules.
#
# Run from the link repo root: `Rscript data-raw/rule_flexibility_demo.R`
# Output: `research/rule_flexibility_data.rds`

suppressMessages({
  library(link)
  library(yaml)
})

stopifnot(requireNamespace("digest", quietly = TRUE))

# Destination for the rendered data the research doc reads.
out_rds <- "research/rule_flexibility_data.rds"

# WSG to demo on. BABL has all 5 spawn species and rear_lake / rear_wetland
# polygons, so it exercises every dial.
demo_wsg <- "BABL"
demo_species <- "CO"

# -----------------------------------------------------------------------------
# Config matrix — cells that vary across the three configs.
#
# All three are descendants of the default bundle. Only the listed cells
# differ from default; everything else (spawn rules, gradient/cw thresholds,
# fresh barriers, breaks, observations) is the same.
# -----------------------------------------------------------------------------
config_matrix <- list(
  use_case_1 = list(
    label = "Use case 1 — linear includes mainlines + area rollups",
    swaps = list()  # ships as-is in the default bundle today
  ),
  use_case_2 = list(
    label = "Use case 2 — linear excludes mainlines, area still rolls up",
    swaps = list(
      # Mainlines through L/W polygons no longer count in linear `rearing_km`.
      rear_stream_in_waterbody = "no",
      # L/W polygon rules contribute only to bucket flag, not main rear.
      rear_lake_area_only      = "yes",
      rear_wetland_area_only   = "yes"
    )
  ),
  bcfishpass = list(
    label = "bcfishpass bundle — strict partition, no polygon-area rollup",
    swaps = list(
      # Mirrors bcfishpass's per-species access SQL: stream rule
      # restricted to outside polygons, no polygon contribution at all
      # for linear or area buckets.
      rear_stream_in_waterbody = "no",
      rear_lake                = "no",
      rear_wetland_polygon     = "no"
    )
  )
)

# -----------------------------------------------------------------------------
# Build a config bundle in a temp dir from the default + per-config swaps.
# -----------------------------------------------------------------------------
build_config <- function(swaps) {
  src <- system.file("extdata", "configs", "default", package = "link",
                     mustWork = TRUE)
  dst <- tempfile("rfdemo_")
  dir.create(dst)
  file.copy(list.files(src, full.names = TRUE), dst, recursive = TRUE)

  csv_path <- file.path(dst, "dimensions.csv")
  dims <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  for (col in names(swaps)) {
    if (!col %in% names(dims)) {
      stop("Column '", col, "' not in default dimensions.csv")
    }
    dims[[col]] <- swaps[[col]]
  }
  utils::write.csv(dims, csv_path, row.names = FALSE, quote = TRUE)

  rules_path <- file.path(dst, "rules.yaml")
  link::lnk_rules_build(csv = csv_path, to = rules_path,
                        edge_types = "explicit")

  cfg_path <- file.path(dst, "config.yaml")
  cfg_yaml <- yaml::read_yaml(cfg_path)
  for (f in c("rules.yaml", "dimensions.csv")) {
    p <- file.path(dst, f)
    cfg_yaml$provenance[[f]]$checksum <-
      paste0("sha256:", digest::digest(file = p, algo = "sha256"))
    cfg_yaml$provenance[[f]]$shape_checksum <-
      link:::.lnk_shape_fingerprint(p)
  }
  yaml::write_yaml(cfg_yaml, cfg_path)

  dst
}

# -----------------------------------------------------------------------------
# Run the pipeline for one config, return rollup + rules.yaml CO block.
# -----------------------------------------------------------------------------
source("data-raw/compare_bcfishpass_wsg.R")

run_one <- function(config_name, spec) {
  message(sprintf("[%s] building config", config_name))
  cfg_dir <- build_config(spec$swaps)
  cfg <- link::lnk_config(cfg_dir)

  rules <- yaml::read_yaml(file.path(cfg_dir, "rules.yaml"))
  rules_co <- rules[[demo_species]]

  message(sprintf("[%s] running BABL pipeline", config_name))
  t0 <- Sys.time()
  rollup <- compare_bcfishpass_wsg(demo_wsg, cfg)
  elapsed <- as.numeric(Sys.time() - t0, units = "secs")
  message(sprintf("[%s] elapsed %.1fs", config_name, elapsed))

  list(
    name      = config_name,
    label     = spec$label,
    swaps     = spec$swaps,
    cfg_dir   = cfg_dir,
    rollup    = rollup,
    rules_co  = rules_co,
    elapsed_s = elapsed
  )
}

# -----------------------------------------------------------------------------
# Execute
# -----------------------------------------------------------------------------
results <- list()
for (nm in names(config_matrix)) {
  results[[nm]] <- run_one(nm, config_matrix[[nm]])
}

dir.create("research", showWarnings = FALSE)
saveRDS(list(
  generated_at  = Sys.time(),
  link_version  = utils::packageVersion("link"),
  fresh_version = utils::packageVersion("fresh"),
  wsg           = demo_wsg,
  species       = demo_species,
  configs       = config_matrix,
  results       = results
), out_rds)

message("Wrote ", out_rds)
