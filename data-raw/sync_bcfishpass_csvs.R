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

stopifnot(file.exists(file.path(BUNDLE_BCFP, "config.yaml")),
          file.exists(file.path(BUNDLE_DEF, "config.yaml")))

# --- Helpers ---------------------------------------------------------------

sha256_text <- function(content_bytes) {
  paste0("sha256:", digest::digest(content_bytes,
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

# Replace `upstream_sha`, `synced`, `checksum` lines for a specific
# provenance entry. Walks the YAML as text lines so comments + key
# ordering are preserved (yaml::write_yaml round-trips lose comments).
update_provenance_in_yaml <- function(yaml_path, rel_path,
                                       new_sha, new_synced, new_checksum) {
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
    } else if (grepl("^    checksum:", line)) {
      lines[i] <- paste0("    checksum: ", new_checksum)
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
  expected <- prov[[rel]]$checksum
  upstream_bytes <- tryCatch(fetch_raw(upstream_rel),
    error = function(e) {
      cat(sprintf("  %s: WARNING fetch failed (%s) — skipping\n",
                  rel, conditionMessage(e)))
      NULL
    })
  if (is.null(upstream_bytes)) next
  observed <- sha256_text(upstream_bytes)
  if (identical(observed, expected)) {
    cat(sprintf("  %s: clean\n", rel))
    next
  }
  cat(sprintf("  %s: DRIFT — recording change\n", rel))
  changes[[rel]] <- list(
    rel = rel,
    upstream_rel = upstream_rel,
    bytes = upstream_bytes,
    old_checksum = expected,
    new_checksum = observed
  )
}

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
    writeBin(ch$bytes, out_path)
    update_provenance_in_yaml(file.path(bundle, "config.yaml"),
      rel_path = rel,
      new_sha = ch$upstream_sha,
      new_synced = today,
      new_checksum = ch$new_checksum)
  }
  cat(sprintf("  %s: wrote (sha %s)\n", rel, ch$upstream_sha))
}

# --- Markdown summary for PR body ------------------------------------------

md_lines <- c(
  sprintf("# CSV sync — %s", today),
  "",
  sprintf("Synced %d file(s) from [%s](https://github.com/%s):",
          length(changes), UPSTREAM_REPO, UPSTREAM_REPO),
  "",
  "| file | upstream_sha | old checksum | new checksum |",
  "|---|---|---|---|"
)
for (rel in names(changes)) {
  ch <- changes[[rel]]
  md_lines <- c(md_lines,
    sprintf("| `%s` | `%s` | `%s` | `%s` |",
            rel, ch$upstream_sha,
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
