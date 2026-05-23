# Task: mapping_code accessibility — reproduce bcfp `barriers_<sp>` (natural-only + override), provincially consistent (#200)

link's per-species mapping_code accessibility uses `barriers_<sp>_unified` = ALL barriers (incl dams) where the species ∈ `blocks_species`, so dam-downstream segments read inaccessible and lose their `;DAM` token2. bcfp's access set is natural-only (gradient@species-threshold ∪ falls ∪ subsurface) MINUS observation/habitat override ∪ all user_definite — dams annotate (token2), never block. Fix: make all access inputs province-wide-persisted (natural ✓ already, override + user_definite added), build a `barriers_<sp>_access` view over them, repoint `barriers_per_sp`. Full design: `planning/active/findings.md` + `RUNBOOK.md` §5.

## Phase 1 — make the override + user_definite province-wide

- [x] `USER_DEFINITE` family in `lnk_barriers_unify` (mirror FALLS branch: FWA-join for ltree; source `<schema>.barriers_definite`; `blocks_species`=all; reference only `blue_line_key`+`downstream_route_measure` for empty-fallback safety). No persist DDL change.
- [x] `cols_barrier_overrides` vector + `CREATE TABLE IF NOT EXISTS <persist>.barrier_overrides` in `lnk_persist_init` (one vector drives DDL + INSERT).
- [x] Persist `barrier_overrides` (DELETE-WHERE-WSG + INSERT, add `'<aoi>'` as `watershed_group_code`) in `lnk_pipeline_persist`; probe-gated.
- [x] Pre-persist auto-handled: the mapping_code-phase pre-persist (`lnk_pipeline_run.R:188`) already calls the full `lnk_pipeline_persist`, which now persists `barrier_overrides` — no separate edit needed.
- [x] Tests: unify `USER_DEFINITE` branch SQL; persist_init `barrier_overrides` DDL; persist INSERT projection. (96 pass)
- [x] DB-smoke: `barrier_overrides` DDL creates in `fresh`; USER_DEFINITE branch parses + resolves ltree/geom (empty-fallback safe + one-row).
- [x] `/code-check` (round 1 clean) + commit.

## Phase 2 — `barriers_<sp>_access` view over province-wide inputs

- [x] Per-species `_access` view in `lnk_barriers_views`: natural (`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW','USER_DEFINITE')`) over persist `barriers`, `NOT EXISTS` anti-join over `barrier_overrides` (derived from the barriers source schema via `sub()`), `USER_DEFINITE` override-exempt, expose `barriers_<sp>_access_id`, keep `wscode_ltree`/`localcode_ltree`, alias `b`.
- [x] Tests: `_access` view SQL per species; counts updated (22→38, 10→14). 30 pass.
- [x] DB-smoke: `barriers_bt_access` valid + queryable; 904,262 natural rows, 0 non-natural (dams/anthropogenic excluded) vs `_unified` 1,045,358.
- [x] `/code-check` (clean) + commit.

## Phase 3 — repoint `barriers_per_sp` → `_access`

- [ ] `lnk_pipeline_run` (:215-217) `..._unified` → `..._access`; rewrite KNOWN-DIVERGENT comment (:200-213).
- [ ] Update `test-lnk_pipeline_run.R` if it asserts the `_unified` name.
- [ ] `/code-check` + commit.

## Phase 4 — DB validation (hard gate): PARS + LFRA vs `fresh.streams_vw_bcfp`

- [ ] Rebuild PARS (BT) `mapping_code=TRUE`; diff `mapping_code_bt` vs bcfp — expect `ACCESS;DAM`/`SPAWN;DAM`/`REAR;DAM`.
- [ ] Rebuild LFRA (anadromous; Coquitlam/Alouette/Stave/Ruskin); confirm cross-WSG override correctness (the point of the provincial design).
- [ ] Whitelist known `remediated_dnstr_ind` divergence (bcfp#690) in the diff.
- [ ] Record parity numbers + four `sources` buckets (research §6) in `findings.md`.

## Phase 5 — docs + release

- [ ] `RUNBOOK.md` §5/§2a/§7 update (fix landed; province-wide override/definite persistence).
- [ ] `NEWS.md` + `DESCRIPTION` → 0.40.4 (final commit).
- [ ] `/planning-archive`, `/gh-pr-push`.

## Validation

- [ ] `devtools::test()` green
- [ ] `devtools::check()` 0 errors / no new warnings (forwarder up for db_conn test)
- [ ] Phase 4 DB parity (hard gate, incl. cross-WSG LFRA)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
