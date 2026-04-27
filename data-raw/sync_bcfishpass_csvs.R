# data-raw/sync_bcfishpass_csvs.R
#
# Syncs bcfishpass-sourced override CSVs into the bundled
# `inst/extdata/configs/{bcfishpass,default}/overrides/` directories.
# Updates the `provenance:` block in each bundle's `config.yaml`
# (synced date, upstream_sha, checksum) for any file whose upstream
# content differs from the recorded checksum.
#
# Driven by `provenance:` declarations: only files whose `source:`
# field is `https://github.com/smnorris/bcfishpass` are synced. Other
# files (link hand-authored, generated, dfo_*, cabd_*) are ignored.
#
# Usage:
#   Rscript data-raw/sync_bcfishpass_csvs.R [--dry-run]
#
# In CI: invoked by .github/workflows/sync-bcfishpass-csvs.yml. Writes
# a markdown summary of changed files to /tmp/sync_summary.md for the
# auto-PR body.
#
# Requires:
#   - `gh` CLI in PATH (preinstalled on GitHub Actions runners; locally
#     install via `brew install gh && gh auth login`)
#   - R packages: yaml, digest, jsonlite (declared in workflow YAML)
#
# Exits 0 on success regardless of whether anything changed. Errors
# (network, parse, missing tooling) crash with a non-zero exit so the
# workflow run is visibly red.

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args

UPSTREAM_REPO <- "smnorris/bcfishpass"
BUNDLE_BCFP <- "inst/extdata/configs/bcfishpass"
BUNDLE_DEF  <- "inst/extdata/configs/default"
SUMMARY_PATH <- "/tmp/sync_summary.md"
DRIFT_KIND_PATH <- "/tmp/sync_drift_kind"

stopifnot(file.exists(file.path(BUNDLE_BCFP, "config.yaml")),
          file.exists(file.path(BUNDLE_DEF, "config.yaml")))

# --- Helpers ---------------------------------------------------------------

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

# Fetch via `gh api` against the contents endpoint instead of raw HTTP:
# - Authenticates via $GH_TOKEN, avoids unauthenticated rate limits
# - Returns explicit HTTP status (gh exits non-zero on any non-2xx)
# - No risk of `download.file` silently saving a 200-OK HTML error page
#
# Files >1MB return `encoding: "none"` from the contents endpoint
# (GitHub API limit). Fall back to the git blob endpoint which has no
# size limit and returns base64 regardless.
fetch_raw <- function(rel_path) {
  endpoint <- sprintf("repos/%s/contents/%s?ref=main", UPSTREAM_REPO, rel_path)
  parsed <- gh_api_json(endpoint)
  if (is.null(parsed$encoding)) {
    stop("Unexpected contents-endpoint response for ", rel_path)
  }
  if (identical(parsed$encoding, "base64") && nzchar(parsed$content %||% "")) {
    return(jsonlite::base64_dec(gsub("\\s", "", parsed$content)))
  }
  # Large-file path — fetch via blob SHA.
  blob_sha <- parsed$sha
  if (is.null(blob_sha)) {
    stop("Contents endpoint returned encoding=", parsed$encoding %||% "NULL",
         " but no blob sha for ", rel_path)
  }
  blob_endpoint <- sprintf("repos/%s/git/blobs/%s", UPSTREAM_REPO, blob_sha)
  blob <- gh_api_json(blob_endpoint)
  if (!identical(blob$encoding, "base64")) {
    stop("Unexpected blob encoding '", blob$encoding, "' for ", rel_path)
  }
  jsonlite::base64_dec(gsub("\\s", "", blob$content))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Latest commit short-sha touching `data/<basename>`. Uses gh CLI which
# auths via $GH_TOKEN (Actions) or local `gh auth login` token.
upstream_sha_for <- function(upstream_path) {
  endpoint <- sprintf("repos/%s/commits?path=%s&per_page=1",
                       UPSTREAM_REPO, upstream_path)
  parsed <- gh_api_json(endpoint)
  if (length(parsed) == 0L) {
    stop("No commit history found for upstream path ", upstream_path)
  }
  full_sha <- parsed[[1]]$sha
  substr(full_sha, 1, 7)
}

# Wrapper around `gh api` that keeps stderr separate from stdout, so
# error text never reaches fromJSON masquerading as a payload. Exits
# loudly on non-zero status with the actual gh stderr in the message.
gh_api_json <- function(endpoint) {
  err_file <- tempfile(fileext = ".err")
  on.exit(unlink(err_file), add = TRUE)
  out <- system2("gh", c("api", endpoint),
                  stdout = TRUE, stderr = err_file)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    err <- if (file.exists(err_file)) {
      paste(readLines(err_file, warn = FALSE), collapse = "\n")
    } else {
      "(no stderr captured)"
    }
    stop("gh api ", endpoint, " failed (exit ", status, "): ", err)
  }
  jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE)
}

