# data-raw/sync_bcfishpass_csvs.R
#
# Syncs bcfishpass-sourced override CSVs into the bundled
# `inst/extdata/configs/{bcfishpass,default}/overrides/` directories.
# Updates the `provenance:` block in each bundle's `config.yaml`
# (synced date, upstream_sha, checksum) for any file whose upstream
# content differs from the recorded checksum.
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
# Drift kinds:
#   none  -- exit clean
#   byte  -- bytes changed but column shape stable; auto-merge byte PR
#   shape -- column rename / add / remove / reshape; halt + halt with
#            schema-drift label for coordinated review
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

library(link)

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args

UPSTREAM_REPO <- "smnorris/bcfishpass"  # for is_bcfp_sourced filter only
S3_PREFIX <- "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass"
BUNDLE_BCFP <- "inst/extdata/configs/bcfishpass"
BUNDLE_DEF  <- "inst/extdata/configs/default"
SUMMARY_PATH <- "/tmp/sync_summary.md"
DRIFT_KIND_PATH <- "/tmp/sync_drift_kind"
BASELINE_LEDGER <- "data-raw/logs/bcfp_baselines.csv"

stopifnot(file.exists(file.path(BUNDLE_BCFP, "config.yaml")),
          file.exists(file.path(BUNDLE_DEF, "config.yaml")))

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

