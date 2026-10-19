# Plan review — #348 (Plan agent, 2026-10-19 ~04:00 UTC)

Reviewer read the plan, the issue and the code while Phase 1-2 were being written,
so it reviewed the draft as well as the plan. The findings and what was done with each:

| # | Finding | Probe | Disposition |
|---|---|---|---|
| Blocker 1 | `--recompute-only` never checks that `--config` is the run's config; a forgotten `--config` recomputes 241 groups under `bcfishpass` and stamps them with the run's uid | `fresh_default.log` for the run: `config_name` = `default` only | **Fix:** refuse unless the run's log names exactly `$CONFIG` |
| A1 | "Closed row for run_uid" ≠ "these rows are this run's" when a later run rebuilt the group, or a hand re-run under the same uid failed after pre-persist | 241 groups in `fresh_default` have a newest row that is closed and from this run | **Fix:** a group counts as finished only if its newest `log` row (max `date_start`, the same rule `schema_consolidate.R` uses) is closed and has this run_uid; signals still add. Fixture cases for both. |
| Gap 1 | The log-derived expected set misses groups that failed before the log opened, and whole runs that died before `run_finish` | — | Deferred: `--wsgs=` covers it; follow-up issue (persist the run's group list at bucket time) |
| Gap 2 | A `--wsgs=` subset leaves upstream groups unsettled | — | **Fix:** WARN when `--wsgs=` is a strict subset of the run's log groups |
| Gap 3 | A compare failure exits before the report, hiding the missing-group names | — | **Fix:** flag it and fall through to the report |
| Gap 4 | Discharge / wet-load resolution runs before the recompute-only branch and can FATAL a recompute that never reads discharge | `wsg_recompute_one.R` reads no discharge | **Fix:** gate on `RECOMPUTE_ONLY=0` |
| Gap 5 | Driver glue (expected minus SKIP, signals) is untested inline code | — | **Fix:** `run_expected_from_hosts` in the lib, tested with plain maps. Subtract only SKIPs no host finished; WARN (drift), not note. |
| Gap 6 | Coverage leaves no artifact | — | **Fix:** `${TS}_coverage.tsv` (wsg, class) |
| Gap 7 | `study_area_verify.sql` stays red after the recovery for a group whose failed attempt left an open row on the dispatcher | — | **Doc:** RUNBOOK §8d says so |
| Gap 8 | Recovery command omits `LNK_GUARD_DOWNSTREAM=warn` and `LNK_RUN_LABEL` | `wsg_run_one.R` guard defaults to `error` | **Fix** |
| Gap 9 | Recompute-only skips all pre-flight | — | Partial: add the `fresh.streams_vw_bcfp` check (the compare needs it). SHA exports fall back to the local checkouts, the same source the pre-flight reads; dirty check not added. |
| Gap 10 | Nothing stops two finishes on one schema (a paused driver plus `--recompute-only`) | — | **Doc:** RUNBOOK warning; no lock (deferred) |
| Gap 11 | Kept-host recovery text still says "recompute every group … wsg_recompute_one.R" | — | **Fix:** point at `--recompute-only --run-uid=` (finish lib, hosts lib, RUNBOOK) |
| Ordering 1 | Plan says run_finish returns the status; it exits | — | Plan text corrected |
| Ordering 2 | Plan says stubbed pool; tests run the real pool against an Rscript stub | — | Plan text corrected |
| Ordering 3 | Add mutants: newest-row term, empty-set skip | — | **Done** in Phase 4 |
| Scope 1 | Consolidate failure still exits before coverage (same failure class) | — | Banner now prints the `--recompute-only` recovery; follow-up issue for the rest |
| Acceptance 1 | Acceptance says "driver exits"; tests exercise `run_finish` (driver `LOG_DIR` is under the repo) | — | Stated in the plan: the lib-level test stands in for the driver |
