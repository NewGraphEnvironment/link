# lake_connection_319 — rearing_km leaves lake connection lines out everywhere (#319)

Stamp: 2026-10-09T04:53Z · link 0.62.0 @ 6328567 (branch, uncommitted Phase 3 edits) · fresh 0.39.0 · local docker fwapg (localhost:5432), schema `fresh` (bcfishpass config) vs `fresh.streams_vw_bcfp`

| file | what |
|---|---|
| `parity_crosssection_before.txt` | `data-raw/parity_crosssection.R` (default WSGs FINA PARS PCEA LKEL) at main `1c61670` code: rearing counts lake connection lines on both sides |
| `parity_crosssection_after.txt` | the same after #319: both sides leave them out by `.lnk_sql_lake_connection()` |
| `vignette_accessible_only.R` | evaluates only the accessible-km block of `data-raw/wsg_vignette_data.R`, so `pars_accessible.rds` regenerates without rebuilding the gpkg or the mapping-code parity |

BT rearing km, link | bcfp (diff %):

| WSG | before | after | connection km (link / bcfp) |
|---|---|---|---|
| FINA | 2845.6 / 2858.5 (−0.45) | 2452.1 / 2464.9 (−0.52) | 393.6 / 393.6 |
| PARS | 2575.1 / 2588.9 (−0.53) | 2565.3 / 2579.2 (−0.54) | 9.8 / 9.8 |
| PCEA | 2023.5 / 2001.4 (+1.10) | 1655.8 / 1625.5 (+1.87) | 367.7 / 375.9 |
| LKEL | 222.8 / 221.1 (+0.75) | 211.3 / 209.7 (+0.79) | 11.5 / 11.5 |

Accessible and spawning rows are identical before and after; ST / CO / CH rearing on LKEL do not move.
Overall 25/25 PASS both times. PCEA's gap widens because link carries 8.2 km fewer connection
lines in BT rearing than bcfishpass there.

`pars_accessible.rds`: rearing 2575.06 / 2588.91 → 2565.31 / 2579.15. Spawning link km read
1683.38 in the July artifact and 1683.36 now, with no spawning code change: PARS `fresh` state
moved 0.02 km since then (input drift, not this change).

## Reproducibility (#284 and the later score schemas)

A full `habitat_variants_score.R` re-score of #284 cannot run at any HEAD after #307: the variant
bundles `extends: default` by name, `default`'s thresholds have changed, and the script stops
("the thresholds bundle for default is not the one every scored WSG ... was built from"). This
is the state on main, not a #319 effect. In that script `summary.csv`, `totals.csv` and
`habitat_change.csv` carry `rearing_km` (a re-score now also adds `rearing_lake_connection_km`
to `summary.csv`, so its shape changes even where values do not); `verdict.csv` and the band
files come from flags.

| file | what |
|---|---|
| `score_schemas_connection_km.R` / `.csv` | rearing on lake connection lines in every `score284_` / `score300_` / `score302_` / `score305_` schema |
| `habitat_change_284_check.R` | recomputes #284's `habitat_change.csv` km with the new default |

- **BT, CH, GR and RB: 0 km of rearing on connection lines in every score schema**, as #319
  predicted (they reared on lake lines only from #310). All 36 rows of #284's
  `habitat_change.csv` reproduce exactly (`identical()` on `rearing_km`, `rearing_km_base`,
  `spawning_km`).
- **SK and KO are not 0** (their L rule always admitted lake lines): KO KOTL ~307–310 km and PARS
  5.7 km, SK up to 641.8 km (BABL). Only #300 and #305 carry KO cost rows (in-sample, KO
  unscored): `lnk_rollup_wsg()` at this HEAD gives KOTL KO base `rearing_km` 259.06 km (was
  568.63) and `ko_mad` 254.67 km (was 561.54), so its change −7.09 km becomes −4.39 km. No verdict reads them. The committed files
  keep the meaning they were written with.
- MORR in `score284_bt_rear_0p*` had no planner statistics (estimated 1 row), so the rollup's
  polygon join ran for minutes; `ANALYZE` on the three tables of each score284 schema brought it
  to under a second. DB state, not code.
