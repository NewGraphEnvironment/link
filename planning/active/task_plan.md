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

## Phase 4b — Cause 4 fix: barriers_per_sp `_unified` → `_min` (NEW)

- [x] Root-caused: `_unified` (all barriers) over-blocks; `_min` (gradient+falls natural barriers) is correct per-species access set. Dams stay in `barrier_sources` (token2 only). Grounded in pre-#187 matching code + prep_minimal source.
- [x] Swap applied in `lnk_pipeline_run` Phase 4 (uncommitted).
- [x] Verify: PARS run (task `bpzeq473w`) → **FAILED mechanically**. `barriers_bt_min_id does not exist` — `_min` tables are break-specs (no id col); `frs_network_features` needs a feature id. `_min` cannot feed `barriers_per_sp`. See findings.
- [x] Architectural finding: `barriers_<sp>_unified` = persist barriers WHERE species ∈ blocks_species (#152), feature-shaped w/ id. Correct fix = per-species feature view, `_unified` shape, natural-only filter — but gated on bcfp semantics.
- [ ] **REVERT the `_min` swap** in lnk_pipeline_run (restore `_unified`) — known state for the data investigation. (deferred until snapshot confirms direction)

## Phase 4c — empirical bcfp semantics (BLOCKING — redo snapshot)

- [x] Tunnel down (stale). Snapshot script is tunnel-free (public sources). Run `snapshot_bcfp.sh --with-bcfp-views --force` → local `fresh.streams_bcfp` (task `be94vol3c`).
- [ ] Inspect `fresh.streams_bcfp` columns — does it carry `mapping_code_bt` + access cols per segment?
- [ ] Row-level: PARS segments above Bennett/Peace Canyon dams — bcfp `mapping_code_bt` value? In bcfp's accessible set or not?
- [x] **RESOLVED by reading bcfp source** (not data — authoritative). Fix shape = (a): per-species access set is natural-only + override-filtered; dams never block access. See findings (RESOLVED 2026-05-23) + RUNBOOK.md §5.
- [x] Reverted broken `_min` swap → `_unified` (runnable, known-divergent) w/ comment → RUNBOOK §5.
- [x] Documented authoritatively in RUNBOOK.md (§2a, §5) + CLAUDE.md pointer + findings. (user ask: "do our homework and document so we can find it")
- [ ] streams_vw_bcfp retry (task b122hazyb) for empirical parity numbers (snapshot's streams view failed on transient gzip).

## Phase 4d — the real fix (NEW, needs scoping/approval)

- [ ] Build per-species NATURAL-only *feature* view reproducing bcfp `barriers_<sp>`:
  gradient@species-threshold + falls + subsurface, MINUS observation/habitat
  overrides, ∪ user_barriers_definite. Has-id (feature shape, §2b).
- [ ] Wire `lnk_barrier_overrides` output into the access path (currently classify-only).
- [ ] Point `barriers_per_sp` at the new view; dams stay in barrier_sources (token2).
- [ ] Candidate issue: `blocks_species` redesign (carry ingredients, classify access late) — RUNBOOK §5 design implication. Draft + review before filing (no unreviewed issues).

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
