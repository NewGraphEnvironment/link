## Outcome

In `default`, a species' `lake_rearing` / `wetland_rearing` bucket now keeps only polygons with same-species spawning on them or within 10 km. `lnk_rules_build()` stamps `requires_connected: spawning` on the first rear L / W rule, from the per-type `rear_*_connected_distance_max` columns; SK and KO are excepted and guarded.
- Lake and reservoir centrelines count in `rearing`: the L rule admits FWA construction lines with no width test.
- CO has no lake or wetland size floor.
- The rollups split rearing km by the polygon each line sits in (stream / lake / wetland), not by edge type, on the link and bcfp sides.

Learned:
- fresh's `lake_rearing` bucket reads `fwa_lakes_poly` only, while its rule compiler also reads reservoirs.
- `fwa_waterbodies` misses ~23,000 km of polygon lines.
- CT and DV get no rules (no thresholds row).
- fresh anchors waterbody-connected spawning on the first rear L *or* W rule. Three `/code-check` loops found the same mechanism over and over: one fact stated in two places with nothing tying them (builder vs fresh's lookup, dictionary vs builder, prose vs data, a test whose two sides came from one query). The verdict is in `research/habitat_thresholds.md`, "Lake and wetland rearing connected to spawning (#310)".

## Measurement

On one segmentation (#311's `zz311_adms` / `zz311_natr`, re-classified at main `865bd04` and at `892a09f`):
- Spawning is unchanged; SK / KO are row-identical.
- Rearing rises +237 to +255 km per species on ADMS and +408 to +525 km on NATR, almost all lake lines. Stream rearing rises up to +10.5 km (NATR BT), from lake lines joining clusters.
- Buckets move little: NATR BT wetland 17,128 → 16,772 ha; CO on ADMS gains 52 lakes under 2 ha.
- stream + lake + wetland equals rearing to 0.01 km.
- Adams Lake alone puts 211.6 km on ADMS CH / CO, 148.8 km of them 1450 connection lines. That takes CH to +91 % and CO to +75 % against bcfishpass, against +22 % / +15 % without the lake. Whether 1450 belongs in lake km is open for review.
- Wrong turns kept:
  - the first rollup draft classified lines through `fwa_waterbodies` (measured short by 23,507 km);
  - the first log README said the wetland "ha, no km" polygons were mostly construction-line wetlands. For BT and CH they are mostly lines `cluster_rearing` dropped.

## Evidence

`data-raw/logs/lake_connected_310/` (run.R, measure.R, summarise.R, CSVs, README); review rounds in this directory (`review-*.md`).

Closed by: PR for #310 (branch `310-default-lake-and-wetland-rearing-connec`)
