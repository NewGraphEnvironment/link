# Pre-run gate (link#372)

- config `default` (chain: default), history in `fresh_default.log`
- link `8fe1ba509041..ff12a85eb2cd`; fresh `v0.39.0..v0.42.0`
- per input 2 groups; bound 3 x last minutes in `fresh_default_20261017.log`, floor 5 min; statement bound <= 30 min

## Changed files (35)

| repo | file | inputs |
|---|---|---|
| fresh | `R/frs_break.R` | segments |
| fresh | `R/frs_candidates_pick.R` | crossings |
| fresh | `R/frs_feature_find.R` | none |
| fresh | `R/frs_habitat_classify.R` | near_river_conn, segments |
| fresh | `R/frs_habitat_predicates.R` | near_river_conn, segments |
| fresh | `R/frs_habitat.R` | segments |
| fresh | `R/frs_near_river.R` | near_river_conn |
| fresh | `R/frs_params.R` | segments |
| fresh | `R/frs_point_snap.R` | none |
| fresh | `R/frs_watershed_split.R` | none |
| fresh | `R/utils.R` | any |
| link | `DESCRIPTION` | none |
| link | `inst/extdata/configs/default/config.yaml` | any, dams, observations, segments |
| link | `inst/extdata/configs/default/dimensions.csv` | near_river_conn, segments |
| link | `inst/extdata/configs/default/parameters_habitat_thresholds.csv` | near_river_conn, segments |
| link | `inst/extdata/configs/default/rules.yaml` | near_river_conn, segments |
| link | `inst/extdata/configs/dictionary_dimensions.csv` | none |
| link | `inst/extdata/configs/dictionary_parameters_habitat_thresholds.csv` | none |
| link | `inst/extdata/parameters_habitat_rules.yaml` | none |
| link | `R/lnk_barrier_overrides.R` | observations |
| link | `R/lnk_barriers_unify.R` | dams, gradient |
| link | `R/lnk_config.R` | any |
| link | `R/lnk_discharge.R` | segments |
| link | `R/lnk_habitat_validate.R` | none |
| link | `R/lnk_log.R` | any |
| link | `R/lnk_match.R` | none |
| link | `R/lnk_persist_init.R` | segments |
| link | `R/lnk_pipeline_classify.R` | near_river_conn, segments |
| link | `R/lnk_pipeline_persist.R` | segments |
| link | `R/lnk_pipeline_prepare.R` | dams, gradient, observations, segments |
| link | `R/lnk_pipeline_pscis_build.R` | crossings |
| link | `R/lnk_points_snap.R` | crossings |
| link | `R/lnk_preflight_fresh.R` | none |
| link | `R/lnk_rules_build.R` | none |
| link | `R/lnk_wsg_downstream_check.R` | dams |

## Inputs

### crossings (`data-raw/pretest/crossings.sql`)

Top five among groups with history: BULK 1,780; HORS 1,156; MCGR 1,081; ELKR 792; PARS 773.

### dams (`data-raw/pretest/dams.sql`)

Top five among groups with history: OKAN 233; SAJR 109; VICT 106; STHM 95; MFRA 75.

### gradient (`data-raw/pretest/gradient.sql`)

Top five among groups with history: SETN 41,783; TOAD 32,051; OWIK 28,138; FINL 20,536; TOBA 20,354.

### near_river_conn (`data-raw/pretest/near_river_conn.sql`)

Top five among groups with history: QUES 63,347; TAKL 32,346; CHIR 25,003; PCEA 19,000; LEUT 15,448.

### observations (`data-raw/pretest/observations.sql`)

Top five among groups with history: LFRA 29,180; UPCE 18,022; OKAN 15,352; LARL 12,180; SQAM 10,849.

### segments (`data-raw/pretest/segments.sql`)

Top five among groups with history: SETN 66,083; TOAD 60,416; LIAR 53,476; OWIK 49,093; MORK 43,086.

## Picks

| group | inputs | last minutes | measured on | bound (min) | statement bound (min) |
|---|---|---|---|---|---|
| SETN | gradient,segments | 16.5 | m1 | 49.5 | 30 |
| BULK | crossings | 12.3 | cypher-job3 | 36.9 | 30 |
| LFRA | observations | 8.5 | m1 | 25.5 | 26 |
| TOAD | gradient,segments | 5.6 | cypher-job1 | 16.9 | 17 |
| QUES | near_river_conn | 4.9 | m1 | 14.8 | 15 |
| UPCE | observations | 3.6 | cypher-job2 | 10.9 | 11 |
| TAKL | near_river_conn | 3.0 | m1 | 9.0 | 9 |
| OKAN | dams | 2.8 | m1 | 8.5 | 9 |
| HORS | crossings | 2.4 | m1 | 7.3 | 8 |
| SAJR | dams | 1.3 | m1 | 5.0 | 5 |

Estimated modelling: 61.1 min (sum of last minutes).

