# #310: lake and wetland rearing connected to spawning, lake centrelines kept

Local docker fwapg (:5432), 2026-10-07. The bundle is `default`, fresh is 0.39.0 (`e247ca1`). #311's scratch builds `zz311_adms` and `zz311_natr` were re-classified twice (classify + connect) on the **same segmentation**. Nothing was persisted to `fresh` / `fresh_default`.

| run | rules | link |
|---|---|---|
| A | main: lake rule on 1000/1100, no connection, CO floored | `865bd04` (main) |
| B | #310: lake centrelines, `requires_connected: spawning` at 10 km on the first rear L / W rule, CO unfloored | `892a09f` |

ADMS has BT, CH, CO, RB and SK; NATR has BT, GR, KO and RB. Segments: ADMS 39,422, NATR 47,300, identical in both runs.

## Files

- `run.R`: re-classify a scratch schema, snapshot `streams_habitat` to `zz310_snap.<wsg>_<run>`, and append the run (SHAs, `cfg_hash`, dirty flag) to `runs.csv`. `stamp_<run>.txt` holds `lnk_stamp()`.
- `measure.R` → `measure.csv`: every run measured from its snapshot under one rule. A line's class is its polygon: lake = `fwa_lakes_poly` ∪ `fwa_manmade_waterbodies_poly`, wetland = `fwa_wetlands_poly`, anything else stream. The file also counts polygons where the bucket and the lines disagree, in both directions.
  - It then rolls the live schemas (run B) up through `.lnk_compare_wsg_rollup_link()` into `rollup_check.csv`. stream + lake + wetland − total is at most 0.01 km, which is the per-column rounding.
- `summarise.R` → `summary.csv`: A → B per WSG × species, plus the bcfishpass reference, rearing km from the local `fresh.streams_vw_bcfp` with `rearing_<sp> IN (1, 2)`.

## Results

**Spawning is unchanged** for every species: Δ 0.0 km. **SK and KO are row-identical** between A and B, on all 39,422 / 47,300 segments.

**Rearing rises by the lake centrelines** (km):

| WSG | species | A | B | Δ | of which lake | of which stream | vs bcfp A → B |
|---|---|---|---|---|---|---|---|
| ADMS | BT | 529.9 | 784.9 | +255.0 | +251.1 | +3.3 | −21.4 % → +16.4 % |
| ADMS | CH | 352.3 | 588.9 | +236.7 | +234.3 | +1.6 | +14.3 % → +91.1 % |
| ADMS | CO | 362.7 | 614.5 | +251.8 | +250.2 | +0.1 | +3.3 % → +75.0 % |
| ADMS | RB | 437.4 | 684.1 | +246.7 | +246.7 | 0 | — |
| NATR | BT | 3,460.0 | 3,985.5 | +525.4 | +508.6 | +10.5 | +12.7 % → +29.8 % |
| NATR | GR | 1,360.8 | 1,769.2 | +408.4 | +402.3 | +3.9 | — |
| NATR | RB | 3,504.7 | 4,004.8 | +500.1 | +500.1 | 0 | — |

- **Stream rearing rises a little too.** Lake lines join the rearing clusters of inlets and outlets, so stream rearing that `cluster_rearing` dropped before survives (BT NATR +10.5 km).
  - RB has `cluster_rearing = FALSE`, so its stream km do not move. For the same reason its lake km follow no spawning test.
- **One lake dominates ADMS.** Adams Lake (13,229 ha) holds 211.6 km of rearing lines, about 85 % of ADMS's lake km: 62.8 km of main-flow construction line (1200) and 148.8 km of connection lines (1450).
  - The 1450 lines join each tributary to the main flow across the lake. So lake km run at roughly three times the length of the lake's main flow line.
  - On NATR, BT's lake km are 275.0 km of 1450 and 227.6 km of 1200.
  - This is what puts ADMS CH and CO past +50 % against bcfishpass. The issue named 1450 among the lake edge types; whether connection lines belong in lake km is for review.

**The buckets move little**, as fresh's ladder predicted at 10 km:

| WSG | species | lake ha A → B | lakes A → B | wetland ha A → B | wetlands A → B |
|---|---|---|---|---|---|
| ADMS | BT | 14,274 → 14,274 | 16 → 16 | 1,256 → 1,253 | 127 → 126 |
| ADMS | CO | 14,127 → 14,159 | 22 → 74 | 1,106 → 1,105 | 106 → 111 |
| NATR | BT | 20,826 → 20,739 | 119 → 114 | 17,128 → 16,772 | 2,148 → 2,087 |
| NATR | RB | 20,175 → 20,088 | 110 → 105 | 16,719 → 16,363 | 2,046 → 1,985 |

(`summary.csv` has every species.)
- **CO gains 52 lakes under 2 ha (and loses none) and 6 wetlands under 0.5 ha** on ADMS, now that it has no floor. One wetland (3.24 ha) drops out for lack of connected spawning, so its wetland ha are flat.
- GR's and KO's lake ha are unchanged.

**The km / ha divergence after B** (polygons, run B):

| WSG | species | lake: ha, no km | lake: km, no ha | wetland: ha, no km | wetland: km, no ha |
|---|---|---|---|---|---|
| ADMS | BT | 2 | 0 | 28 | 1 |
| ADMS | CO | 9 | 0 | 26 | 1 |
| NATR | BT | 14 | 2 | 808 | 16 |
| NATR | GR | 3 | 0 | 0 | 160 |
| NATR | RB | 0 | 5 | 273 | 53 |

- For lakes it is rare: at most 14 polygons per species.
  - "ha, no km" is a connected lake whose lines `cluster_rearing` dropped.
  - "km, no ha" is a lake past 10 km whose lines still cluster with spawning upstream. For RB it is any lake at all, since RB has no rearing cluster pass.
- The wetland "ha, no km" counts have two causes, in different proportions per species:
  - **Admitted lines that `cluster_rearing` drops**, as for lakes. NATR BT: 515 of 808 polygons hold 1050/1150 wetland-flow lines and 12 more hold only 1000/1100.
  - **Wetlands whose lines are all construction lines (1200 / 1400)**, which no rear rule admits. That is the follow-up. NATR BT 281 of 808; ADMS BT 14 of 28 and CH 9 of 19; all of RB's (273 and 13), since RB has no cluster pass to drop admitted lines.
- GR has no wetland rearing (`rear_wetland = no`). Its 160 "km, no ha" are mainlines in wetlands that rear through the stream rule.
- The lake divergence is not common enough for its own issue here.
