# research

What is known about link's methods and inputs, kept current so it does not have to be
re-derived. Each topic file carries its provenance in the line under its heading.
Committed logs under `data-raw/logs/` hold the raw measurements. The PWF archives under
`planning/archive/` hold the story of the issue that produced each file.

Naming: `<topic>.md`, revised in place, from 2026-09-26. Files dated before that carry a
date in the name (`*_2026_05_25.md`); they are cited by path elsewhere and are not being
renamed.

## Methodology and parity with bcfishpass

| File | Covers |
|---|---|
| [`bcfishpass_parity.md`](bcfishpass_parity.md) | **The current parity record**: link's `bcfishpass` config against bcfishpass, km per group and species, what moved since the last score and why; revised in place by each parity run (#362) |
| [`bcfishpass_methodology.md`](bcfishpass_methodology.md) | bcfishpass methodology, the canonical reference |
| [`bcfishpass_comparison.md`](bcfishpass_comparison.md) | How link's output is compared with bcfishpass |
| [`bcfp_table_map.md`](bcfp_table_map.md) | bcfp ↔ link table relationships |
| [`bcfp_segmentation_parity.md`](bcfp_segmentation_parity.md) | Where streams break, bcfishpass and link step by step: bcfishpass's five access scripts, link's break set, how it drifted (#45, #223), why parity numbers missed it, and what it does to BT habitat (#324) |
| [`observation_breaks.md`](observation_breaks.md) | Where a fish observation breaks a stream: `default`'s top per species per line against every record, what reads code 2, what moved, the sampling bias it removes, and a smaller near-exact set, dropped (#396); since #399 code 2 normally ends at each species' highest record |
| [`species_paused.md`](species_paused.md) | Pausing a species in a bundle (`species_modelled.csv`): it adds no gradient breaks, what that moves on six groups (segments 0.2 to 6 %, habitat in two, the gradient at fish records), and what it leaves alone (barriers, accessible km) (#432, #433) |
| [`known_suspected_km.md`](known_suspected_km.md) | Accessible km with and without the species recorded upstream (access codes 2 and 1): the rollup's split, a baseline for #396's five groups, why link's observed km ran above bcfishpass's (the segment above a record) and equal them since #399, and what will move them (#403, #399) |
| [`bcfp_view_column_coding.md`](bcfp_view_column_coding.md) | `streams_vw_bcfp` column coding and the parity predicates |
| [`bcfp_compare_mapping_code.md`](bcfp_compare_mapping_code.md) | mapping_code comparison: enrich + score |
| [`bcfp_divergence_taxonomy.yml`](bcfp_divergence_taxonomy.yml) | Taxonomy that `lnk_parity_annotate()` tags divergences with |
| [`access_columns.md`](access_columns.md) | Which column says a segment is accessible: fresh's `accessible` against link's `access_<sp>`, the four mechanisms that split them, and the settle that makes the habitat flags follow link (#349) |
| [`accessible_km_divergence.md`](accessible_km_divergence.md) | `accessible_km` divergence for high-threshold species ([figure](blk359209845_bt_accessible_km.png)) |
| [`default_vs_bcfishpass.md`](default_vs_bcfishpass.md) | The `default` config vs bcfishpass, per WSG, incl. the reverted gradient floor |
| [`dimensions_audit.md`](dimensions_audit.md) | Audit of the bcfishpass bundle's `dimensions.csv` |
| [`rule_flexibility.md`](rule_flexibility.md) | Three configs, one pipeline, one CSV (data: `rule_flexibility_data.rds`) |
| [`output_vocabulary.md`](output_vocabulary.md) | Naming link's outputs: the four token axes (cut, acc, grad, flow), why access is its own axis, what stays out of tokens, and how each shipped config resolves (#414) |

## Habitat thresholds

| File | Covers |
|---|---|
| [`habitat_thresholds.md`](habitat_thresholds.md) | CH and BT gradient and channel-width thresholds, and the MAD (discharge) ranges for BT, GR, KO and RB (#302): observation evidence, literature, scoring and the `default_tuned` values; `default`'s ranges converted from its width minima (#307) |
| [`habitat_validation.md`](habitat_validation.md) | Scoring a run against fish observations (`lnk_habitat_validate()`): capture, cost, miss reasons, absences; `default` vs `bcfishpass` baseline |
| [`species_pooling.md`](species_pooling.md) | Which observation species count as evidence for which model species, by region: the state of knowledge behind `species_pooling.csv` |
| [`species_presence.md`](species_presence.md) | Which groups each species is modelled in: what a presence cell decides, the rule it is checked by (one record since 1950, releases and exclusions out, pooling applied), the 351 flags and their patterns, the codes the pipeline drops, and the review tracker (#402) |

## Runs, scope and infrastructure

| File | Covers |
|---|---|
| [`study_area_run.md`](study_area_run.md) | The tunnel-free, M1-dispatch study-area runner |
| [`study_areas.md`](study_areas.md) | Drainage-independent components and host buckets |
| [`study_area_scope_and_funders.md`](study_area_scope_and_funders.md) | Funders, and field scope vs model scope |
| [`provincial_run_runbook.md`](provincial_run_runbook.md) | Provincial run runbook |
| [`upstream_input_provenance.md`](upstream_input_provenance.md) | What pins fwapg, bcfishobs and bcfishpass inputs |
| [`recompute_parallel_2026_09_01.md`](recompute_parallel_2026_09_01.md) | Parallelising the post-consolidate recompute |
| [`recompute_cost.md`](recompute_cost.md) | What a group's recompute costs and why: the downstream walk's province-wide probe, not the barriers below the group (#261) |

## Run records (dated; kept for their evidence)

The parity files here are the history of [`bcfishpass_parity.md`](bcfishpass_parity.md), which holds the current result.

| File | Covers |
|---|---|
| [`provincial_parity_2026_05_01.md`](provincial_parity_2026_05_01.md) | Provincial parity baseline, link 0.20.0 |
| [`provincial_parity_2026_05_11.md`](provincial_parity_2026_05_11.md) | Provincial parity, link 0.35.0 |
| [`provincial_parity_2026_05_12.md`](provincial_parity_2026_05_12.md) | Provincial parity, link 0.36.0 |
| [`provincial_parity_2026_05_25.md`](provincial_parity_2026_05_25.md) | Study-area mapping_code parity |
| [`parity_accessible_habitat_2026_07_03.md`](parity_accessible_habitat_2026_07_03.md) | Accessible + spawning + rearing parity |
| [`distributed_2hosts_2026_05_01.md`](distributed_2hosts_2026_05_01.md) | First 2-host distributed parity run |
| [`run_record_2026_08_31_cypher_pilots.md`](run_record_2026_08_31_cypher_pilots.md) | v0.47.0 orchestration on a real cypher |
| [`post_compact_provincial_handoff.md`](post_compact_provincial_handoff.md) | Provincial run handoff notes |
