# data-raw/sync_bcfishpass_csvs.R
#
# Syncs bcfishpass-sourced override CSVs into the bundled
# `inst/extdata/configs/{bcfishpass,default}/overrides/` directories.
# Each bundle syncs the files its own `provenance:` block names as copies
# (`source: https://github.com/smnorris/bcfishpass`), and only into itself:
# `default`'s presence table is link's own, the `bcfishpass` bundle's is a
# copy (#429). A copy is kept byte for byte; link's changes to it live in
# an overlay beside it (`files: <key>: overlay:`, R/lnk_overlay.R).
# Updates the `provenance:` entry (synced date, upstream_sha, checksum)
# of any copy whose upstream content differs from the recorded checksum.
#
# Source: `s3://fresh-bc/bcfishpass/csvs/` -- populated weekly by
# NewGraphEnvironment/db_newgraph (workflow dump-bcfishpass-csvs.yaml).
# That workflow pins to the SHA from the latest successful smnorris/
# bcfishpass:ng-prod run, so every CSV in the prefix is at the same
# upstream commit -- no per-file SHA walking needed here.
#
# All provenance entries take the same `upstream_sha` (the rebuild SHA
# from `s3://fresh-bc/bcfishpass/log.json`). On drift detection, this
# script also appends a row to `data-raw/logs/bcfp_baselines.csv` so
# every comparison rollup ties back to both the bcfp build AND the
# matching bundle CSV state.
#
# Usage:
#   Rscript data-raw/sync_bcfishpass_csvs.R [--dry-run]
#
# In CI: invoked by .github/workflows/sync-bcfishpass-csvs.yml. Writes
# a markdown summary of changed files to /tmp/sync_summary.md for the
# auto-PR body and a drift kind to /tmp/sync_drift_kind.
#
# Drift kinds (the worst present wins: shape, review, byte, none):
#   none   -- exit clean
#   byte   -- bytes changed, column shape and every output token stable;
#             auto-merge byte PR
#   review -- an output token's spec moved (a presence cell, say), or a
#             bundle no longer loads after the write (an overlay row whose
#             key upstream dropped); PR with token-review label, not merged.
#             The PR body names the axis and the new spec for the
#             vocabulary row (inst/extdata/vocabulary.csv)
#   shape  -- column rename / add / remove / reshape; halt with
#             schema-drift label for coordinated review
#
# A fetch that fails stops the run: a copy that cannot be compared is not
# clean.
#
# Shape drift is detected two ways (belt + suspenders):
#   1. First-line shape_checksum mismatch (catches all CSVs)
#   2. crate::crt_schema_validate() against the canonical schema slug,
#      for provenance entries that declare `canonical_schema:` (precise
#      missing-required-column errors surfaced in the PR body)
#
# Requires (in CI workflow): R deps from DESCRIPTION (httr, jsonlite,
# crate, yaml, digest). No GH_TOKEN needed -- s3://fresh-bc is public
# read.

# The source tree, never a stale installed copy (code-check-r). In CI the
# workflow installs link from this checkout and has no pkgload, so the
# installed package is the source tree there.
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(".", quiet = TRUE)
} else {
  library(link)
}

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args

S3_PREFIX <- "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass"
BUNDLES <- c("inst/extdata/configs/bcfishpass",
             "inst/extdata/configs/default")
SUMMARY_PATH <- "/tmp/sync_summary.md"
DRIFT_KIND_PATH <- "/tmp/sync_drift_kind"
BASELINE_LEDGER <- "data-raw/logs/bcfp_baselines.csv"

stopifnot(all(file.exists(file.path(BUNDLES, "config.yaml"))))

# --- Helpers ---------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a)) b else a

sha256_text <- function(content_bytes) {
  paste0("sha256:", digest::digest(content_bytes,
                                    algo = "sha256",
                                    serialize = FALSE))
}

