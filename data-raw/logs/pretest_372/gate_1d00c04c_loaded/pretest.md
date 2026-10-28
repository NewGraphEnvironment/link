# Pre-run gate (link#372)

- config `default` (chain: default), history in `fresh_default.log`
- link `1d00c04cc5b2..20d2bc4c7db2`; fresh `v0.42.0..v0.44.0`
- per input 2 groups; bound 3 x last minutes in `fresh_default.log`, floor 5 min; statement bound <= 30 min

## Changed files (23)

| repo | file | inputs |
|---|---|---|
| fresh | `R/frs_migration_trial.R` | none |
| fresh | `R/frs_order_child.R` | segments |
| fresh | `R/frs_params.R` | segments |
| fresh | `R/frs_point_snap.R` | none |
| link | `data-raw/schema_consolidate.R` | unexercised |
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
- `link data-raw/wsg_recompute_one.R`

## Inputs

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
| SETN | gradient,segments | 16.3 | m1 | 48.8 | 30 |
| QUES | near_river_conn | 9.3 | m1 | 28.0 | 29 |
| OKAN | dams | 7.6 | m1 | 22.7 | 23 |
| LFRA | observations | 6.6 | m1 | 19.8 | 20 |
| TOAD | gradient,segments | 6.0 | cypher-job2 | 18.0 | 18 |
| UPCE | observations | 3.7 | cypher-job1 | 11.2 | 12 |
| TAKL | near_river_conn | 3.2 | m1 | 9.5 | 10 |
| SAJR | dams | 1.6 | m1 | 5.0 | 5 |

Estimated modelling: 54.3 min (sum of last minutes).

## Verdict

| group | inputs | last minutes | bound | this run | exit | verdict |
|---|---|---|---|---|---|---|
| SETN | gradient,segments | 16.3 | 48.8 | 7.5 | 0 | pass |
| QUES | near_river_conn | 9.3 | 28.0 | 4.3 | 0 | pass |
| OKAN | dams | 7.6 | 22.7 | 2.7 | 0 | pass |
| LFRA | observations | 6.6 | 19.8 | 4.4 | 0 | pass |
| TOAD | gradient,segments | 6.0 | 18.0 | 4.1 | 0 | pass |
| UPCE | observations | 3.7 | 11.2 | 2.3 | 0 | pass |
| TAKL | near_river_conn | 3.2 | 9.5 |  | 124 | bound |
| SAJR | dams | 1.6 | 5.0 |  | 124 | bound |

**Gate: FAIL.** TAKL bound; SAJR bound.

