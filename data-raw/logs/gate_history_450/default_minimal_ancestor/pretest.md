# Pre-run gate (link#372)

- config `default_minimal` (chain: default_minimal < default), history in `fresh_default.log` under `default`, borrowed (found through extends): its own builds do not cover it
- link `4dfbfa4980eb..f05c30f40a04`; fresh `v0.52.0..v0.52.0`
- per input 2 groups; bound 3 x last minutes (`fresh_default.log`, or `data-raw/logs/build_minutes.csv` where newer, scaled to m1 at speed 1.31; 60 min where neither has the group), floor 5 min; statement bound <= 30 min

## Changed files (14)

| repo | file | inputs |
|---|---|---|
| link | `data-raw/schema_consolidate.R` | unexercised |
| link | `data-raw/study_area_run.sh` | unexercised |
| link | `DESCRIPTION` | none |
| link | `inst/extdata/vocabulary.csv` | any |
| link | `R/lnk_artifact.R` | any |
| link | `R/lnk_catalog.R` | none |
| link | `R/lnk_downstream.R` | none |
| link | `R/lnk_export_groups.R` | none |
| link | `R/lnk_export_inputs.R` | none |
| link | `R/lnk_log.R` | any |
| link | `R/lnk_scenario_export.R` | none |
| link | `R/lnk_stamp.R` | any |
| link | `R/lnk_streams_parent.R` | none |
| link | `R/lnk_wsg_deps.R` | none |

**Changed and unexercised by the gate** (on the run's path, not on the modelled one):

- `link data-raw/schema_consolidate.R`
- `link data-raw/study_area_run.sh`

## Inputs

## Picks

| group | inputs | last minutes (here) | measured on | from | bound (min) | statement bound (min) |
|---|---|---|---|---|---|---|
| GRNL | any | 0.5 | m1 | log | 5.0 | 5 |

Estimated modelling: 0.5 min (sum of last minutes).

