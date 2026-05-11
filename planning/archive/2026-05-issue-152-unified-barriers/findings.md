# Findings — Unified <persist_schema>.barriers (#152)

## Issue context

## Problem

`lnk_pipeline_access()` consumes bcfp-shape per-species barriers tables (`barriers_bt`, `barriers_ch_cm_co_pk_sk`, `barriers_ct_dv_rb`, ...). Today link only materializes:

- Source-typed bcfp-shape tables in the per-WSG working schema: `<schema>.barriers_anthropogenic`, `barriers_dams`, `barriers_pscis`, `barriers_remediations` (built by `lnk_pipeline_crossings`)
- Per-species minimal scratch tables: `<schema>.barriers_<sp>_min` with only `(blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree)` -- no ID, no `barrier_type`, none of the bcfp metadata `lnk_pipeline_access` needs

Two problems with the current state:

1. **Per-species barriers gap.** End-to-end mapping_code parity from local primitives is blocked. The v0.30.0 validation worked by pointing `lnk_pipeline_access` at `bcfishpass.barriers_<sp>` on the tunnel -- that path validates parity logic but isn't self-sufficient. Phase 6 of #138 archive: *"deferred -- depends on `lnk_pipeline_prepare` observations bug + populated CABD dams flow + bcfishobs.observations parquet."*

2. **Cross-WSG dnstr.** Phase A bcfp parity validation (research/bcfp_compare_mapping_code.md, 2026-05-10) surfaced that per-WSG barrier staging can't reproduce bcfp's `dam_dnstr_ind` for WSGs that drain through dams in other WSGs. PARS BT match was 56% because PARS drains through W.A.C. Bennett (PCEA), Peace Canyon (UPCE), and Site C (UPCE) dams. The barriers live in *other* WSGs; per-WSG `WHERE watershed_group_code = 'PARS'` filtering misses them.

Materializing 8+ per-species tables matching bcfp's pattern would unblock parity but locks link into bcfp's species-centric view of "what blocks fish." link's roadmap extends to water quality, jurisdictions, and temperature -- none of which are species-typed in the same way.

## Proposed solution

