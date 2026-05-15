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
- **Phase 3 done — autonomy validated.** Two-attempt journey:
  - **Attempt 1**: 16-WSG dispatch ran fine (16/16 RDS, 17m wall, exit 0) but consolidate hit 6 duplicate-key errors. M1's `fresh_default` had leftover WSGs from yesterday's province-wide dispatch; `pg_dump --schema=fresh_default` pulled rows for WSGs outside the current bucket, colliding with M4's data. Only 12 of 16 landed.
  - **Root-cause fix** (Phase 1.5 commit `89da284`): added `state_clean.sh --schemas=<csv>` scoped mode (drops only listed schemas, skips canonical-fresh wipe + snapshot reload) + `province_run.sh` Step 0 pre-clean that fires when `--schema=` is set. Empty `--schemas=` guard added per round-1 code-check.
  - **Attempt 2** (with pre-clean): 16/16 WSGs in `fresh_default.streams` on M4, 20m wall (pre-clean + cold-cache pipeline + consolidate). Exit 0. No mid-run prompts. Annotated CSV: 343 rows; 66 UNEXPLAINED at ≥2% surfaced as WARNING (methodology divergence for `default` bundle, expected for northern-WSG test set).
- Pre-existing limitation surfaced (consolidate stale-state collision) → resolved as part of #172 scope because the autonomy story requires it; the umbrella now genuinely runs end-to-end without operator handholding even when the cluster has leftover state.
- Next: Phase 4 — rename 8 operational scripts to noun_verb convention (git mv + reference updates).
