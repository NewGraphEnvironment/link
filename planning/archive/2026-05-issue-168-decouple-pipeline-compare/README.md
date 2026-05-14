# Decouple bcfp compare from link pipeline run (#168) — 2026-05-14

## Outcome

Split `lnk_compare_wsg()` into two independent functions: `lnk_pipeline_run()` (modelling — writes PG) and `lnk_compare_rollup()` (comparison — reads PG, returns rollup). Rewrote `data-raw/run_provincial_parity.R` resume check to use PG state via `.lnk_wsg_persisted()` instead of RDS file existence — closes the 2026-05-14 incident where 4 of 16 WSGs were silently skipped due to stale error-stub RDS files. Added `--force` CLI flag for cache bypass.

`data-raw/compare_bcfishpass_wsg.R` split into `wsg_pipeline_run.R` + `wsg_compare.R`; 4 callers updated to the explicit two-call pattern. `lnk_compare_wsg()` retained as a thin wrapper for backwards compat; mapping_code branch still bundled (decoupling deferred — filed as a follow-up).

Phase 7 smoke matrix validated against live DB on DEAD WSG / isolated `fresh_smoke168` schema. All four cache states behaved as designed:

| State | Setup | Wall | Outcome |
|-------|-------|------|---------|
| A — empty | drop schema + RDS | 57s | pipeline + compare fired |
| B — pipeline-cached | drop RDS only | 9s | `[compare-only]` fired (~6× speedup) |
| C — fully cached | both intact | 2s | `(cached, skip)` no-op |
| D — `--force` | both intact | 56s | both re-fired regardless of cache |

Filed-but-not-closed follow-ups (in NEWS + plan Out-of-scope):
- `lnk_compare_mapping_code` as its own family member (promotes `with_mapping_code = TRUE` flag).
- `lnk_compare_wsg → lnk_compare_run` family rename (symmetric with `lnk_pipeline_run`).
- Persist family naming pass.
- 8 other `data-raw/` script renames (stay in #172).

Closed by: PR (TBD, branch `168-decouple-pipeline-compare`, tag `v0.37.0`).
