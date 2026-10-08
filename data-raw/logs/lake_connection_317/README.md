# #317: lake connection lines reported apart from rearing km

Local docker fwapg (:5432), 2026-10-08. link 0.61.0 at `1161b59` (main plus the PWF baseline), fresh 0.39.0 (`e247ca1`). `stamp.txt` holds `lnk_stamp()`.

Nothing was re-classified. The rule is a rollup rule, so it is measured on #310's run-B snapshots (`zz310_snap.{adms,natr}_b`, the `default` bundle at `892a09f`, identical to v0.61.0's rules) on their own segmentation (`zz311_{adms,natr}.streams`).

**The rule.** A connection line is a line in a lake or reservoir polygon (`.lnk_sql_waterbody_class()` = `lake`) on edge type 1400 or 1450. It stays in fresh's `rearing` flag, where it joins inlet rearing to the lake for `cluster_rearing`. In the km:
- `rear_km` excludes connection lines;
- `rear_lake_km` is lake flow lines only;
- `rear_connection_km` holds the connection lines.

So `stream + lake + wetland = rear_km`, and `rear_km + connection = rear_flag_km` (the old total). The same rule is applied to the bcfishpass reference (`fresh.streams_vw_bcfp`, `rearing_<sp> IN (1, 2)`).

## Files

- `measure.R` → `measure.csv` (link), `reference.csv` (bcfishpass), `adams_lake.csv`. `parts_minus_total` is at most 0.001 km.
- `summarise.R` → `summary.csv`: old → new, and against bcfishpass under the same rule on both sides.

## Results (km)

| WSG | species | rearing old | rearing new | connection | lake old → new | vs bcfp old → new |
|---|---|---|---|---|---|---|
| ADMS | BT | 784.9 | 620.7 | 164.2 | 251.1 → 87.0 | +16.4 % → +2.0 % |
| ADMS | CH | 588.9 | 428.3 | 160.7 | 234.3 → 73.7 | +91.1 % → +38.9 % |
| ADMS | CO | 614.5 | 451.9 | 162.6 | 250.2 → 87.6 | +75.0 % → +28.7 % |
| ADMS | RB | 684.1 | 521.9 | 162.2 | 246.7 → 84.5 | — |
| ADMS | SK | 229.9 | 70.8 | 159.1 | 229.9 → 70.8 | 0.0 % → 0.0 % |
| NATR | BT | 3,985.5 | 3,709.5 | 275.9 | 508.6 → 232.6 | +29.8 % → +24.3 % |
| NATR | GR | 1,769.2 | 1,533.7 | 235.5 | 402.3 → 166.8 | — |
| NATR | KO | 345.4 | 132.4 | 213.0 | 345.4 → 132.4 | — |
| NATR | RB | 4,004.8 | 3,736.3 | 268.5 | 500.1 → 231.6 | — |

- **Nearly all of it is 1450.** 1400 is 0.9 km (NATR BT) and 1.4 km (NATR RB), and zero elsewhere.
- **Adams Lake:** 148.8 km of 1450 and 62.8 km of 1200 for every ADMS species that rears there. The 1450 leaves the km; the 1200 stays.
- **ADMS CH and CO stay well above bcfishpass** (+38.9 % / +28.7 %). bcfishpass has no CH or CO lake rearing at all on ADMS, so the remaining gap is lake flow lines, Adams's 62.8 km of 1200 among them. That is the #310 decision that lakes rear CH / CO, not a line-type artifact.
- **bcfishpass counts connection lines too.** Its BT rearing holds 65.9 km (ADMS) and 88.1 km (NATR) of 1450, and its SK rearing holds the same 159.1 km link does. Applying the rule to both sides keeps SK at 0.0 %. Applying it to link alone would have read SK as −69 %.
- **Spawning, the flags and the buckets do not move**: this is a reporting rule only.
