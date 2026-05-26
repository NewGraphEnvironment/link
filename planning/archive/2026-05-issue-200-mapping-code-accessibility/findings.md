# Findings — mapping_code accessibility, reproduce bcfp `barriers_<sp>` (#200)

## Issue context

link's per-species mapping_code accessibility (`barriers_per_sp` → `accessible`) uses `barriers_<sp>_unified` = ALL barriers (incl dams/PSCIS/modelled) where the species is in `blocks_species`. bcfp's per-species access set is natural barriers only (gradient@species-threshold ∪ falls ∪ subsurface), MINUS upstream observation/habitat overrides, ∪ all `user_barriers_definite`. Dams are never in the access set — token2 descriptor only. Consequence: every segment below a dam reads inaccessible → `;DAM`/`;MODELLED`/`;ASSESSED` second token suppressed (token2 correctly gated on `accessible`) → link emits bare `SPAWN`/`REAR` where bcfp emits `SPAWN;DAM`.

## bcfp mechanism (read authoritatively from `smnorris/bcfishpass@e12c1a5`, 2026-05-23)

All 5 per-species access models (`model/01_access/sql/model_access_{bt,ch_cm_co_pk_sk,wct,ct_dv_rb,st}.sql`) share one structure:
```
barriers_<sp> = ( gradient@species-classes ∪ falls ∪ subsurface )
  MINUS (barriers with upstream observation OR confirmed habitat, in the species' obs-set)
  ∪ ALL barriers_user_definite        -- override-EXEMPT (comment: "include *all* user added features, even those below observations")
```
Per-species axes (the only differences across models):

| Model | Gradient classes | Obs/habitat species |
|---|---|---|
| BT | 25, 30 | BT,CH,CM,CO,PK,SK,ST |
| salmon (CH,CM,CO,PK,SK) | 15, 20, 25, 30 | CH,CM,CO,PK,SK |
| ST | 20, 25, 30 | CH,CM,CO,PK,SK,ST |
| WCT | 20, 25, 30 | (wct) |
| CT,DV,RB | 25, 30 | BT,DV,CT,RB |

- **`barriers_user_definite.sql`** materializes the definite table with a synthesized deterministic id + ltree resolved by joining the raw user CSV to `whse_basemapping.fwa_stream_networks_sp` (segment whose `[downstream_route_measure, upstream_route_measure)` contains the barrier). link's existing FALLS branch in `lnk_barriers_unify.R:221-242` does the **identical** join.
- **`load_streams_access.sql`** — `barriers_<sp>_dnstr` (per-species, natural+definite) is separate from `barriers_anthropogenic_dnstr`/`barriers_dams_dnstr` (descriptors). `access_<sp>` = 0 if a downstream barrier exists, else 1/2 (obs-aware). token2 gate (`load_streams_mapping_code.sql`) = `barriers_<sp>_dnstr = array[]` — identical to link's `ifelse(accessible, mc_barrier, NA)`.
- **Province-wide accumulation**: each `barriers_<sp>` is per-WSG-built but accumulated into one province-wide table, so cross-WSG downstream walks (PARS→PCEA→UPCE) see the correct override-applied set.

## link mapping (every ingredient already exists)

| bcfp ingredient | link object | state |
|---|---|---|
| gradient@species-threshold | `access_gradient_max` → `blocks_species` (gradient CASE in `lnk_barriers_unify`) | ✓ correct |
| obs/habitat override | `lnk_barrier_overrides` → `<schema>.barrier_overrides` (uses `fwa_upstream`, topological/cross-WSG) | ✓ computed; **per-WSG only, not persisted** |
| user_definite | `<schema>.barriers_definite` (`lnk_pipeline_prepare.R:182-200`; CSV cols, no id/ltree; empty-fallback = blk+drm only) | **per-WSG only, not in persist barriers** |
| natural barriers | persist `barriers` (gradient/falls/subsurface families) | ✓ province-wide |

`lnk_barrier_overrides` output is `(blue_line_key, downstream_route_measure, species_code)` and currently feeds only `lnk_pipeline_classify` (habitat), NOT the access path.

## The design decision (why province-wide, not a per-WSG view)

The access set is a downstream `frs_network_features` walk that **crosses WSG boundaries**. A per-WSG `_access` view (subtract only the current WSG's overrides from province-wide natural barriers) is quietly wrong for any natural barrier in a downstream/sibling WSG — the cross-WSG twin of the dam bug. Rejected. Correct design: **persist all three access inputs province-wide** (natural ✓, override → new persist table, user_definite → `USER_DEFINITE` persist family), persisted **together per WSG** so any persisted WSG is internally consistent. Caveat (single-WSG run sees only persisted WSGs) is identical to today's natural barriers and bcfp's accumulation — handled by the provincial orchestrator.

Approach A (definite as unify family) + persist overrides was chosen over the issue-draft's per-WSG view-union (B') after a Plan-agent review and the user's explicit "make it provincial, don't ship a 2/200 one-off." `barriers_definite` lacks id+ltree → resolved via the FALLS-pattern FWA join. No `cols_barriers` DDL change (USER_DEFINITE is a new row-source, same columns). `barrier_overrides` persist uses a single `cols_barrier_overrides` vector for DDL+INSERT (avoids the v0.40.3 matched-pair drift).

## Verified facts (this session)

