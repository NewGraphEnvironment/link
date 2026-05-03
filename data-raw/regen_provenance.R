#!/usr/bin/env Rscript
# Regenerate stale config artifacts:
# 1. rules.yaml in both bundles via lnk_rules_build()
# 2. provenance:checksum + shape_checksum in both config.yaml for the
#    drifted files (rules.yaml, dimensions.csv, parameters_fresh.csv,
#    overrides/wsg_species_presence.csv).
#
# Algorithm matches R/lnk_config_verify.R::.lnk_shape_fingerprint and
# the byte-checksum digest::digest(file=...) call there.

suppressPackageStartupMessages({
  library(digest)
})

setwd("/Users/airvine/Projects/repo/link")
devtools::load_all(quiet = TRUE)

byte_csum <- function(p) paste0("sha256:", digest::digest(file = p, algo = "sha256"))

shape_csum <- function(p) {
  first <- readLines(p, n = 1, warn = FALSE)
  if (length(first) == 0L) return(NA_character_)
  norm <- sub("\\s+$", "", first)
  paste0("sha256:", digest::digest(norm, algo = "sha256", serialize = FALSE))
}

# 1. Regenerate rules.yaml for both bundles
for (b in c("bcfishpass", "default")) {
  dim_csv  <- sprintf("inst/extdata/configs/%s/dimensions.csv", b)
  out_yaml <- sprintf("inst/extdata/configs/%s/rules.yaml", b)
  cat(sprintf("[regen] %s rules.yaml ← %s\n", b, dim_csv))
  lnk_rules_build(dim_csv, out_yaml, edge_types = "explicit")
}

# 2. Update provenance for the four drifted files in each bundle.
# Surgical line-replace to preserve comments + key order in config.yaml.
update_provenance <- function(cfg_path, file_keys) {
  lines <- readLines(cfg_path)
  out <- lines
  for (key in file_keys) {
    abs_path <- file.path(dirname(cfg_path), key)
    if (!file.exists(abs_path)) {
      cat(sprintf("  !! missing: %s\n", abs_path))
      next
    }
    new_byte  <- byte_csum(abs_path)
    new_shape <- shape_csum(abs_path)

    # Find the block: a line "  <key>:" at the start of a 2-space-indented
    # provenance entry, then replace its `checksum:` and `shape_checksum:` lines.
    key_re <- sprintf("^  %s:$", gsub("/", "\\/", key, fixed = TRUE))
    key_idx <- grep(key_re, out)
    if (length(key_idx) != 1L) {
      cat(sprintf("  !! could not find unique provenance block for %s\n", key))
      next
    }
    # Walk forward until we hit the next 2-space-indented top-level key
    # (line matching "^  [^ ]") or end of file.
    end_idx <- length(out)
    for (j in (key_idx + 1):length(out)) {
      if (grepl("^  [^ ]", out[j])) { end_idx <- j - 1; break }
    }
    block <- out[(key_idx + 1):end_idx]

    byte_pos  <- grep("^    checksum: sha256:",       block)
    shape_pos <- grep("^    shape_checksum: sha256:", block)

    if (length(byte_pos)  == 1L) block[byte_pos]  <- sprintf("    checksum: %s", new_byte)
    if (length(shape_pos) == 1L) block[shape_pos] <- sprintf("    shape_checksum: %s", new_shape)

    out[(key_idx + 1):end_idx] <- block
    cat(sprintf("  %-50s -> %s | %s\n",
                paste0(basename(dirname(cfg_path)), "/", key),
                substr(new_byte, 8, 19), substr(new_shape, 8, 19)))
  }
  writeLines(out, cfg_path)
}

drifted_files <- c(
  "rules.yaml",
  "dimensions.csv",
  "parameters_fresh.csv",
  "overrides/wsg_species_presence.csv"
)

for (b in c("bcfishpass", "default")) {
  cfg_path <- sprintf("inst/extdata/configs/%s/config.yaml", b)
  cat(sprintf("\n[provenance] %s\n", cfg_path))
  update_provenance(cfg_path, drifted_files)
}

cat("\n[verify] re-running lnk_config_verify on each bundle\n")
for (b in c("bcfishpass", "default")) {
  # Force re-load to pick up updated config.yaml
  cfg <- lnk_config(b)
  v <- lnk_config_verify(cfg)
  drifted_n <- sum(v$byte_drift | v$shape_drift)
  cat(sprintf("  %-12s drifted=%d / %d\n", b, drifted_n, nrow(v)))
}