# Shape fingerprint: sha256 of normalized first line. Catches column
# rename/add/remove/reshape but not type changes within stable columns.
# Mirrors `link:::.lnk_shape_fingerprint()` so sync-time and runtime
# computations agree.
shape_fingerprint <- function(content_bytes) {
  text <- rawToChar(content_bytes)
  first_line <- sub("\n.*$", "", text)
  if (!nzchar(first_line)) return(NA_character_)
  normalized <- sub("\\s+$", "", first_line)
  paste0("sha256:", digest::digest(normalized,
                                    algo = "sha256",
                                    serialize = FALSE))
}

# Replace `upstream_sha`, `synced`, `checksum`, `shape_checksum` lines
# for a specific provenance entry. Walks the YAML as text lines so
# comments + key ordering are preserved (yaml::write_yaml round-trips
# lose comments).
update_provenance_in_yaml <- function(yaml_path, rel_path,
                                       new_sha, new_synced,
                                       new_checksum, new_shape_checksum) {
  lines <- readLines(yaml_path)
  header_literal <- paste0("  ", rel_path, ":")
  start <- which(sub("\\s+$", "", lines) == header_literal)
  if (length(start) != 1L) {
    stop("Could not locate exactly one provenance entry for ",
         rel_path, " in ", yaml_path,
         " (matches: ", length(start), ")")
  }
  i <- start + 1L
  while (i <= length(lines)) {
    line <- lines[i]
    if (nzchar(line) && !grepl("^    ", line)) break
    if (grepl("^    upstream_sha:", line)) {
      lines[i] <- paste0("    upstream_sha: ", new_sha)
    } else if (grepl("^    synced:", line)) {
      lines[i] <- paste0("    synced: ", new_synced)
    } else if (grepl("^    checksum:", line) &&
               !grepl("^    shape_checksum:", line)) {
      lines[i] <- paste0("    checksum: ", new_checksum)
    } else if (grepl("^    shape_checksum:", line)) {
      lines[i] <- paste0("    shape_checksum: ", new_shape_checksum)
    }
    i <- i + 1L
  }
  writeLines(lines, yaml_path)
}

# Optional canonical-schema gate via crate. Returns NULL on success
# or an error message string on validation failure (caller decides
# how to surface it).
validate_canonical_schema <- function(rel, slug, bytes) {
  if (is.null(slug) || !nzchar(slug)) return(NULL)
  tryCatch({
    df <- utils::read.csv(text = rawToChar(bytes),
                          colClasses = "character",
                          stringsAsFactors = FALSE)
    schema <- crate::crt_schema_read(slug)
    crate::crt_schema_validate(df, schema)
    NULL
  }, error = function(e) {
    sprintf("%s (canonical_schema=%s): %s",
            rel, slug, conditionMessage(e))
  })
}

# --- Read upstream build identifier (single SHA for all files) -------------

log <- lnk_bucket_log(S3_PREFIX)
sha_short <- substr(log$head_sha, 1, 7)
cat(sprintf("Upstream build: %s (head_sha=%s, completed=%s)\n",
            log$model_version, sha_short, log$date_completed))

# --- Compare each bundle's copies with the dump ----------------------------

today <- format(Sys.Date(), "%Y-%m-%d")
fetched <- list()  # bucket key -> raw bytes, fetched once for both bundles
fetch <- function(bucket_key) {
  if (is.null(fetched[[bucket_key]])) {
    fetched[[bucket_key]] <<- tryCatch(
      lnk_bucket_get(bucket_key, prefix = S3_PREFIX),
      error = function(e) {
        stop("fetch of ", bucket_key, " failed (", conditionMessage(e),
             "): a copy that cannot be compared is not clean", call. = FALSE)
      })
  }
  fetched[[bucket_key]]
}

changes <- list()        # one entry per bundle x file
schema_errors <- character(0)
review <- character(0)   # reasons a change needs a person
redundant <- character(0)