# Replace `upstream_sha`, `synced`, `checksum`, `shape_checksum` lines
# for a specific provenance entry. Walks the YAML as text lines so
# comments + key ordering are preserved (yaml::write_yaml round-trips
# lose comments).
update_provenance_in_yaml <- function(yaml_path, rel_path,
                                       new_sha, new_synced,
                                       new_checksum, new_shape_checksum) {
  lines <- readLines(yaml_path)
  # Provenance entries are indented 2 spaces under top-level
  # `provenance:` and the file path key has a trailing colon. Match
  # the entry header by literal string equality (after stripping any
  # trailing whitespace from the YAML line) — avoids regex-metachar
  # surprises with future filenames containing `+`, `[`, etc.
  header_literal <- paste0("  ", rel_path, ":")
  start <- which(sub("\\s+$", "", lines) == header_literal)
  if (length(start) != 1L) {
    stop("Could not locate exactly one provenance entry for ",
         rel_path, " in ", yaml_path,
         " (matches: ", length(start), ")")
  }
  i <- start + 1L
  # Entry-body lines are indented 4 spaces. Walk forward and stop only
  # when we hit a line that's both non-blank AND not indented to the
  # body level — i.e., the next entry, the next top-level key, or EOF.
  # Blank lines inside an entry are tolerated (stopping at one would
  # silently skip the rest of the keys).
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

# --- Discover files to sync from bcfishpass bundle's manifest --------------

manifest <- yaml::read_yaml(file.path(BUNDLE_BCFP, "config.yaml"))
prov <- manifest$provenance
if (is.null(prov)) stop("bcfishpass config.yaml has no provenance block")

is_bcfp_sourced <- function(entry) {
  isTRUE(entry$source == sprintf("https://github.com/%s", UPSTREAM_REPO))
}
target_files <- names(prov)[vapply(prov, is_bcfp_sourced, logical(1))]
if (length(target_files) == 0L) {
  cat("No bcfishpass-sourced files found in provenance — nothing to do\n")
  quit(status = 0)
}
cat(sprintf("Checking %d bcfishpass-sourced files for drift...\n",
            length(target_files)))

# --- Diff loop -------------------------------------------------------------

today <- format(Sys.Date(), "%Y-%m-%d")
changes <- list()

for (rel in target_files) {
  upstream_rel <- prov[[rel]]$path  # e.g. data/user_habitat_classification.csv
  if (is.null(upstream_rel)) {
    cat(sprintf("  %s: skipping (no upstream path in provenance)\n", rel))
    next
  }
  expected_byte  <- prov[[rel]]$checksum
  expected_shape <- prov[[rel]]$shape_checksum
  upstream_bytes <- tryCatch(fetch_raw(upstream_rel),
    error = function(e) {
      cat(sprintf("  %s: WARNING fetch failed (%s) — skipping\n",
                  rel, conditionMessage(e)))
      NULL
    })
  if (is.null(upstream_bytes)) next
  observed_byte  <- sha256_text(upstream_bytes)
  observed_shape <- shape_fingerprint(upstream_bytes)
  if (identical(observed_byte, expected_byte)) {
    cat(sprintf("  %s: clean\n", rel))
    next
  }
  shape_drift <- !is.null(expected_shape) &&
                  !identical(observed_shape, expected_shape)
  cat(sprintf("  %s: %s DRIFT — recording change\n",
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

# Determine overall drift kind for the workflow gate.
drift_kind <- if (length(changes) == 0L) {
  "none"
} else if (any(vapply(changes, function(ch) isTRUE(ch$shape_drift),
                       logical(1)))) {
  "shape"
} else {
  "byte"
}
writeLines(drift_kind, DRIFT_KIND_PATH)
cat(sprintf("Drift kind: %s (-> %s)\n", drift_kind, DRIFT_KIND_PATH))

if (length(changes) == 0L) {
  cat("No drift detected — exit clean\n")
  if (file.exists(SUMMARY_PATH)) file.remove(SUMMARY_PATH)
  quit(status = 0)
}

# --- Write changes ---------------------------------------------------------

if (dry_run) {
  cat(sprintf("\n[dry-run] would update %d files; skipping writes\n",
              length(changes)))
  quit(status = 0)
}

# Collect upstream SHAs (one API call per file) to put into provenance.
for (rel in names(changes)) {
  changes[[rel]]$upstream_sha <- upstream_sha_for(changes[[rel]]$upstream_rel)
}

for (rel in names(changes)) {
  ch <- changes[[rel]]
  for (bundle in c(BUNDLE_BCFP, BUNDLE_DEF)) {
    out_path <- file.path(bundle, rel)
    # writeBin (NOT writeLines) — preserves bytes verbatim so the
    # sync-time sha256 of `ch$bytes` matches the runtime sha256 of
    # the on-disk file (lnk_config_verify hashes by file path).
    # writeLines on Windows would translate \n -> \r\n and break parity.
    writeBin(ch$bytes, out_path)
    update_provenance_in_yaml(file.path(bundle, "config.yaml"),
      rel_path = rel,
      new_sha = ch$upstream_sha,
      new_synced = today,
      new_checksum = ch$new_checksum,
      new_shape_checksum = ch$new_shape)
  }
  cat(sprintf("  %s: wrote (sha %s%s)\n",
              rel, ch$upstream_sha,
              if (ch$shape_drift) " — SHAPE DRIFT, do NOT auto-merge" else ""))
}

# --- Markdown summary for PR body ------------------------------------------

any_shape_drift <- any(vapply(changes,
  function(ch) isTRUE(ch$shape_drift), logical(1)))
md_lines <- c(
  sprintf("# CSV sync — %s%s", today,
          if (any_shape_drift) " — SHAPE DRIFT" else ""),
  "",
  if (any_shape_drift) c(
    "> :warning: One or more files changed shape (column rename / add /",
    "> remove / reshape). This PR is **not** auto-merged — the link",
    "> pipeline and downstream consumers (`fresh::frs_habitat_overlay`,",
    "> reporting repos, db_newgraph schema views) likely need a",
    "> coordinated update before merging. See [link#64](https://github.com/NewGraphEnvironment/link/issues/64)",
    "> + crate's adapter for the recommended workflow.",
    ""
  ) else character(0),
  sprintf("Synced %d file(s) from [%s](https://github.com/%s):",
          length(changes), UPSTREAM_REPO, UPSTREAM_REPO),
  "",
  "| file | upstream_sha | drift | old byte | new byte |",
  "|---|---|---|---|---|"
)
for (rel in names(changes)) {
  ch <- changes[[rel]]
  md_lines <- c(md_lines,
    sprintf("| `%s` | `%s` | %s | `%s` | `%s` |",
            rel, ch$upstream_sha,
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
