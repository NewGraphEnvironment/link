#!/usr/bin/env Rscript
# Pre-flight audit of every config layer for both bundles.
# Goal: catch staleness BEFORE running the trifecta — recompute the
# provenance checksums, regenerate rules.yaml, sanity-check that the
# species axes line up across dimensions / parameters_fresh /
# wsg_species_presence, flag undeclared override CSVs.
#
# Reports findings; does NOT fix them. Fix decisions belong to a human.

suppressPackageStartupMessages({
  library(yaml); library(digest); library(tibble); library(dplyr)
})

setwd("/Users/airvine/Projects/repo/link")
devtools::load_all(quiet = TRUE)

bundles <- c("bcfishpass", "default")

cat("\n==== CONFIG AUDIT (link", as.character(packageVersion("link")), ") ====\n")

# ---------------------------------------------------------------------------
# 1. Provenance checksums vs current file state
# ---------------------------------------------------------------------------
cat("\n--- 1. Provenance drift (config.yaml `provenance:` vs current files) ---\n")

shape_checksum <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  ext <- tools::file_ext(path)
  obj <- if (ext == "csv") {
    df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    list(cols = names(df), nrow = nrow(df), col_types = vapply(df, class, character(1)))
  } else if (ext == "yaml") {
    y <- yaml::read_yaml(path)
    list(top_keys = names(y))
  } else {
    list(size = file.size(path))
  }
  paste0("sha256:", digest::digest(obj, algo = "sha256", serialize = TRUE))
}

byte_checksum <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  paste0("sha256:", digest::digest(file = path, algo = "sha256"))
}

drift_report <- list()
for (b in bundles) {
  cfg_path <- sprintf("inst/extdata/configs/%s/config.yaml", b)
  cfg <- yaml::read_yaml(cfg_path)
  bundle_dir <- dirname(cfg_path)
  rows <- list()
  for (key in names(cfg$provenance)) {
    p <- file.path(bundle_dir, key)
    rec <- cfg$provenance[[key]]
    cur_byte <- byte_checksum(p)
    cur_shape <- shape_checksum(p)
    rows[[length(rows) + 1]] <- tibble(
      bundle = b, file = key,
      byte_drift  = !is.na(rec$checksum) && !is.na(cur_byte) &&
                     rec$checksum != cur_byte,
      shape_drift = !is.na(rec$shape_checksum) && !is.na(cur_shape) &&
                     rec$shape_checksum != cur_shape,
      cur_byte = cur_byte, rec_byte = rec$checksum,
      cur_shape = cur_shape, rec_shape = rec$shape_checksum
    )
  }
  drift_report[[b]] <- bind_rows(rows)
}
all_drift <- bind_rows(drift_report)
drifted <- all_drift |> dplyr::filter(byte_drift | shape_drift)
cat(sprintf("  %d drifted entries across %d bundles\n",
            nrow(drifted), length(bundles)))
if (nrow(drifted) > 0) {
  print(drifted |> dplyr::select(bundle, file, byte_drift, shape_drift), n = Inf)
}

# ---------------------------------------------------------------------------
# 2. rules.yaml regeneration diff
# ---------------------------------------------------------------------------
cat("\n--- 2. rules.yaml regen vs committed ---\n")
for (b in bundles) {
  dim_csv <- sprintf("inst/extdata/configs/%s/dimensions.csv", b)
  rules_committed <- sprintf("inst/extdata/configs/%s/rules.yaml", b)
  tf <- tempfile(fileext = ".yaml")
  lnk_rules_build(dim_csv, tf, edge_types = "categories")

  identical_yaml <- identical(yaml::read_yaml(tf), yaml::read_yaml(rules_committed))
  identical_text <- identical(readLines(tf), readLines(rules_committed))
  cat(sprintf("  %-12s  identical(structure)=%s  identical(bytes)=%s\n",
              b, identical_yaml, identical_text))
  if (!identical_yaml) {
    cat("    !! regen differs from committed — committed rules.yaml is stale\n")
  } else if (!identical_text) {
    cat("    (text differs but yaml structure matches — likely formatting only)\n")
  }
}

