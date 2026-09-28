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
| [`bcfishpass_methodology.md`](bcfishpass_methodology.md) | bcfishpass methodology, the canonical reference |
| [`bcfishpass_comparison.md`](bcfishpass_comparison.md) | How link's output is compared with bcfishpass |
| [`bcfp_table_map.md`](bcfp_table_map.md) | bcfp ↔ link table relationships |
| [`bcfp_view_column_coding.md`](bcfp_view_column_coding.md) | `streams_vw_bcfp` column coding and the parity predicates |
| [`bcfp_compare_mapping_code.md`](bcfp_compare_mapping_code.md) | mapping_code comparison: enrich + score |
| [`bcfp_divergence_taxonomy.yml`](bcfp_divergence_taxonomy.yml) | Taxonomy that `lnk_parity_annotate()` tags divergences with |
| [`accessible_km_divergence.md`](accessible_km_divergence.md) | `accessible_km` divergence for high-threshold species ([figure](blk359209845_bt_accessible_km.png)) |
| [`default_vs_bcfishpass.md`](default_vs_bcfishpass.md) | The `default` config vs bcfishpass, per WSG, incl. the reverted gradient floor |
| [`dimensions_audit.md`](dimensions_audit.md) | Audit of the bcfishpass bundle's `dimensions.csv` |
| [`rule_flexibility.md`](rule_flexibility.md) | Three configs, one pipeline, one CSV (data: `rule_flexibility_data.rds`) |

## Habitat thresholds

| File | Covers |
|---|---|
| [`habitat_thresholds.md`](habitat_thresholds.md) | CH and BT gradient and channel-width thresholds: observation evidence, literature, and the `default_tuned` candidates |
| [`habitat_validation.md`](habitat_validation.md) | Scoring a run against fish observations (`lnk_habitat_validate()`): capture, cost, miss reasons, absences; `default` vs `bcfishpass` baseline |
| [`species_pooling.md`](species_pooling.md) | Which observation species count as evidence for which model species, by region: the state of knowledge behind `species_pooling.csv` |

## Runs, scope and infrastructure

| File | Covers |
|---|---|
| [`study_area_run.md`](study_area_run.md) | The tunnel-free, M1-dispatch study-area runner |
| [`study_areas.md`](study_areas.md) | Drainage-independent components and host buckets |
| [`study_area_scope_and_funders.md`](study_area_scope_and_funders.md) | Funders, and field scope vs model scope |
| [`provincial_run_runbook.md`](provincial_run_runbook.md) | Provincial run runbook |
| [`upstream_input_provenance.md`](upstream_input_provenance.md) | What pins fwapg, bcfishobs and bcfishpass inputs |
| [`recompute_parallel_2026_09_01.md`](recompute_parallel_2026_09_01.md) | Parallelising the post-consolidate recompute |

## Run records (dated; kept for their evidence)

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
