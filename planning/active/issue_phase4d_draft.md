# DRAFT ISSUE — review before filing (not filed)

**Title:** mapping_code accessibility: reproduce bcfp `barriers_<sp>` (natural-only + override) so dam-downstream segments emit `;DAM`

**Labels:** bug, mapping_code

## Problem

link's per-species mapping_code accessibility (`barriers_per_sp` →
`accessible`) uses `barriers_<sp>_unified` = ALL barriers (incl dams/PSCIS/
modelled) where the species is in `blocks_species`. bcfp's per-species access
set (`barriers_<sp>`) is **natural barriers only** (gradient at the species
threshold + falls + subsurface), MINUS barriers with upstream observations /
confirmed habitat, ∪ all `user_barriers_definite`. Dams are never in the access
set — they're a downstream descriptor (token2) only.

Consequence: every segment below a dam reads inaccessible for that species, so
the `;DAM`/`;MODELLED`/`;ASSESSED` second token is suppressed (token2 is gated
on `accessible`, correctly, matching bcfp). link emits bare `SPAWN`/`REAR` where
bcfp emits `SPAWN;DAM`. Full trace + authoritative bcfp source refs in
`RUNBOOK.md` §5; bcfp files: `smnorris/bcfishpass@v0.7.15`
`model/01_access/sql/model_access_bt.sql`, `load_streams_access.sql`,
`model/02_habitat_linear/sql/load_streams_mapping_code.sql`.

## Fix (composition + wiring — link has all the pieces)

Build `<schema>.barriers_<sp>_access` (feature-shaped, keeps `_id`):

```
barriers_<sp>_unified WHERE barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW')  -- natural only
  ANTI-JOIN <schema>.barrier_overrides ON (blue_line_key, ~downstream_route_measure, species_code)
  UNION ALL <schema>.barriers_definite                                                 -- all species
```

Repoint `lnk_pipeline_run` `barriers_per_sp` → `_access`. Dams stay in
`barrier_sources` (token2). Implementation detail in
`planning/active/phase4d_plan_draft.md`.

## Open sub-questions

- `barriers_definite` id (synthesize if absent).
- cross-WSG natural overrides (barrier_overrides is per-WSG; may need persist-wide).
- subsurface opt-in.

## Acceptance

PARS (resident/BT) + LFRA (anadromous, Coquitlam/Alouette/Stave/Ruskin) parity
vs bcfp `streams_vw_bcfp`: dam-downstream-but-accessible segments emit
`SPAWN;DAM`/`REAR;DAM`/`ACCESS;DAM`. (Needs the 1.6 GB bcfp streams baseline —
snapshot bug, see RUNBOOK §6.)
