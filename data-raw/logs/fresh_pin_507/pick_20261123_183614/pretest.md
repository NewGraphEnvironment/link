# Pre-run gate (link#372)

- config `default` (chain: default), history in `fresh_default.log` under `default`
- link `4dfbfa4980eb..565e4478ae27`; fresh `v0.52.0..v0.56.0`
- per input 2 groups; bound 3 x last minutes (`fresh_default.log`, or `data-raw/logs/build_minutes.csv` where newer, scaled to m1 at speed 1.31; 60 min where neither has the group), floor 5 min; statement bound <= 30 min

## Changed files (84)

| repo | file | inputs |
|---|---|---|
| fresh | `R/frs_cluster.R` | segments |
| fresh | `R/frs_db_conn.R` | any, none |
| fresh | `R/frs_habitat_classify.R` | near_river_conn, segments |
| fresh | `R/frs_habitat_overlay.R` | segments |
| fresh | `R/frs_habitat_predicates.R` | near_river_conn, segments |
| fresh | `R/frs_habitat.R` | segments |
| fresh | `R/frs_near_river.R` | near_river_conn |
| fresh | `R/frs_order_child.R` | segments |
| fresh | `R/utils.R` | any |
| link | `data-raw/schema_consolidate.R` | unexercised |
| link | `data-raw/study_area_run.sh` | unexercised |
| link | `data-raw/wsg_recompute_one.R` | unexercised |
| link | `data-raw/wsg_run_one.R` | any |
| link | `data-raw/wsg_stall_sample.R` | any |
| link | `DESCRIPTION` | none |
| link | `inst/extdata/configs/default/config.yaml` | any, dams, observations, segments |
| link | `inst/extdata/configs/default/overrides/observation_exclusions_link.csv` | gradient, observations |
| link | `inst/extdata/configs/default/overrides/README.md` | none |
| link | `inst/extdata/configs/default/overrides/wsg_species_presence_overlay.csv` | segments |
| link | `inst/extdata/configs/default/overrides/wsg_species_presence.csv` | segments |
| link | `inst/extdata/configs/default/parameters_fresh.csv` | gradient, obs_upstream, observations, segments |
| link | `inst/extdata/configs/default/presence_groups.csv` | gradient, segments |
| link | `inst/extdata/configs/default/README.md` | none |
| link | `inst/extdata/configs/default/species_pooling.csv` | gradient, obs_upstream, observations, segments |
| link | `inst/extdata/configs/default/wsg_species_presence_review.csv` | none |
| link | `inst/extdata/configs/dictionary_parameters_fresh.csv` | none |
| link | `inst/extdata/configs/dictionary_presence_groups.csv` | none |
| link | `inst/extdata/configs/dictionary_species_groups.csv` | none |
| link | `inst/extdata/configs/dictionary_species_modelled.csv` | none |
| link | `inst/extdata/configs/dictionary_species_pooling.csv` | none |
| link | `inst/extdata/configs/dictionary_wsg_species_presence_review.csv` | none |
| link | `inst/extdata/schemas/habitat_fwa_v1_segment.yaml` | none |
| link | `inst/extdata/vocabulary.csv` | any |
| link | `R/lnk_access.R` | unexercised |
| link | `R/lnk_aggregate.R` | none |
| link | `R/lnk_artifact.R` | any |
| link | `R/lnk_barrier_overrides.R` | observations |
| link | `R/lnk_barriers_unify.R` | dams, gradient |
| link | `R/lnk_baseline_current.R` | none |
| link | `R/lnk_catalog.R` | none |
| link | `R/lnk_compare_mapping_code.R` | none |
| link | `R/lnk_compare_rollup.R` | none |
| link | `R/lnk_config.R` | any |
| link | `R/lnk_crossings_union.R` | crossings |
| link | `R/lnk_csv_sync.R` | none |
| link | `R/lnk_db_conn.R` | any |
| link | `R/lnk_db_load.R` | none |
| link | `R/lnk_downstream.R` | none |
| link | `R/lnk_export_groups.R` | none |
| link | `R/lnk_export_inputs.R` | none |
| link | `R/lnk_gradient_parent.R` | any |
| link | `R/lnk_habitat_validate.R` | none |
| link | `R/lnk_load_overrides.R` | any |
| link | `R/lnk_load.R` | none |
| link | `R/lnk_log.R` | any |
| link | `R/lnk_observation_records.R` | gradient, obs_upstream, observations, segments |
| link | `R/lnk_persist_init.R` | segments |
| link | `R/lnk_pipeline_access.R` | obs_upstream, segments |
| link | `R/lnk_pipeline_break.R` | observations, segments |
| link | `R/lnk_pipeline_load.R` | crossings |
| link | `R/lnk_pipeline_mapping_code.R` | segments |
| link | `R/lnk_pipeline_persist.R` | segments |
| link | `R/lnk_pipeline_prepare.R` | dams, gradient, obs_upstream, observations, segments |
| link | `R/lnk_pipeline_pscis_build.R` | crossings |
| link | `R/lnk_pipeline_run.R` | any |
| link | `R/lnk_preflight_fresh.R` | none |
| link | `R/lnk_preflight_vintage.R` | none |
| link | `R/lnk_presence_check.R` | none |
| link | `R/lnk_presence_measures.R` | none |
| link | `R/lnk_presence.R` | any |
| link | `R/lnk_publish.R` | none |
| link | `R/lnk_rules_build.R` | none |
| link | `R/lnk_scenario_export.R` | none |
| link | `R/lnk_source.R` | none |
| link | `R/lnk_species_pooling.R` | any, gradient, obs_upstream, observations, segments |
| link | `R/lnk_stall.R` | any |
| link | `R/lnk_stamp.R` | any |
| link | `R/lnk_streams_parent.R` | none |
| link | `R/lnk_thresholds.R` | none |
| link | `R/lnk_vocabulary.R` | any |
| link | `R/lnk_wsg_deps.R` | none |
| link | `R/lnk_wsg_downstream_check.R` | dams |
| link | `R/lnk_wsg_resolve.R` | dams |
| link | `R/utils.R` | any |

