# Progress — csv-sync rewrite (#117)

## Session 2026-05-07

- Plan-mode exploration — phases approved by user with Option C naming for new exports
- Branch `117-csv-sync-switch-to-weekly-cadence-sha-pi` created off main (5ba87b5, v0.30.2)
- Scaffolded PWF baseline with approved phases
- Upstream NewGraphEnvironment/db_newgraph PR #5 merged earlier in session — s3://fresh-bc/bcfishpass/ now auto-refreshes weekly Wed 12:00 UTC
- Phase 1 done: `lnk_bucket_get()` + `lnk_bucket_log()` shipped with mocked unit tests (6 tests). httr + jsonlite added to Imports.
- Phase 2 done: `lnk_baseline_read()` + `lnk_baseline_append()` shipped with `withr::local_tempfile`-based unit tests (8 tests). `cols_baseline` is the column source-of-truth.
- Full test suite: 808 PASS / 0 FAIL. Lints clean.
- Next: Phase 3 — refactor `data-raw/sync_bcfishpass_csvs.R` to consume the new exports.