# ---------------------------------------------------------------------------
# 3. Species axis consistency
# ---------------------------------------------------------------------------
cat("\n--- 3. Species axis consistency per bundle ---\n")
for (b in bundles) {
  dim_csv  <- sprintf("inst/extdata/configs/%s/dimensions.csv", b)
  pf_csv   <- sprintf("inst/extdata/configs/%s/parameters_fresh.csv", b)
  wsg_csv  <- sprintf("inst/extdata/configs/%s/overrides/wsg_species_presence.csv", b)
  yaml_path <- sprintf("inst/extdata/configs/%s/rules.yaml", b)

  dim_sp  <- gsub('"', '', utils::read.csv(dim_csv, stringsAsFactors = FALSE,
                                            check.names = FALSE)[[1]])
  pf_sp   <- gsub('"', '', utils::read.csv(pf_csv,  stringsAsFactors = FALSE,
                                            check.names = FALSE)[[1]])
  wsg_hdr <- names(utils::read.csv(wsg_csv, stringsAsFactors = FALSE,
                                    check.names = FALSE, nrows = 1))
  wsg_sp  <- toupper(setdiff(wsg_hdr, c("watershed_group_code", "notes")))
  yaml_sp <- names(yaml::read_yaml(yaml_path))

  cat(sprintf("\n  bundle: %s\n", b))
  cat(sprintf("    dimensions.csv:           %s\n", paste(sort(dim_sp), collapse = " ")))
  cat(sprintf("    parameters_fresh.csv:     %s\n", paste(sort(pf_sp), collapse = " ")))
  cat(sprintf("    wsg_species_presence cols:%s\n", paste(sort(wsg_sp), collapse = " ")))
  cat(sprintf("    rules.yaml top-level:     %s\n", paste(sort(yaml_sp), collapse = " ")))

  # Mismatches
  in_dim_not_pf <- setdiff(dim_sp, pf_sp)
  in_pf_not_dim <- setdiff(pf_sp, dim_sp)
  in_pf_not_wsg <- setdiff(pf_sp, wsg_sp)
  in_dim_not_yaml <- setdiff(dim_sp, yaml_sp)
  in_yaml_not_dim <- setdiff(yaml_sp, dim_sp)

  flags <- list(
    "dim ∖ pf"     = in_dim_not_pf,
    "pf ∖ dim"     = in_pf_not_dim,
    "pf ∖ wsg-cols"= in_pf_not_wsg,
    "dim ∖ yaml"   = in_dim_not_yaml,
    "yaml ∖ dim"   = in_yaml_not_dim
  )
  for (name in names(flags)) {
    if (length(flags[[name]]) > 0) {
      cat(sprintf("    !! %s: %s\n", name, paste(flags[[name]], collapse = ", ")))
    }
  }
}

# ---------------------------------------------------------------------------
# 4. Undeclared override CSVs (files on disk but not in cfg$files)
# ---------------------------------------------------------------------------
cat("\n--- 4. Override files on disk vs declared in config.yaml ---\n")
for (b in bundles) {
  cfg_path <- sprintf("inst/extdata/configs/%s/config.yaml", b)
  cfg <- yaml::read_yaml(cfg_path)
  declared_paths <- vapply(cfg$files, \(x) x$path, character(1))
  declared_files <- basename(declared_paths)

  override_dir <- sprintf("inst/extdata/configs/%s/overrides", b)
  on_disk <- list.files(override_dir, pattern = "\\.csv$")

  undeclared <- setdiff(on_disk, declared_files)
  missing <- setdiff(declared_files, on_disk)

  cat(sprintf("\n  bundle: %s\n", b))
  if (length(undeclared) > 0) {
    cat(sprintf("    on-disk-but-not-declared: %s\n",
                paste(undeclared, collapse = ", ")))
  } else {
    cat("    on-disk-but-not-declared: (none)\n")
  }
  if (length(missing) > 0) {
    cat(sprintf("    !! declared-but-missing: %s\n",
                paste(missing, collapse = ", ")))
  } else {
    cat("    declared-but-missing: (none)\n")
  }
}

# ---------------------------------------------------------------------------
# 5. lnk_load_overrides smoke per bundle
# ---------------------------------------------------------------------------
cat("\n--- 5. lnk_load_overrides() smoke per bundle ---\n")
for (b in bundles) {
  cfg <- tryCatch(lnk_config(b), error = function(e) NULL)
  if (is.null(cfg)) {
    cat(sprintf("  %s: lnk_config FAILED\n", b)); next
  }
  loaded <- tryCatch(lnk_load_overrides(cfg), error = function(e) e)
  if (inherits(loaded, "error")) {
    cat(sprintf("  %s: lnk_load_overrides FAILED — %s\n", b, conditionMessage(loaded)))
  } else {
    cat(sprintf("  %s: %d entries loaded — %s\n", b, length(loaded),
                paste(names(loaded), collapse = ", ")))
  }
}

# ---------------------------------------------------------------------------
# 6. Top-level (legacy) parameters_habitat_*  — check for staleness
# ---------------------------------------------------------------------------
cat("\n--- 6. Legacy top-level parameters_habitat_* files ---\n")
for (f in c("inst/extdata/parameters_habitat_dimensions.csv",
            "inst/extdata/parameters_habitat_rules.yaml")) {
  if (file.exists(f)) {
    cat(sprintf("  %s  (mtime: %s)\n", f, format(file.info(f)$mtime, "%Y-%m-%d")))
  }
}
cat("  Note: these were the pre-bundle predecessors. Per CLAUDE.md they map to\n")
cat("  the default bundle's dimensions.csv. If they have drifted from the\n")
cat("  default bundle, they're stale and should be either removed or pinned.\n")

cat("\n==== AUDIT COMPLETE ====\n")
