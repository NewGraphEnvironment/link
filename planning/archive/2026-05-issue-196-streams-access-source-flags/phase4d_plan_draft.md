# Phase 4d — DRAFT plan: per-species natural-access set (reproduce bcfp `barriers_<sp>`)

Status: **draft for review — not approved, no code written.** Fixes the
mapping_code dam divergence (RUNBOOK §5). Match-bcfp first; the **dam-override**
extension (let dams be overridden by the same evidence rules — RUNBOOK §5) is
deliberately out of scope here.

## Goal

Make `barriers_per_sp` (the set that drives `accessible` → token1 ACCESS + the
token2 gate) reproduce bcfp's `barriers_<sp>`:

```
natural barriers blocking species S        -- gradient@S-threshold ∪ falls ∪ subsurface
  MINUS barriers with upstream S-observations / confirmed habitat   -- the override
  ∪ ALL user_barriers_definite                                      -- never overridden
```

Dams/PSCIS/modelled stay OUT of the access set; they remain in `barrier_sources`
→ token2 descriptor only (already correct).

## link already has every ingredient

| Need | Existing link object |
|---|---|
| Natural barriers, per-species threshold | `barriers_<sp>_unified` (persist `barriers` WHERE S ∈ `blocks_species`) filtered `barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW')` — gradient threshold is already encoded in `blocks_species` |
| Override skip list (fish/habitat above) | `<schema>.barrier_overrides` `(blue_line_key, downstream_route_measure, species_code)`, built by `lnk_barrier_overrides` in `lnk_pipeline_prepare.R:519`, per-species thresholds from `parameters_fresh` (already match bcfp) |
| User hard barriers | `<schema>.barriers_definite` (`lnk_pipeline_prepare.R:182-197`) |

So this is **composition + wiring**, not new modelling.

## Implementation

1. **New per-species access view** — extend `lnk_barriers_views` (or a sibling
   `lnk_barriers_access_views`) to emit `<schema>.barriers_<sp>_access`:
   ```sql
   SELECT id_barrier AS barriers_<sp>_access_id, blue_line_key,
          downstream_route_measure, wscode_ltree, localcode_ltree, geom
   FROM <persist>.barriers
   WHERE '<SP>' = ANY(blocks_species)
     AND barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW')   -- natural only
     AND NOT EXISTS (                                               -- override removal
       SELECT 1 FROM <schema>.barrier_overrides o
       WHERE o.species_code = '<SP>'
         AND o.blue_line_key = barriers.blue_line_key
         AND abs(o.downstream_route_measure - barriers.downstream_route_measure) < 1)
   UNION ALL
   SELECT <namespaced id>, blue_line_key, downstream_route_measure,
          wscode_ltree, localcode_ltree, geom
   FROM <schema>.barriers_definite                                  -- all species, no override
   ```
   Keeps the feature shape (`_id` col) `frs_network_features` requires (RUNBOOK §2b).

2. **Repoint** `lnk_pipeline_run` `barriers_per_sp` → `barriers_<sp>_access`
   (currently `_unified`). One-line change + comment.

3. **Ordering**: `barrier_overrides` + `barriers_definite` are built in
   `lnk_pipeline_prepare` (before the mapping_code phase), so they exist when the
   access views are created. Confirm in `lnk_pipeline_run` phase order.

4. `barrier_sources` (dams/pscis/anthropogenic/remediations) unchanged → token2.

## Open sub-questions (resolve during impl)

- **`barriers_definite` id**: does it carry a usable id for the feature view? If
  not, namespace one (mirror `lnk_barriers_unify`'s `3e9 + row_number()` trick).
- **Cross-WSG natural overrides**: `barrier_overrides` is per-WSG (working
  schema). Natural barriers downstream of an AOI but in *another* WSG (e.g. a
  fall in PCEA downstream of a PARS segment) would be in persist `barriers` but
  not covered by the AOI's local override. bcfp computes overrides province-wide.
  Likely minor (the dominant PARS downstream barriers are the dams = anthropogenic
  = excluded), but verify on LFRA where above-dam salmon obs are the whole point.
  May need a persist-wide `barrier_overrides` (parallel to the persist barriers).
- **subsurface presence**: only built when the config opts in; view filter is
  harmless when absent.

## Validation (parity targets)

- **PARS** (resident/BT, Peace dams, `mcbi_r`) and **LFRA** (anadromous,
  Coquitlam/Alouette/Stave/Ruskin dams, `mcbi_a`, above-dam sockeye obs).
- Need bcfp baseline: `fresh.streams_vw_bcfp` (1.6 GB download — currently
  missing, snapshot bug RUNBOOK §6) or tunnel.
- Acceptance: link `mapping_code_<sp>` distribution matches bcfp for PARS + LFRA
  within tolerance; specifically dam-downstream-but-accessible segments emit
  `SPAWN;DAM`/`REAR;DAM`/`ACCESS;DAM` not bare `SPAWN`/`REAR`.

## Sequencing question (for the user)

- #196's 3 persist commits (DDL, pre-persist, INSERT projection) are correct +
  independent — **ship as v0.40.3** now?
- Open Phase 4d as its **own issue** (access-set reproduction) — distinct from
  #196's persist-flag scope? Draft body for review before filing.
- Separately, `blocks_species` redesign + dam-passability extension = a third,
  later issue (RUNBOOK §5 design implication).
