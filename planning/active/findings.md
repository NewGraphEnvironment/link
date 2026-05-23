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

## Open / watch

- Cross-WSG override correctness — the provincial design should fix it; **verify on LFRA** in Phase 4 (don't assume).
- `remediated_dnstr_ind` divergence is bcfp's own bug (`smnorris/bcfishpass#690`) — whitelist in the parity diff.
- Pre-existing (out of scope): `lnk_pipeline_run.R:228` `pscis = <schema>.barriers_pscis` vs view name `barriers_pscis_unified` — watch in Phase 4.
