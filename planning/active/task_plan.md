# Task: csv-sync rewrite to read from s3://fresh-bc/bcfishpass/ (#117)

## Problem (excerpt from issue body)

Daily csv-sync produces 1–7 days of drift between bundle CSVs and the tunnel's rebuild SHA. 8 stale daily PRs (#85, #91, #100, #111, #116, #125, #136, #141). Now unblocked: NewGraphEnvironment/db_newgraph PR #5 writes `s3://fresh-bc/bcfishpass/log.json` + `csvs/*` weekly Wed 12:00 UTC pinned to the rebuild SHA.

This rewrite flips the sync source from GitHub API to that S3 prefix, exposes four reusable `lnk_*` exports for downstream parity drivers + future multi-build comparison (grayling / rainbow / ko / etc.), and drops cadence to weekly Wed afternoon.

## New `lnk_*` exports (Option C — bucket + baseline families)

```r
# Bucket reads (any S3 prefix; format-agnostic — caller decodes)
lnk_bucket_get(name, prefix = "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass", to = NULL)
lnk_bucket_log(prefix = "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass")

# Run-tracking ledger (path-configurable for future multi-build use)
lnk_baseline_read(path = "data-raw/logs/bcfp_baselines.csv")
lnk_baseline_append(log, run_label, link_schema = "n/a", notes = "",
                    path = "data-raw/logs/bcfp_baselines.csv")
```

## Phase 1: Add `lnk_bucket_*` family

- [x] Implement `lnk_bucket_get(name, prefix, to)`. Uses `httr::GET()`; fails loud on non-2xx. Returns raw vector if `to = NULL`; writes to disk + returns invisible(path) if `to` given.
- [x] Implement `lnk_bucket_log(prefix)`. Sugar: `jsonlite::fromJSON(rawToChar(lnk_bucket_get("log.json", prefix)))`. Validates required keys (`model_version`, `date_completed`, `head_sha`).
- [x] Roxygen with runnable `@examples` (live S3 hit acceptable since fresh-bc is publicly readable).
- [x] Mocked unit tests in `tests/testthat/test-lnk_bucket.R`.
- [x] `devtools::document()`, `lintr::lint("R/lnk_bucket_*.R")`, `devtools::test()` clean.

## Phase 2: Add `lnk_baseline_*` family

- [x] Implement `lnk_baseline_read(path)`. Returns tibble with column shape validated against expected `cols_baseline` named vector (defined inside the file as the source of truth for ledger columns).
- [x] Implement `lnk_baseline_append(log, run_label, link_schema, notes, path)`. Constructs row from `log$model_version`, `log$date_completed`, optional `log$head_sha`. `bcfp_model_run_id` empty when `log` lacks it (Path 2). Stamps `run_started_pdt` via `format(Sys.time(), tz = "America/Vancouver", "%Y-%m-%d %H:%M")`. Stamps `host` via `Sys.info()[["nodename"]]`.
- [x] Validate column shape on append — fail loud if ledger header doesn't match `cols_baseline`.
- [x] Roxygen with runnable `@examples` using `withr::local_tempfile()`.
- [x] Mocked unit tests in `tests/testthat/test-lnk_baseline.R`.
- [x] `devtools::document()`, `lintr`, `devtools::test()` clean.

## Phase 3: Refactor `data-raw/sync_bcfishpass_csvs.R` to use new exports

- [x] Drop helpers: `fetch_raw()`, `upstream_sha_for()`, `gh_api_json()`.
- [x] Top of script: `log <- lnk_bucket_log()` once. All provenance entries take `upstream_sha = substr(log$head_sha, 1, 7)`.
- [x] Per-file: replace `fetch_raw(rel)` with `lnk_bucket_get(paste0("csvs/", basename(rel)))`.
- [x] Keep `is_bcfp_sourced()` filter, `update_provenance_in_yaml()`, `sha256_text()`, `shape_fingerprint()`, `%||%` script-local.
- [x] On drift, call `lnk_baseline_append(log, run_label = paste0("csv-sync-", format(Sys.Date(), "%Y%m%d")), notes = paste0("auto-append by csv-sync; head_sha=", substr(log$head_sha, 1, 7)))`.
- [x] Update `/tmp/sync_summary.md` template — surface `model_version`, `head_sha`, `date_completed` from log in PR body header.
- [x] Update header comment block.

## Phase 4: crate schema-validate gate

- [x] For provenance entries with `canonical_schema:` declared, read fetched bytes into a tibble, run `crt_schema_validate(df, crt_schema_read(slug))` wrapped in tryCatch.
- [x] On validation failure → escalate `drift_kind` to `"shape"` AND prepend the validation error to `/tmp/sync_summary.md`.
- [x] Files without `canonical_schema:` keep current `shape_checksum` first-line-hash check (belt + suspenders).

## Phase 5: Update GHA workflow

- [x] Cron `'0 9 * * *'` → `'0 14 * * WED'` (Wed 14:00 UTC = 7 AM PDT, ~2h after upstream dump at 12:00 UTC).
- [x] Drop `GH_TOKEN` env from sync step (no `gh api`); keep `GITHUB_TOKEN` for PR creation.
- [x] Stage `data-raw/logs/bcfp_baselines.csv` alongside `inst/extdata/configs/` in the auto-commit.
- [x] Install link locally via `local::.` so the script's `library(link)` call resolves.
- [x] Update header comment: weekly cadence rationale, S3 source, NewGraphEnvironment/db_newgraph#4 cross-ref.
- [x] Existing byte/shape gate logic stays unchanged.

## Live smoke test (blocked on rtj#114)

- [ ] Once `s3://fresh-bc/bcfishpass/*` is publicly readable (rtj#114 applies bucket policy):
  - [ ] Local `Rscript -e 'devtools::load_all("."); source("data-raw/sync_bcfishpass_csvs.R")' --dry-run` returns expected drift (bundle was last synced from SHA `4879bba`; bucket is at `6e9cf1c`).
  - [ ] `gh workflow run sync-bcfishpass-csvs.yml --repo NewGraphEnvironment/link` opens a clean PR.

## Phase 6: NEWS + DESCRIPTION + open PR

- [ ] DESCRIPTION 0.30.2 → 0.31.0 (minor — 4 new exports).
- [ ] NEWS.md 0.31.0 entry.
- [ ] `/code-check` clean on staged diff.
- [ ] `devtools::test()` + `lintr::lint_package()` + `devtools::check()` clean.
- [ ] Commit, push, open PR closing #117 with SRED tag in PR body.
- [ ] `/gh-pr-merge` (squash + tag v0.31.0).

## Phase 7: Close 8 stale daily csv-sync PRs as superseded

- [ ] Manual `gh workflow run sync-bcfishpass-csvs.yml`. Confirm clean exit.
- [ ] Close PRs #85, #91, #100, #111, #116, #125, #136, #141 with brief comment: "Superseded by weekly s3-backed cadence (#117 / PR #<n>)."
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