for (bundle in BUNDLES) {
  prov <- yaml::read_yaml(file.path(bundle, "config.yaml"))$provenance
  targets <- link:::.lnk_sync_targets(prov)
  cat(sprintf("%s: checking %d bcfishpass copies\n", bundle, length(targets)))
  for (rel in targets) {
    upstream_rel <- prov[[rel]]$path  # e.g. data/user_habitat_classification.csv
    if (is.null(upstream_rel)) {
      stop(bundle, ": provenance entry ", rel, " names bcfishpass but no ",
           "upstream path", call. = FALSE)
    }
    bytes <- fetch(paste0("csvs/", basename(upstream_rel)))
    observed_byte  <- sha256_text(bytes)
    observed_shape <- shape_fingerprint(bytes)
    schema_err <- validate_canonical_schema(rel, prov[[rel]]$canonical_schema,
                                            bytes)
    if (!is.null(schema_err)) schema_errors <- c(schema_errors, schema_err)

    if (identical(observed_byte, prov[[rel]]$checksum)) {
      cat(sprintf("  %s: clean\n", rel))
      next
    }
    shape_drift <- !is.null(prov[[rel]]$shape_checksum) &&
      !identical(observed_shape, prov[[rel]]$shape_checksum)
    cat(sprintf("  %s: %s DRIFT\n", rel, if (shape_drift) "SHAPE" else "byte"))
    changes[[paste(bundle, rel)]] <- list(
      bundle = bundle, rel = rel, bytes = bytes,
      old_checksum = prov[[rel]]$checksum, new_checksum = observed_byte,
      new_shape = observed_shape, shape_drift = shape_drift)
  }

  # Write the bundle's changes into a copy of it and compare output token
  # specs: a moved spec, or a bundle that no longer loads, needs a person.
  mine <- Filter(function(ch) ch$bundle == bundle, changes)
  if (length(mine) > 0L) {
    tr <- link:::.lnk_sync_trial(
      bundle, stats::setNames(lapply(mine, `[[`, "bytes"),
                              vapply(mine, `[[`, "", "rel")))
    if (!is.null(tr$error)) {
      review <- c(review, sprintf(
        "`%s` does not load after the sync: %s", basename(bundle), tr$error))
    }
    for (axis in tr$moved) {
      review <- c(review, sprintf(
        "`%s`'s `%s` spec moves, so it needs a new vocabulary row (and the old one retired): `%s`",
        basename(bundle), axis, tr$after[[axis]]))
    }
  }

  # Overlay rows whose cell the (new) copy already holds: upstream adopted
  # them, so they can be retired.
  files <- yaml::read_yaml(file.path(bundle, "config.yaml"))$files
  for (key in names(files)) {
    ovl <- files[[key]]$overlay
    if (is.null(ovl)) next
    rel <- files[[key]]$path
    ch <- changes[[paste(bundle, rel)]]
    base <- file.path(bundle, rel)
    if (!is.null(ch)) {
      base <- tempfile(fileext = ".csv")
      writeBin(ch$bytes, base)
    }
    red <- link:::.lnk_sync_overlay_redundant(base, file.path(bundle, ovl))
    if (nrow(red) > 0L) {
      redundant <- c(redundant, sprintf(
        "`%s` %s: %s now matches upstream; retire the row",
        basename(bundle), ovl,
        paste(red[[1]], red$column, sep = "/", collapse = ", ")))
    }
  }
}

drift_kind <- link:::.lnk_sync_drift_kind(
  byte = length(changes) > 0L,
  shape = length(schema_errors) > 0L ||
    any(vapply(changes, function(ch) isTRUE(ch$shape_drift), logical(1))),
  review = length(review) > 0L)
writeLines(drift_kind, DRIFT_KIND_PATH)
cat(sprintf("Drift kind: %s (-> %s)\n", drift_kind, DRIFT_KIND_PATH))
for (r in c(review, redundant)) cat("  note:", r, "\n")

if (drift_kind == "none") {
  cat("No drift detected -- exit clean\n")
  if (file.exists(SUMMARY_PATH)) file.remove(SUMMARY_PATH)
  quit(status = 0)
}

# --- Write changes ---------------------------------------------------------

if (dry_run) {
  cat(sprintf("\n[dry-run] would update %d bundle files; skipping writes\n",
              length(changes)))
  if (length(schema_errors) > 0L) {
    cat("\n[dry-run] schema validation errors:\n")
    cat(paste0("  ", schema_errors, "\n"))
  }
  quit(status = 0)
}