One unified barriers table at the **province-wide persist schema** level (matching link's existing persistence pattern for `<persist_schema>.streams` and `<persist_schema>.streams_habitat_<sp>`), with predicate columns replacing per-species materialized tables:

```sql
<persist_schema>.barriers (
  barrier_id text PRIMARY KEY,
  barrier_source text,           -- 'PSCIS' | 'CABD' | 'MODELLED' | 'GRADIENT' | 'FALLS' | 'SUBSURFACE_FLOW'
  barrier_subtype text,          -- 'gradient_15' | 'dam' | 'culvert' | 'falls' | etc.
  passability text,              -- 'BARRIER' | 'POTENTIAL' | 'PASSABLE' | 'UNKNOWN'
  blocks_species text[],         -- pre-computed: which species this row blocks
  linear_feature_id, blue_line_key, watershed_key,
  downstream_route_measure, wscode_ltree, localcode_ltree,
  watershed_group_code,
  geom,
  attributes jsonb               -- source-specific (height_m, gradient, etc.)
)
```

`<persist_schema>` resolves from `cfg$pipeline$schema` -- same source as `<persist_schema>.streams`. Each config bundle picks its own name (`fresh` for the bcfishpass bundle, `fresh_default` for the default bundle).

**Persistence pattern** (mirrors `lnk_pipeline_persist` for `streams_habitat_<sp>`):

- `lnk_pipeline_crossings` (per-WSG) writes its slice to `<persist_schema>.barriers` via the same idempotent `DELETE WHERE watershed_group_code = <aoi>; INSERT ...` pattern already used for habitat output.
- The province-wide table accumulates across WSG runs; cross-WSG dnstr lookups in `lnk_pipeline_access` see all barriers regardless of which WSG they live in.
- Trifecta consolidation uses the existing `data-raw/consolidate_schema.R` flow -- same as how `<persist_schema>.streams_habitat_<sp>` consolidates from M1 + cypher onto M4.

**`blocks_species` semantics:**

- Anthropogenic with `passability IN ('BARRIER', 'POTENTIAL')` -> blocks all 8 species
- Anthropogenic `PASSABLE` -> blocks none
- `GRADIENT` `gradient_<n>` -> blocks species whose `access_gradient_max < n/100` (per `parameters_fresh.csv`)
- `FALLS` / `SUBSURFACE_FLOW` -> blocks all 8 (matches bcfp's natural barrier semantics)

**`lnk_pipeline_access` query becomes:**

```sql
WHERE 'bt' = ANY(blocks_species)
```

passed to `fresh::frs_network_features()` (already abstract over any features table, walks downstream via FWA topology -- cross-WSG dnstr just works).

**bcfp-shape adapter for parity output:** add `lnk_barriers_to_bcfp_shape(unified_table, species_groupings, to)` that materializes bcfp's per-species tables on demand from the unified table. This is what runs during parity validation -- the unified table is link's internal model, the bcfp shape is one specific projection.

## Why now

Three things converging at this decision point:

1. v0.30.0 added `lnk_pipeline_access`, v0.32.0 added `lnk_pipeline_crossings` with source-typed barriers. The next step is per-species barriers -- which can either follow bcfp's pattern (lock-in) or generalize (flexibility for WQ / temperature / jurisdiction).
2. PARS BT 56% (cross-WSG dnstr) shows per-WSG barrier scoping is structurally insufficient.
3. Cost analysis (full provincial trifecta, 250 WSG runs):

| Strategy | Total row-loads | Note |
|---|---|---|
| Re-stage province-wide per run | ~375M | Naive |
| Topology-aware (downstream chain) | ~7.5M | Brittle topology graph |
| **Stage once into province-wide schema** | **~1.5M** | Same pattern as `lnk_pipeline_persist` for `streams_habitat_<sp>` |

Province-wide persist schema wins by ~5x over topology-aware in aggregate, and is the same persistence pattern link already uses.

## Future extensibility (out of scope but considered)

The same pattern generalizes to non-species predicates:

- `barrier_source = 'TEMPERATURE'`, `attributes = {"lethal_threshold_c": 22}`
- `barrier_source = 'WATER_QUALITY'`, `attributes = {"failed_param": "DO"}`
- `barrier_source = 'JURISDICTION'`, `attributes = {"access_type": "private_no_access"}`

For non-species predicates we'd add parallel arrays (`blocks_jurisdictions`, etc.) or generalize to a `blocks_what jsonb` map. Out of scope for this issue -- explicitly do this when the second dimension lands.

## Implementation outline

1. **`lnk_barriers_unify(conn, aoi, cfg, schema = paste0("working_", tolower(aoi)))`** -- new exported function. Follows the same signature pattern as `lnk_pipeline_persist`. Reads source-typed tables from working `<schema>` (`barriers_anthropogenic`, `barriers_dams`, etc.) plus per-species access-gradient thresholds from `parameters_fresh`. Computes `blocks_species` per row. Upserts to `<persist_schema>.barriers` (DELETE WHERE watershed_group_code = aoi; INSERT) -- `<persist_schema>` resolved from `cfg$pipeline$schema`.

2. **`lnk_persist_init` extension** -- when initializing the persist schema, also create `<persist_schema>.barriers` (alongside `streams` and `streams_habitat_<sp>`).

3. **`lnk_barriers_to_bcfp_shape(conn, persist_schema, species_groupings, to)`** -- adapter. Reads `<persist_schema>.barriers`, emits bcfp's per-species tables for parity validation. Optional, only invoked by compare scripts.

4. **`lnk_pipeline_access` refactor** -- accept either a unified barriers table reference (preferred), or fall back to bcfp-shape per-species tables (existing path). Allows in-place migration. The unified path reads from `<persist_schema>.barriers` so cross-WSG dnstr works.

5. **Pipeline wiring** -- add `lnk_barriers_unify` after `lnk_pipeline_crossings` and `lnk_pipeline_prepare`'s gradient/falls/subsurface steps. Drives `lnk_pipeline_access` from the unified table.

6. **Tests** -- unit tests on the `blocks_species` derivation logic; live multi-WSG test confirming PARS BT mapping_code parity >=99% from `<persist_schema>.barriers` (was 56% with per-WSG staging -- cross-WSG dam_dnstr_ind validation).

## Out of scope

- `streams_mapping_code` and `streams_access` persistence is a separate concern -- Phase B in `research/bcfp_compare_mapping_code.md`. This issue covers the **barrier shape**; mapping_code / access output persistence stays per-WSG-only until Phase B lands.
- Generalizing `blocks_species` to water quality / temperature / jurisdiction predicates -- separate issue when those dimensions land.
- Removing the source-typed bcfp-shape tables (`barriers_anthropogenic` etc.) in working schema -- keep them; they're useful primitives and the `unify` step reads from them.

## Acceptance

- [ ] `<persist_schema>.barriers` materializes correctly with all source rows + `blocks_species` populated
- [ ] `lnk_pipeline_access` runs from `<persist_schema>.barriers` -> produces `streams_access` byte-identical (within tolerance) to a run pointed at the bcfp tunnel barriers (the Phase A baseline established before this issue lands)
- [ ] `lnk_barriers_to_bcfp_shape` produces tables structurally identical to `bcfishpass.barriers_<sp>`
- [ ] **PARS BT mapping_code parity >=99% from local-only inputs** (validates cross-WSG dam_dnstr_ind -- was 56% with per-WSG staging in Phase A baseline)
- [ ] Mapping_code parity (`compare_bcfp_mapping_code.R --wsgs=ADMS,BULK,WILL,PARS`) >=99% on all multi-WSG runs
- [ ] Roxygen + lintr clean on all new exports

