# Progress — Provincial run autonomy + script renames (#172)

## Session 2026-05-14 (afternoon — post-#168)

- Resumed #172 against the new #168 architecture. PG-state resume + decoupled `wsg_pipeline_run`/`wsg_compare` are now in place, so most of yesterday's first-attempt scab fixes (smoke auto-skip, archive --config, phantom-cy mitigation via fallback paths) became unnecessary.
- Plan-mode exploration — phases approved by user. Locked in yesterday's rename decisions (umbrella = `wsgs_run_pipeline.sh`, per-host loop = `wsgs_run_host.R`, mixed nouns for other wrappers).
- Cypher integration deferred to follow-up — keeps PR scope tight, matches #168 discipline.
- rtj cross-repo update authorized (direct commit + push).
- Created branch `172-provincial-run-autonomy-renames` off main (v0.37.0 baseline).
- Scaffolded PWF baseline (`task_plan.md`, `findings.md`, `progress.md`) with 7 approved phases.
- **Phase 1 done.** Added `--wsgs=`, `--no-cyphers`, `--force` to `trifecta_provincial.sh`. Fixed phantom-cy (R's `paste0("cy", integer(0))` → `"cy"` recycling bug) via 3-branch `cy_host_keys`. Hardened empty-`CY_WORKSPACES` init. `/code-check` round 1 caught a silent-abort bug (R `stop()` exits bash without operator-visible message under `SPLIT_OUT=$(...)`); fixed with explicit `||` block dumping SPLIT_OUT to stderr. Round 2 clean. SPLIT_R logic verified via isolated R run.
- **Phase 2 done.** Added 5 new flags to `province_run.sh`. Gated Step 3+4 (cypher spin/prep), Step 5 cypher archive, Step 9 cypher-source consolidate, and trap-EXIT burn behind `if NO_CYPHERS=0`. Step 7 omits `--cy-workspaces=...` under `--no-cyphers` or `--wsgs`. Step 8 ANN_CSV path is config-aware. Auto-skip-smoke fires when smoke assumptions don't hold. `/code-check` round 1 caught a silent TARGET_SCHEMA fallback bug (masked misconfigured `--config=` with hardcoded "fresh"); fixed with explicit guards. Round 2 clean.
- Next: Phase 3 — M4+M1 16-WSG integration test on the patched-but-not-yet-renamed scripts.
