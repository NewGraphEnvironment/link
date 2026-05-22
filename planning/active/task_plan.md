# Task: streams_access per-source flag persistence + cross-WSG mapping_code (#196)

Retroactive PWF — #196 was started as a "quick single-file fix" without PWF, then ballooned into a 3-bug investigation. Scaffolded mid-flight 2026-05-19 to capture the trace.

## Problem

Post-#187 `lnk_mapping_code` second token defaulted to `NONE` for every segment (should be `DAM`/`MODELLED`/`ASSESSED`/`REMEDIATED`/`NONE`). PARS BT match_pct vs bcfp dropped from historic ~98% to ~30-50%. Three coupled root causes, fixed in three commits.

## Phase 1 — persist DDL: per-source flag columns

- [x] `.lnk_cols_streams_access_source_flags()` helper in `lnk_persist_init.R` — 6 boolean cols (`has_barriers_{anthropogenic,pscis,dams,remediations}_dnstr`, `dam_dnstr_ind`, `remediated_dnstr_ind`).
- [x] Wired into `streams_access` CREATE TABLE.
- [x] `/code-check` clean.
- [x] Commit `91f3f90`.

## Phase 2 — cross-WSG visibility: pre-persist barriers

- [x] `lnk_pipeline_run` mapping_code phase: pre-persist current WSG's barriers BEFORE `lnk_barriers_views`, so views default to persist (province-wide, cross-WSG dam visibility per link#152). Reverted #187 Phase 4's `barriers_table = working` override.
- [x] `/code-check` clean.
- [x] Commit `e23819a`.

## Phase 3 — persist INSERT projection (the actual NONE bug)

- [x] `lnk_pipeline_persist`: `access_cols_v` was `base + per_sp` only — MISSING `.lnk_cols_streams_access_source_flags()`. DDL had the cols (Phase 1) but INSERT never populated them → NULL → NONE token. Added the generator to the projection.
- [x] Verified in isolation: persist `streams_access` flags now populate (anth 48559, dams 48559, dam_ind 32406 of 48559 for PARS).
- [x] `/code-check` — SKIPPED on this commit (verified empirically instead; the earlier code-check that missed this gap was the cautionary tale).
- [x] Commit `475e397`.

## Phase 4 — end-to-end verification (IN FLIGHT)

- [ ] Clean `lnk_pipeline_run(aoi="PARS", mapping_code=TRUE)` — rebuilds habitat (damaged by debug shortcut) + access + mapping_code. (task `btkkjqxlp`, ~16 min)
- [ ] Verify PARS BT `mapping_code_bt` distribution includes `ACCESS;DAM`/`ACCESS;MODELLED`/`ACCESS;ASSESSED` (not just `ACCESS;NONE`).
- [ ] Tunnel up → `lnk_compare_wsg(aoi="PARS", mapping_code=TRUE)` → match_pct vs bcfp ≥ ~95%.
- [ ] Re-run BULK too (also damaged / needs rebuild).

## Phase 5 — performance concern (NEW — decide before merge)

- [ ] Wall time blew up to 956s (~16 min) vs normal ~3.5 min for PARS — the double-persist (pre-persist barriers + final persist) re-writes streams + habitat + barriers twice. Decide:
  - (a) Accept it (correctness over speed; provincial run adds ~hours though).
  - (b) Pre-persist ONLY barriers (not streams + habitat) — the views only need barriers. Smaller helper / `only=` arg on lnk_pipeline_persist.
  - (c) Reorder so persist runs once, mapping_code phase after.
  - Likely (b). File as part of #196 or follow-up.

## Phase 6 — release v0.40.3

- [ ] DESCRIPTION 0.40.2 → 0.40.3, Date.
- [ ] NEWS.md entry.
- [ ] CLAUDE.md branch ref.
- [ ] `/planning-archive`.
- [ ] `/gh-pr-push` + `/gh-pr-merge`.

## Validation

- [ ] PARS BT tokens include DAM/MODELLED/ASSESSED
- [ ] match_pct vs bcfp restored to ~98%
- [ ] `devtools::test()` passing
- [ ] wall-time decision made (Phase 5)
- [ ] `/code-check` clean on any remaining commits
