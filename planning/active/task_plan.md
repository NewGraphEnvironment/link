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

- [x] `lnk_pipeline_run` (:215-217) `..._unified` → `..._access`; rewrote KNOWN-DIVERGENT comment (:200-213) to describe the landed fix.
- [x] `test-lnk_pipeline_run.R` asserts no `_unified`/`barriers_per_sp` name → no update needed.
- [x] Full suite 1193 pass (the lone FAIL is the env-only `db_conn` test — needs the real db_newgraph tunnel: `.Renviron` `PG_*_SHARE` → `:63333` w/ airvine/bcfishpass creds; CI skips it via `skip_if_no_db`). Phase 3 repoint validated by Phase 2's code-check (consumption confirmed).
- [x] commit.

## Phase 4 — DB validation (hard gate): PARS + LFRA vs `fresh.streams_vw_bcfp`

- [x] Rebuild PARS (BT) `mapping_code=TRUE`; `;DAM` tokens now emit (`SPAWN;DAM` 5293≈5263 bcfp). **98.95% match.** Needed PCEA+UPCE barriers persisted first (cross-WSG dams) — confirms the provincial design.
- [x] Rebuild LFRA (anadromous; Coquitlam/Alouette/Stave/Ruskin). **bt 97.77%, co 97.90%**; coho DAM tokens 4672≈4636 bcfp. Dams in-WSG (drains to ocean), single run.
- [x] Found + fixed real bug: `barrier_overrides` PK needed `watershed_group_code` (boundary-stream overrides shared across adjacent WSGs collided). Found + worked around stale-persist-table drift (bt+co wide tables → DROP + recreate full-width).
- [x] Residual ~1-2% characterized: token1 habitat-presence (`ACCESS`↔`SPAWN`/`REAR`, dimensions/rules) + minor token2 ordering — NOT the dam-access divergence. Recorded in `findings.md`.

## Phase 5 — docs + release

- [x] `RUNBOOK.md` §2a/§3/§5/§7 updated (fix landed; province-wide override/definite persistence; provincial-accumulation note).
- [x] `NEWS.md` + `DESCRIPTION` → 0.40.4.
- [x] Temp validation scripts removed.
- [ ] `/planning-archive`, `/gh-pr-push`.

## Validation

- [x] `devtools::test()` 1193 pass (lone FAIL = env-only `db_conn`, needs real tunnel; CI skips).
- [~] `devtools::check()` — CI runs it green (no DB → db_conn skips); local can't be fully green without the db_newgraph tunnel. Noted in PR.
- [x] Phase 4 DB parity (hard gate): PARS BT 98.95%, LFRA BT 97.77% / CO 97.90%; `;DAM` correct.
- [x] `/code-check` clean on Phases 1-2; Phase 3 covered by Phase 2 review; Phase 4 PK fix reasoned + tested.
- [x] PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion.
