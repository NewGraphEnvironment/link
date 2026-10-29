# Pre-run gate (link#372)

- config `default` (chain: default), history in `fresh_default.log`
- link `1d00c04cc5b2..b0dd63eb85a1`; fresh `v0.42.0..v0.46.0`
- per input 2 groups; bound 3 x last minutes in `fresh_default.log`, floor 5 min; statement bound <= 30 min

## Changed files (31)

| repo | file | inputs |
|---|---|---|
| fresh | `R/frs_cluster.R` | segments |
| fresh | `R/frs_feature_index.R` | none |
| fresh | `R/frs_habitat_classify.R` | near_river_conn, segments |
| fresh | `R/frs_habitat.R` | segments |
| fresh | `R/frs_migration_trial.R` | none |
| fresh | `R/frs_network_features.R` | segments |
| fresh | `R/frs_network_segment.R` | none |
| fresh | `R/frs_order_child.R` | segments |
| fresh | `R/frs_params.R` | segments |
| fresh | `R/frs_point_snap.R` | none |
| fresh | `R/utils.R` | any |
| link | `data-raw/schema_consolidate.R` | unexercised |
| link | `data-raw/study_area_run.sh` | unexercised |
| link | `data-raw/wsg_recompute_one.R` | unexercised |
| link | `data-raw/wsg_run_one.R` | any |
| link | `DESCRIPTION` | none |
| link | `inst/extdata/configs/default/config.yaml` | any, dams, observations, segments |
| link | `inst/extdata/configs/dictionary_dimensions.csv` | none |
| link | `R/lnk_barriers_unify.R` | dams, gradient |
| link | `R/lnk_barriers_views.R` | segments |
| link | `R/lnk_config.R` | any |
| link | `R/lnk_habitat_validate.R` | none |
| link | `R/lnk_log.R` | any |
| link | `R/lnk_persist_init.R` | segments |
| link | `R/lnk_pipeline_break.R` | observations, segments |
| link | `R/lnk_pipeline_classify.R` | near_river_conn, segments |
| link | `R/lnk_pipeline_prepare.R` | dams, gradient, observations, segments |
| link | `R/lnk_preflight_fresh.R` | none |
| link | `R/lnk_rules_build.R` | none |
| link | `R/lnk_stamp.R` | any |
| link | `R/utils.R` | any |

**Changed and unexercised by the gate** (on the run's path, not on the modelled one):

- `link data-raw/schema_consolidate.R`
- `link data-raw/study_area_run.sh`
- `link data-raw/wsg_recompute_one.R`

## Inputs

### dams (`data-raw/pretest/dams.sql`)

Top five among groups with history: LKEL 1; PCEA 1.

### gradient (`data-raw/pretest/gradient.sql`)

Top five among groups with history: PCEA 17,997; PARS 11,723; FINA 8,736; LKEL 982.

### near_river_conn (`data-raw/pretest/near_river_conn.sql`)

Top five among groups with history: PCEA 19,000; FINA 12,131; PARS 3,018; LKEL 2,763.

### observations (`data-raw/pretest/observations.sql`)

Top five among groups with history: PARS 2,145; PCEA 825; LKEL 725; FINA 581.

### segments (`data-raw/pretest/segments.sql`)

Top five among groups with history: PARS 37,215; PCEA 31,774; FINA 23,833; LKEL 2,382.

## Picks

| group | inputs | last minutes | measured on | bound (min) | statement bound (min) |
|---|---|---|---|---|---|
| PARS | gradient,observations,segments | 4.2 | m4 | 12.7 | 13 |
| PCEA | dams,gradient,near_river_conn,observations,segments | 2.7 | m4 | 8.1 | 9 |
| FINA | near_river_conn | 2.7 | m4 | 8.1 | 9 |
| LKEL | dams | 1.4 | m4 | 5.0 | 5 |

Estimated modelling: 11.0 min (sum of last minutes).

