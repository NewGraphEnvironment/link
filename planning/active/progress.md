# Progress — #56 CSV sync workflow

## Session 2026-04-26

- Branch `56-csv-sync-action` off `main` (post v0.11.0 merge)
- PWF baseline: task plan + findings written
- Cadence decision: nightly Mon-Sat 09:00 UTC, based on observed
  upstream churn (1-3 CSV-touching PRs per active weekday in April
  2026). Smaller per-PR diffs, easier review/trace.
- Approach: R script (reuses `digest` + yaml + `lnk_config()`) does
  the work; workflow shell only orchestrates check-in + PR creation.
- 7 bcfishpass-sourced files tracked per bundle; bundles share files
  byte-for-byte today, so script writes once and copies to both.
- Next: Phase 2 — write `data-raw/sync_bcfishpass_csvs.R`.