for (ch in changes) {
  # writeBin (NOT writeLines) -- preserves bytes verbatim so the sync-time
  # sha256 matches the runtime sha256 of the on-disk file.
  writeBin(ch$bytes, file.path(ch$bundle, ch$rel))
  update_provenance_in_yaml(file.path(ch$bundle, "config.yaml"),
    rel_path = ch$rel,
    new_sha = sha_short,
    new_synced = today,
    new_checksum = ch$new_checksum,
    new_shape_checksum = ch$new_shape)
  cat(sprintf("  %s/%s: wrote (sha %s)\n", basename(ch$bundle), ch$rel,
              sha_short))
}

# --- Append baseline ledger row --------------------------------------------

lnk_baseline_append(
  log,
  run_label = paste0("csv-sync-", format(Sys.Date(), "%Y%m%d")),
  notes = paste0("auto-append by csv-sync; head_sha=", sha_short,
                 if (drift_kind != "byte") paste0("; ", toupper(drift_kind))),
  path = BASELINE_LEDGER
)
cat(sprintf("Appended row to %s\n", BASELINE_LEDGER))

# --- Markdown summary for PR body ------------------------------------------

md_lines <- c(
  sprintf("# CSV sync -- %s%s", today,
          switch(drift_kind, shape = " -- SHAPE DRIFT",
                 review = " -- TOKEN REVIEW", "")),
  "",
  sprintf("Pinned to bcfp build `%s` (head_sha `%s`, completed `%s`).",
          log$model_version, sha_short, log$date_completed),
  "",
  if (drift_kind == "shape") c(
    "> :warning: One or more files changed shape (column rename / add /",
    "> remove / reshape) OR failed canonical-schema validation. This",
    "> PR is **not** auto-merged -- the link pipeline and downstream",
    "> consumers (`fresh::frs_habitat_overlay`, reporting repos,",
    "> db_newgraph schema views) likely need a coordinated update before",
    "> merging. See [link#64](https://github.com/NewGraphEnvironment/link/issues/64)",
    "> + crate's adapter for the recommended workflow.",
    ""
  ) else character(0),
  if (length(review) > 0L) c(
    "## Needs review before merging",
    "",
    "A run of the bundle below refuses until each item is resolved:",
    "a moved spec needs a row in `inst/extdata/vocabulary.csv` (and the",
    "row it replaces retired, with a version bump); a bundle that does not",
    "load needs its overlay fixed.",
    "",
    paste0("- ", review),
    ""
  ) else character(0),
  if (length(redundant) > 0L) c(
    "## Overlay rows upstream now holds",
    "",
    paste0("- ", redundant),
    ""
  ) else character(0),
  if (length(schema_errors) > 0L) c(
    "## Canonical-schema validation errors",
    "",
    paste0("- ", schema_errors),
    ""
  ) else character(0),
  sprintf("Synced %d bundle file(s) from `s3://fresh-bc/bcfishpass/csvs/`:",
          length(changes)),
  "",
  "| bundle | file | drift | old byte | new byte |",
  "|---|---|---|---|---|")
for (ch in changes) {
  md_lines <- c(md_lines,
    sprintf("| `%s` | `%s` | %s | `%s` | `%s` |",
            basename(ch$bundle), ch$rel,
            if (ch$shape_drift) "**shape**" else "byte",
            substr(ch$old_checksum %||% "none", 1, 14),
            substr(ch$new_checksum, 1, 14)))
}
md_lines <- c(md_lines,
  "",
  "Each bundle syncs only the copies its own provenance declares. Run",
  "`Rscript -e 'devtools::load_all(\".\"); lnk_config_verify(lnk_config(\"bcfishpass\"))'`",
  "after pulling to confirm clean state.")

writeLines(md_lines, SUMMARY_PATH)
cat(sprintf("Wrote summary to %s\n", SUMMARY_PATH))
quit(status = 0)
