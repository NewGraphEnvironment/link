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
