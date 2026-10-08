# #311: fresh v0.39.0 pin and the floored wetland-flow rear rule

Local docker fwapg (:5432), 2026-10-07. The bundle is `default`. Four WSGs were built once into scratch working schemas `zz311_<wsg>`, then re-classified three ways on the **same segmentation**. Nothing was persisted to `fresh` / `fresh_default`.

| run | fresh | rules | link |
|---|---|---|---|
| A | 0.36.2 (`e3a37f0`) | old: carve-out unfloored | `664ec2d` (main + PWF) |
| B | 0.39.0 (`e247ca1`) | old | `664ec2d` |
| C | 0.39.0 (`e247ca1`) | new: carve-out floored (`0ca706b`) | `0ca706b` |

So A → B is fresh's movement on its own: fresh#240's area-only buckets plus fresh#237's floor on the polygon rule. B → C is the floored carve-out (#311).

**Environment**
- Segments: ADMS 39,422, BULK 87,638, NATR 47,300 and PARS 97,534; identical in every run.
- Source FWA lines: ADMS 11,520, BULK 32,472, NATR 29,298 and PARS 37,215.
- `bcfishobs.observations` holds 373,050 rows.
- `stamp_<run>.txt` holds the `lnk_stamp()` output. `measure.csv` records the link and fresh SHAs and `cfg_hash` on every row.

## Files

- `run.R`: build (`setup` .. `connect`) or re-classify (`classify` + `connect`). It measures `<schema>.streams_habitat`, appends to `measure.csv`, and snapshots the table to `zz311_snap.<wsg>_<run>`.
- `summarise.R` → `summary.csv`: A → B and B → C per WSG × species, plus the bcfishpass reference. The reference is rearing km from the local `fresh.streams_vw_bcfp` snapshot, `rearing_<sp> IN (1, 2)`.
- `obs.R` → `obs_AB.csv`, `obs_BC.csv`: observation species-locations on rearing, and on rearing that is lost or gained. A species-location is a distinct location per species, summed over species. It takes three of the validator's default filters (match-type class A/B, no source starting "Releases Database", BT pooled with DV), but not its observation exclusions or its per-metre de-duplication.

## Results

**A → B reproduces five of fresh's six published numbers exactly.** The sixth is the sub-floor wetland-flow km, which fresh gives as an upper bound. fresh's figures come from persisted `fresh_default`; these are from scratch builds, whose segmentation differs slightly (NATR BT: 10,657 rearing segments here under A).

| check | fresh published | here |
|---|---|---|
| NATR BT rearing | −40 segments, −2.1 km | −40, −2.124 km |
| PARS BT rearing | −60, −3.1 km | −60, −3.128 km |
| BULK CO rearing | −2 segments | −2 |
| NATR BT lake bucket | 309.9 → 521.4 km | 309.863 → 521.353 |
| NATR BT wetland bucket | 683.9 → 1,287.3 km | 683.899 → 1,287.263 |
| NATR BT wetland-flow rearing in wetlands < 1 ha | ~26.4 km (upper bound) | 26.605 km |

The A → B rearing loss is small everywhere: at most 75 segments / 3.6 km (PARS RB). No observation species-location on rearing is lost.

**B → C: the floored carve-out.**
- **Wetland-flow rearing in sub-floor wetlands goes to 0** for every floored species. Under A it was 26.6 km on NATR BT, 46.7 km on NATR RB, 19.1 km on PARS BT and 18.0 km on BULK RB.
- `rear_km_subfloor_C` > 0 (up to 0.6 km) is on 1000/1100 mainlines. The stream rule admits those by design.
- Rearing lost per WSG × species:

| WSG | species | segments | km | of which 1050/1150 | other edges (connectivity) |
|---|---|---|---|---|---|
| NATR | BT | −335 | −34.1 | 27.3 | 6.8 |
| NATR | RB | −565 | −46.7 | 46.7 | 0 |
| PARS | BT | −281 | −26.2 | 19.8 | 6.4 |
| PARS | RB | −367 | −28.0 | 28.0 | 0 |
| BULK | ST | −95 | −23.8 | 6.4 | 17.4 |
| BULK | RB | −217 | −18.0 | 18.0 | 0 |
| BULK | BT | −86 | −8.5 | 7.2 | 1.4 |
| BULK | CH | −52 | −7.9 | 3.7 | 4.2 |
| BULK | CO | −18 | −1.3 | 1.3 | 0 |
| ADMS | BT / CH / CO / RB | −22 / −13 / −3 / −24 | −1.5 / −0.9 / −0.1 / −1.7 | all | ~0 |

- **The "other edges" column is the rearing connectivity pass.** C changes only the rule for edges 1050/1150, so a segment on any other edge has the same predicate in B and C. When it flips, `cluster_rearing` has dropped it, because the sub-floor wetland link that connected it to spawning is gone.
- For the same reason, wetland-flow km lost can exceed the A sub-floor figure (NATR BT 27.3 against 26.6).
- No segment gains rearing.
- **Observations:** 3 species-locations stop rearing out of 2,265 on rearing in B (BULK BT 1, NATR RB 1, PARS BT 1). Every other species and WSG loses 0.

**Against bcfishpass** (rearing km, `summary.csv`, B → C): the floor moves the departure by at most 1.1 points. NATR BT goes from +13.8 % to +12.7 %, PARS BT from +1.7 % to +0.6 %, BULK ST from +13.8 % to +12.8 %, and ADMS BT from −21.2 % to −21.4 %. A → B moves it by at most 0.1. bcfishpass carries no RB rearing column.

## Caveats

- Sub-floor uses fresh's rule for which polygons count: a `waterbody_key` counts as meeting the floor when its largest polygon does.
- Province-wide, 40 edge-1050 lines (about 6.6 km) have no `waterbody_key`, and the floored rule drops them. None fall in these four WSGs.
- `lake_rear_ha` / `wetland_rear_ha` in `measure.csv` sum polygon area over every `waterbody_key` that carries a bucket line.