**Changed and unexercised by the gate** (on the run's path, not on the modelled one):

- `link data-raw/schema_consolidate.R`
- `link data-raw/study_area_run.sh`
- `link data-raw/wsg_recompute_one.R`
- `link R/lnk_access.R`

## Inputs

### crossings (`data-raw/pretest/crossings.sql`)

Top five among groups the config models: BULK 1,780; HORS 1,156; MCGR 1,081; ELKR 792; PARS 773.

### dams (`data-raw/pretest/dams.sql`)

Top five among groups the config models: OKAN 233; SAJR 109; VICT 106; STHM 95; MFRA 75.

### gradient (`data-raw/pretest/gradient.sql`)

Top five among groups the config models: SETN 41,783; TOAD 32,051; OWIK 28,138; FINL 20,536; TOBA 20,354.

### near_river_conn (`data-raw/pretest/near_river_conn.sql`)

Top five among groups the config models: QUES 63,347; TAKL 32,346; CHIR 25,003; PCEA 19,000; LEUT 15,448.

### obs_upstream (`data-raw/pretest/obs_upstream.sql`)

Top five among groups the config models: LFRA 126,143; HARR 102,474; FRCN 87,488; LARL 58,912; SETN 43,683.

### observations (`data-raw/pretest/observations.sql`)

Top five among groups the config models: LFRA 29,180; UPCE 18,022; OKAN 15,352; LARL 12,180; SQAM 10,849.

### segments (`data-raw/pretest/segments.sql`)

Top five among groups the config models: SETN 66,083; TOAD 60,416; LIAR 53,476; OWIK 49,093; MORK 43,086.

## Picks

| group | inputs | last minutes (here) | measured on | from | bound (min) | statement bound (min) |
|---|---|---|---|---|---|---|
| QUES | near_river_conn | 18.8 | cypher-job3 | log | 56.3 | 30 |
| BULK | crossings | 6.6 | cypher-job1 | log | 19.9 | 20 |
| SETN | gradient,segments | 6.3 | m1 | log | 19.0 | 20 |
| LFRA | obs_upstream,observations | 6.2 | cypher-job1 | log | 18.6 | 19 |
| TOAD | gradient,segments | 3.5 | m1 | log | 10.4 | 11 |
| OKAN | dams | 3.1 | cypher-job2 | log | 9.2 | 10 |
| HARR | obs_upstream | 2.8 | m4 | log | 8.5 | 9 |
| TAKL | near_river_conn | 2.8 | cypher-job3 | log | 8.4 | 9 |
| UPCE | observations | 2.2 | cypher-job1 | log | 6.7 | 7 |
| HORS | crossings | 1.5 | m4 | log | 5.0 | 5 |
| SAJR | dams | 1.2 | cypher-job1 | log | 5.0 | 5 |

Estimated modelling: 55.1 min (sum of last minutes).