# Filter: only sync entries whose origin is the bcfishpass repo.
# (Source field is descriptive, not prescriptive -- still valid even
# now that we fetch via S3 rather than GitHub API.)
is_bcfp_sourced <- function(entry) {
  isTRUE(entry$source == sprintf("https://github.com/%s", UPSTREAM_REPO))
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

# --- Discover files to sync from bcfishpass bundle's manifest --------------

manifest <- yaml::read_yaml(file.path(BUNDLE_BCFP, "config.yaml"))
prov <- manifest$provenance
if (is.null(prov)) stop("bcfishpass config.yaml has no provenance block")

target_files <- names(prov)[vapply(prov, is_bcfp_sourced, logical(1))]
if (length(target_files) == 0L) {
  cat("No bcfishpass-sourced files found in provenance -- nothing to do\n")
  quit(status = 0)
}
cat(sprintf("Checking %d bcfishpass-sourced files for drift...\n",
            length(target_files)))

# --- Diff loop -------------------------------------------------------------

today <- format(Sys.Date(), "%Y-%m-%d")
changes <- list()
schema_errors <- character(0)

for (rel in target_files) {
  upstream_rel <- prov[[rel]]$path  # e.g. data/user_habitat_classification.csv
  if (is.null(upstream_rel)) {
    cat(sprintf("  %s: skipping (no upstream path in provenance)\n", rel))
    next
  }
  bucket_key <- paste0("csvs/", basename(upstream_rel))
  expected_byte  <- prov[[rel]]$checksum
  expected_shape <- prov[[rel]]$shape_checksum
  canonical_slug <- prov[[rel]]$canonical_schema

  upstream_bytes <- tryCatch(lnk_bucket_get(bucket_key, prefix = S3_PREFIX),
    error = function(e) {
      cat(sprintf("  %s: WARNING fetch failed (%s) -- skipping\n",
                  rel, conditionMessage(e)))
      NULL
    })
  if (is.null(upstream_bytes)) next

  observed_byte  <- sha256_text(upstream_bytes)
  observed_shape <- shape_fingerprint(upstream_bytes)

  # Crate canonical-schema gate (only if entry declares one).
  schema_err <- validate_canonical_schema(rel, canonical_slug, upstream_bytes)
  if (!is.null(schema_err)) {
    schema_errors <- c(schema_errors, schema_err)
  }

  if (identical(observed_byte, expected_byte)) {
    cat(sprintf("  %s: clean\n", rel))
    next
  }
  shape_drift <- !is.null(expected_shape) &&
                  !identical(observed_shape, expected_shape)
  cat(sprintf("  %s: %s DRIFT -- recording change\n",
              rel, if (shape_drift) "SHAPE" else "byte"))
  changes[[rel]] <- list(
    rel = rel,
    upstream_rel = upstream_rel,
    bytes = upstream_bytes,
    old_checksum  = expected_byte,
    new_checksum  = observed_byte,
    old_shape     = expected_shape,
    new_shape     = observed_shape,
    shape_drift   = shape_drift
  )
}

# Determine overall drift kind for the workflow gate. Schema-validation
# failures escalate to "shape" even if first-line fingerprint matched.
drift_kind <- if (length(changes) == 0L && length(schema_errors) == 0L) {
  "none"
} else if (length(schema_errors) > 0L ||
           any(vapply(changes, function(ch) isTRUE(ch$shape_drift),
                       logical(1)))) {
  "shape"
} else {
  "byte"
}
writeLines(drift_kind, DRIFT_KIND_PATH)
cat(sprintf("Drift kind: %s (-> %s)\n", drift_kind, DRIFT_KIND_PATH))

if (length(changes) == 0L && length(schema_errors) == 0L) {
  cat("No drift detected -- exit clean\n")
  if (file.exists(SUMMARY_PATH)) file.remove(SUMMARY_PATH)
  quit(status = 0)
}

# --- Write changes ---------------------------------------------------------

if (dry_run) {
  cat(sprintf("\n[dry-run] would update %d files; skipping writes\n",
              length(changes)))
  if (length(schema_errors) > 0L) {
    cat("\n[dry-run] schema validation errors:\n")
    cat(paste0("  ", schema_errors, "\n"))
  }
  quit(status = 0)
}

for (rel in names(changes)) {
  ch <- changes[[rel]]
  for (bundle in c(BUNDLE_BCFP, BUNDLE_DEF)) {
    out_path <- file.path(bundle, rel)
    # writeBin (NOT writeLines) -- preserves bytes verbatim so the
    # sync-time sha256 of `ch$bytes` matches the runtime sha256 of
    # the on-disk file (lnk_config_verify hashes by file path).
    writeBin(ch$bytes, out_path)
    update_provenance_in_yaml(file.path(bundle, "config.yaml"),
      rel_path = rel,
      new_sha = sha_short,
      new_synced = today,
      new_checksum = ch$new_checksum,
      new_shape_checksum = ch$new_shape)
  }
  cat(sprintf("  %s: wrote (sha %s%s)\n",
              rel, sha_short,
              if (ch$shape_drift) " -- SHAPE DRIFT, do NOT auto-merge" else ""))
}

# --- Append baseline ledger row --------------------------------------------

lnk_baseline_append(
  log,
  run_label = paste0("csv-sync-", format(Sys.Date(), "%Y%m%d")),
  notes = paste0("auto-append by csv-sync; head_sha=", sha_short,
                 if (drift_kind == "shape") "; SHAPE DRIFT" else ""),
  path = BASELINE_LEDGER
)
cat(sprintf("Appended row to %s\n", BASELINE_LEDGER))

# --- Markdown summary for PR body ------------------------------------------

any_shape_drift <- drift_kind == "shape"
md_lines <- c(
  sprintf("# CSV sync -- %s%s", today,
          if (any_shape_drift) " -- SHAPE DRIFT" else ""),
  "",
  sprintf("Pinned to bcfp build `%s` (head_sha `%s`, completed `%s`).",
          log$model_version, sha_short, log$date_completed),
  "",
  if (any_shape_drift) c(
    "> :warning: One or more files changed shape (column rename / add /",
    "> remove / reshape) OR failed canonical-schema validation. This",
    "> PR is **not** auto-merged -- the link pipeline and downstream",
    "> consumers (`fresh::frs_habitat_overlay`, reporting repos,",
    "> db_newgraph schema views) likely need a coordinated update before",
    "> merging. See [link#64](https://github.com/NewGraphEnvironment/link/issues/64)",
    "> + crate's adapter for the recommended workflow.",
    ""
  ) else character(0),
  if (length(schema_errors) > 0L) c(
    "## Canonical-schema validation errors",
    "",
    paste0("- ", schema_errors),
    ""
  ) else character(0),
  if (length(changes) > 0L) c(
    sprintf("Synced %d file(s) from `s3://fresh-bc/bcfishpass/csvs/`:",
            length(changes)),
    "",
    "| file | drift | old byte | new byte |",
    "|---|---|---|---|"
  ) else character(0)
)
for (rel in names(changes)) {
  ch <- changes[[rel]]
  md_lines <- c(md_lines,
    sprintf("| `%s` | %s | `%s` | `%s` |",
            rel,
            if (ch$shape_drift) "**shape**" else "byte",
            substr(ch$old_checksum, 1, 14),
            substr(ch$new_checksum, 1, 14)))
}
md_lines <- c(md_lines,
  "",
  "Both `bcfishpass` and `default` bundles updated identically. Run",
  "`Rscript -e 'devtools::load_all(\".\"); lnk_config_verify(lnk_config(\"bcfishpass\"))'`",
  "after pulling to confirm clean state.")

writeLines(md_lines, SUMMARY_PATH)
cat(sprintf("Wrote summary to %s\n", SUMMARY_PATH))
quit(status = 0)