- Persist pattern is `cols_*`-vector-driven; `cols_barriers` drives both DDL (`lnk_persist_init`) and INSERT (`lnk_pipeline_persist.R:94,99`).
- break (`lnk_pipeline_break.R:112`) + classify (`lnk_pipeline_classify.R:223`) read `<schema>.barriers_definite` separately → adding `USER_DEFINITE` to persist `barriers` does NOT double-count.
- `barriers_anthropogenic/dams/pscis_unified` filter by `barrier_source` → `USER_DEFINITE` doesn't pollute them. `lnk_compare_*` don't read `_unified`.
- `frs_network_features` (fresh) needs `feature_id_col, blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree` on the feature table. The `phase4d_plan_draft.md:37` draft wrongly dropped the ltree cols.
- `whse_basemapping.fwa_stream_networks_sp` present in local fwapg; `fresh.streams_vw_bcfp` loaded (4.23M rows, PARS 43,660, carries `mapping_code_bt`) — tunnel-free parity baseline. bcfp baseline `v0.7.15-14-ge12c1a5`.

## Phase 4 validation — PARS BT (2026-05-23)

Run `lnk_pipeline_run("PARS", mapping_code=TRUE)` against local docker fwapg (bcfp baseline `v0.7.15-14-ge12c1a5` in `fresh.streams_vw_bcfp`).

**Result: 99.04% per-segment match vs bcfp** (42,701 / 43,114 joined on `blue_line_key` + rounded `downstream_route_measure`). The headline #200 fix works:
- token1 collapse GONE — `ACCESS`/`SPAWN`/`REAR` emit (was bare `SPAWN`/`REAR`). Counts ≈ bcfp (`SPAWN;DAM` 5293 vs 5263, `REAR;DAM` 2213 vs 2191).
- token2 `;DAM` emerges — dam-downstream-but-accessible segments now annotate `;DAM` not `;NONE`.

**Cross-WSG dependency confirmed (the provincial design's whole point):** the FIRST PARS run (PARS only) emitted `;NONE` because the Bennett/Peace Canyon dams live in PCEA/UPCE, which weren't persisted. After persisting PCEA + UPCE barriers (`mapping_code=FALSE`) and re-running PARS, the cross-WSG downstream walk saw the dams → `;DAM`. token2/`barrier_sources` is unchanged by #200; it just needs the downstream WSGs in persist.

Residual ~1% (413 segs): token1 `ACCESS`↔`REAR` swaps (habitat-presence threshold — dimensions/rules, not #200) + a few token2 `DAM`↔`MODELLED` next-downstream-ordering edges. Not the dam-access divergence.

### Phase 4 validation — LFRA (anadromous; Coquitlam/Alouette/Stave/Ruskin dams)

`lnk_pipeline_run("LFRA", mapping_code=TRUE)`. Match vs bcfp: **LFRA/bt 97.77%, LFRA/co 97.90%** (26,651 segs each). LFRA coho DAM-token count link **4672 vs bcfp 4636** — the dam descriptor + above-dam path works for anadromous salmon, not just resident BT. LFRA drains to the ocean (lowest Fraser group) so its dams are in-WSG — single run, no cross-WSG persist needed (unlike PARS→PCEA/UPCE).

Residual ~2%: token1 `ACCESS`↔`SPAWN`/`REAR` (spawning/rearing **habitat-presence** — token1 habitat fires regardless of access per RUNBOOK §4; governed by `frs_habitat_classify`/dimensions, unaffected by #200) + small token2 `DAM`↔`MODELLED`/`NONE` next-downstream-ordering edges. The dam-access fix itself (token2 DAM on accessible dam-downstream segments) matches.

**Acceptance MET** for both resident + anadromous. Remaining habitat-token1 parity is a separate, pre-existing concern (habitat rules), not #200.

### Stale-persist-table drift (pre-existing, surfaced in Phase 4)

LFRA first failed: `column "has_barriers_ch_dnstr" of relation "streams_access" does not exist`. The M1 `fresh.streams_access` / `streams_mapping_code` were stale at bt+co width (old pre-v0.40.2 runs); `lnk_persist_init`'s `CREATE IF NOT EXISTS` won't widen an existing table, and `.lnk_validate_persist_table` only detects GENERATED-column drift, not species-count drift. `lnk_pipeline_run` correctly sizes persist_init to `cfg$species` (8) — so DROPping the two stale wide tables + re-running recreated them full-width. NOT a #200 bug (production provincial runs start clean). Possible follow-up: extend drift-validate to species-column count.

**Real bug caught + fixed during the run:** `barrier_overrides` PK was `(blk, drm, species_code)` — UPCE's persist INSERT collided with PCEA's because the SAME override position is computed by two adjacent WSG runs (boundary streams whose `blue_line_key` spans WSGs). Fixed: PK now includes `watershed_group_code` (mirrors `cols_barriers`), so per-WSG DELETE+INSERT is clean; the WSG-agnostic access anti-join makes the duplicate harmless.

## Open / watch

- Cross-WSG override correctness — the provincial design should fix it; **verify on LFRA** in Phase 4 (don't assume).
- `remediated_dnstr_ind` divergence is bcfp's own bug (`smnorris/bcfishpass#690`) — whitelist in the parity diff.
- Pre-existing (out of scope): `lnk_pipeline_run.R:228` `pscis = <schema>.barriers_pscis` vs view name `barriers_pscis_unified` — watch in Phase 4.
