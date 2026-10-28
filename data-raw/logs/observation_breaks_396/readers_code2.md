# Who reads `access_<sp>` = 2 against 1 (#396, question 4)

`access_<sp>` is 0 (blocked), 1 (accessible, species not observed upstream),
2 (accessible, observed upstream), -9 (species not present). Read 2026-10-28 at
link `d71fe2bf`.

## In this repo: nothing tells 2 from 1

| file:line | what it reads |
|---|---|
| `R/lnk_rollup_wsg.R:120` | `accessible_km` = `access IN (1, 2)` |
| `R/lnk_compare_rollup.R:232` | `access IN (1, 2)` |
| `R/lnk_habitat_validate.R:901`, `:1273` | `accessible` = `access IN (1, 2)`; `not_accessible` is its negation |
| `R/lnk_habitat_gate.R` | gates habitat where `access_<sp>` = 0 |
| `R/lnk_pipeline_mapping_code.R` | reads `has_barriers_<sp>_dnstr`, not `access_<sp>` |
| `R/lnk_scenario_export.R:158-206` | habitat flags and `access_gradient_max`, not `access_<sp>` |
| `R/lnk_access.R:224` | the recompute keeps a prior 2 where the segment stays accessible; it computes no new 2 (`observations = NULL`) |
| `data-raw/parity_crosssection.R:86`, `:203` | `access IN (1, 2)` |
| `data-raw/wsg_vignette_data.R:124` | `access IN (1, 2)` |
| `data-raw/query_habitat_thresholds_mad.R:295` | `access IN (1, 2)` |

No `.qml` or `.sld` file is in this repo.

## Beyond it

- **QGIS styles and project files read bcfishpass's text column, not link's integer.**
  `rfp/inst/extdata/styles/vector/streams_{all,bt,salmon,st}.qml` and
  `crossings_pscis_modelled_dams.qml` read `model_access_st`,
  `model_access_ch_co_sk` and `model_access_wct`; so do
  `rfp/inst/templates/bcrestoration_mobile.qgs` and the reporting repos'
  `restoration_wedzin_kwa_mapping.qgs`. None reads `access_<sp>`.
- **bcfishpass's `aw_linear_summary()`** (`db/schema.sql:5272`, local clone at
  `smnorris/bcfishpass@7f444f1b`, 2026-07-06) sums
  `access_<sp> = 2` km as `length_naturallyaccessible_obsrvd_<sp>`. It is the one
  reader found anywhere that tells 2 from 1. It runs on bcfishpass's own tables;
  link's `bcfishpass` config, the parity instrument, keeps every observation
  break, so nothing it compares moves.
- **`has_observation_key_upstr`** is computed (`R/lnk_pipeline_access.R:348`) and
  deliberately not persisted (`R/lnk_persist_init.R:89`).

## Latent: cutthroat aliases never set code 2 for CT

`.lnk_pipeline_break_obs_species()` lets `CCT`, `ACT` and `CT/RB` observations
through the presence filter when CT is present, but the code-2 test is exact
(`sp_upper %in% x`, `R/lnk_pipeline_access.R:363`), so an alias observation never
makes CT read 2. Under `top_per_species` each alias keeps its own top (decision 2),
so the reduced breaks change nothing here. Making the reader see the aliases is a
separate change to the access reader.
