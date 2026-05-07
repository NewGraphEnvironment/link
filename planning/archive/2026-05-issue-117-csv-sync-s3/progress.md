# Progress — csv-sync rewrite (#117)

## Session 2026-05-07

- Plan-mode exploration — phases approved by user with Option C naming for new exports
- Branch `117-csv-sync-switch-to-weekly-cadence-sha-pi` created off main (5ba87b5, v0.30.2)
- Scaffolded PWF baseline with approved phases
- Upstream NewGraphEnvironment/db_newgraph PR #5 merged earlier in session — s3://fresh-bc/bcfishpass/ now auto-refreshes weekly Wed 12:00 UTC
- Phase 1 done: `lnk_bucket_get()` + `lnk_bucket_log()` shipped with mocked unit tests (6 tests). httr + jsonlite added to Imports.
- Phase 2 done: `lnk_baseline_read()` + `lnk_baseline_append()` shipped with `withr::local_tempfile`-based unit tests (8 tests). `cols_baseline` is the column source-of-truth.
- Full test suite: 808 PASS / 0 FAIL. Lints clean.
- Phase 3 done: `data-raw/sync_bcfishpass_csvs.R` rewritten to use `lnk_bucket_log()` + `lnk_bucket_get()` + `lnk_baseline_append()`. Dropped `fetch_raw`, `upstream_sha_for`, `gh_api_json`. All provenance entries get the same `upstream_sha` from log.json.
- Phase 4 done: crate schema-validate gate inline in the script — `validate_canonical_schema()` returns NULL on success or error message string on failure; failures escalate drift_kind to "shape" and surface in the PR body.
- Phase 5 done: workflow cron Sun -> Wed 14:00 UTC; dropped GH_TOKEN from sync step; install link locally via `local::.`; staged `bcfp_baselines.csv` alongside provenance updates in auto-commit.
- Smoke test: live S3 fetch returns 403 — bucket has BlockPublicAccess. Filed NewGraphEnvironment/rtj#114 to apply public-read policy on `bcfishpass/*` prefix.
- Next: Phase 6 (NEWS + DESCRIPTION + draft PR with rtj#114 dependency noted) once we either wait or unblock another way.
