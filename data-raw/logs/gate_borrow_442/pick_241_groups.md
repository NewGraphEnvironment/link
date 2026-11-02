# Pre-run gate (link#372)

- config `default_minimal` (chain: default_minimal < default), history in `fresh_default_history.log` under `default`, borrowed: it has no builds of its own
- link `1d00c04cc5b2..709e6d4b6ec6`; fresh `v0.42.0..v0.52.0`
- per input 2 groups; bound 3 x last minutes in `fresh_default_history.log`, floor 5 min; statement bound <= 30 min
- minutes excluded (bounded on the median): KTSU, OKAN

## Changed files (69)

| repo | file | inputs |
|---|---|---|
| fresh | `R/frs_cluster.R` | segments |
| fresh | `R/frs_feature_index.R` | none |
| fresh | `R/frs_habitat_classify.R` | near_river_conn, segments |
| fresh | `R/frs_habitat_overlay.R` | segments |
| fresh | `R/frs_habitat.R` | segments |
| fresh | `R/frs_lake_fetch.R` | none |
| fresh | `R/frs_migration_trial.R` | none |
| fresh | `R/frs_network_downstream.R` | none |
| fresh | `R/frs_network_features.R` | obs_upstream, segments |
| fresh | `R/frs_network_prune.R` | none |
| fresh | `R/frs_network_segment.R` | none |
| fresh | `R/frs_network_upstream.R` | none |
| fresh | `R/frs_network.R` | none |
| fresh | `R/frs_order_child.R` | segments |
| fresh | `R/frs_params.R` | segments |
| fresh | `R/frs_point_locate.R` | none |
| fresh | `R/frs_point_snap.R` | none |
| fresh | `R/frs_stream_fetch.R` | none |
| fresh | `R/frs_waterbody_network.R` | none |
| fresh | `R/frs_watershed_at_measure.R` | none |
| fresh | `R/frs_wetland_fetch.R` | none |
| fresh | `R/utils.R` | any |
| link | `data-raw/schema_consolidate.R` | unexercised |
| link | `data-raw/study_area_run.sh` | unexercised |
| link | `data-raw/wsg_recompute_one.R` | unexercised |
| link | `data-raw/wsg_run_one.R` | any |
| link | `DESCRIPTION` | none |
| link | `inst/extdata/configs/default_minimal/config.yaml` | any, dams, observations, segments |
| link | `inst/extdata/configs/default_minimal/README.md` | none |
| link | `inst/extdata/configs/default/config.yaml` | any, dams, observations, segments |
| link | `inst/extdata/configs/default/overrides/cabd_blkey_xref.csv` | dams |
| link | `inst/extdata/configs/default/overrides/cabd_passability_status_updates.csv` | dams |
| link | `inst/extdata/configs/default/overrides/user_modelled_crossing_fixes_20240825.csv` | crossings |
| link | `inst/extdata/configs/default/overrides/wcrp_watersheds.csv` | segments |
| link | `inst/extdata/configs/default/overrides/wsg_species_presence.csv` | segments |
| link | `inst/extdata/configs/default/README.md` | none |
| link | `inst/extdata/configs/default/species_modelled.csv` | gradient, segments |
| link | `inst/extdata/configs/default/wsg_species_presence_review.csv` | none |
| link | `inst/extdata/configs/dictionary_dimensions.csv` | none |
| link | `inst/extdata/configs/dictionary_species_modelled.csv` | none |
| link | `inst/extdata/configs/dictionary_wsg_species_presence_review.csv` | none |
| link | `inst/extdata/vocabulary.csv` | any |
| link | `R/lnk_access.R` | unexercised |
| link | `R/lnk_barriers_unify.R` | dams, gradient |
| link | `R/lnk_barriers_views.R` | segments |
| link | `R/lnk_config.R` | any |
| link | `R/lnk_csv_sync.R` | none |
| link | `R/lnk_habitat_validate.R` | none |
| link | `R/lnk_load_overrides.R` | any |
| link | `R/lnk_log.R` | any |
| link | `R/lnk_mapping_code.R` | segments |
| link | `R/lnk_overlay.R` | any |
| link | `R/lnk_persist_init.R` | segments |
| link | `R/lnk_pipeline_access.R` | obs_upstream, segments |
| link | `R/lnk_pipeline_break.R` | observations, segments |
| link | `R/lnk_pipeline_classify.R` | near_river_conn, segments |
| link | `R/lnk_pipeline_persist.R` | segments |
| link | `R/lnk_pipeline_prepare.R` | dams, gradient, observations, segments |
| link | `R/lnk_pipeline_run.R` | any |
| link | `R/lnk_pipeline_species.R` | any |
| link | `R/lnk_preflight_fresh.R` | none |
| link | `R/lnk_presence_check.R` | none |
| link | `R/lnk_presence_measures.R` | none |
| link | `R/lnk_rollup_wsg.R` | none |
| link | `R/lnk_rules_build.R` | none |
| link | `R/lnk_stamp.R` | any |
| link | `R/lnk_vocabulary.R` | any |
| link | `R/lnk_wsg_resolve.R` | dams |
| link | `R/utils.R` | any |

**Changed and unexercised by the gate** (on the run's path, not on the modelled one):

- `link data-raw/schema_consolidate.R`
- `link data-raw/study_area_run.sh`
- `link data-raw/wsg_recompute_one.R`
- `link R/lnk_access.R`

## Inputs

### crossings (`data-raw/pretest/crossings.sql`)

Top five among groups with history: BULK 1,780; HORS 1,156; MCGR 1,081; ELKR 792; PARS 773.

### dams (`data-raw/pretest/dams.sql`)

Top five among groups with history: OKAN 233; SAJR 109; VICT 106; STHM 95; MFRA 75.

### gradient (`data-raw/pretest/gradient.sql`)

Top five among groups with history: SETN 41,783; TOAD 32,051; OWIK 28,138; FINL 20,536; TOBA 20,354.

### near_river_conn (`data-raw/pretest/near_river_conn.sql`)

Top five among groups with history: QUES 63,347; TAKL 32,346; CHIR 25,003; PCEA 19,000; LEUT 15,448.

### obs_upstream (`data-raw/pretest/obs_upstream.sql`)

Top five among groups with history: LFRA 126,143; HARR 102,474; FRCN 87,488; LARL 58,912; SETN 43,683.

### observations (`data-raw/pretest/observations.sql`)

Top five among groups with history: LFRA 29,180; UPCE 18,022; OKAN 15,352; LARL 12,180; SQAM 10,849.

### segments (`data-raw/pretest/segments.sql`)

Top five among groups with history: SETN 66,083; TOAD 60,416; LIAR 53,476; OWIK 49,093; MORK 43,086.

## Picks

| group | inputs | last minutes | measured on | bound (min) | statement bound (min) |
|---|---|---|---|---|---|
| SETN | gradient,segments | 16.3 | m1 | 48.8 | 30 |
| BULK | crossings | 13.7 | cypher-job3 | 41.1 | 30 |
| QUES | near_river_conn | 9.3 | m1 | 28.0 | 29 |
| LFRA | obs_upstream,observations | 6.6 | m1 | 19.8 | 20 |
| TOAD | gradient,segments | 6.0 | cypher-job2 | 18.0 | 18 |
| HARR | obs_upstream | 5.7 | m1 | 17.2 | 18 |
| UPCE | observations | 3.7 | cypher-job1 | 11.2 | 12 |
| OKAN | dams | 3.7 | median | 11.2 | 12 |
| TAKL | near_river_conn | 3.2 | m1 | 9.5 | 10 |
| HORS | crossings | 2.6 | m1 | 7.7 | 8 |
| SAJR | dams | 1.6 | m1 | 5.0 | 5 |

Estimated modelling: 72.4 min (sum of last minutes).

