# Through-wetland lines and the near-river test (link#364)

Evidence for #364: the stream door for FWA 1050 / 1150 lines (`rear_wetland_flow = stream`) and the near-river pair (fresh 0.42.0). Built 2026-10-21 on local docker fwapg, the base at link `3e782f42` and the variants at `b26d406f` (the ANALYZE fix), fresh 0.42.0 (fresh PR #264). The bcfishpass reference is run 144, `smnorris/bcfishpass@620dbe43`.

## Producers

| file | what |
|---|---|
| `verify_phase3.R` → `verify_phase3_adms.txt` | A test bundle (CH stream door, pair model / 15 m / 3 m³/s / 1000 m) end to end on ADMS: persisted near-river rows, the logged pair, the validator, and the fill moving nothing under `default` |
| `../../query_mad_width_equivalent.R` → `mad_width_*` | The modelled width at which streams reach 3 m³/s, in `fresh_default` (fwapg discharge) |
| `../../habitat_variants_build.R`, `../../habitat_variants_score.R` → `score/` | The scoring build: `data-raw/habitat_score/variants_364.csv` on `wsg_roles_364.csv` |
| `summarise.R` → `wetland_flow.csv`, `floor.csv`, `stream_edges.csv`, `w_polygon.csv`, `measures.csv` | km tables from the scored schemas |
| `compare_co_bcfishpass.R` → `compare_co_bcfishpass*.csv/txt` | CO under the `bcfishpass` bundle, before and after the gradient test on its 1050/1150 rule |

## The width for 3 m³/s

The narrowest width bin (±0.1 m) holding at least 100 stream segments whose median fwapg discharge reaches 3 m³/s is **15 m**: n 600, median 3.29 m³/s. The 14 m bin has a median of 2.96. Above about 20 m, stream lines outside a polygon get rare, because large rivers are polygons, and their medians swing (19 m 3.63, 20 m 2.77). A rule that asked the median to stay above the target gave 44 m from that noise.

## Groups and roles

The groups are ADMS, BULK, CHWK, CLWR and SQAM; each has CH and CO present. Their drainage closure (14 groups, `score/closure.txt`) was modelled under `default`, and access was recomputed on the five; it did not change. All five are `held_out`. The pair's numbers came from province-wide work (#346) and the 15 m from `fresh_default` province-wide, so none of these groups chose them. 291 CH and 1,234 CO observation locations; CH rearing in the base is 3,442.2 km.

## Structure variants (CH rearing, observations of any stage)

| variant | added km | found / expected | removed km | found / expected | rearing km change | capture (of 291) |
|---|---|---|---|---|---|---|
| stream door, no pair | 3.3 | 0 / 0.2 | 43.1 | 0 / 3.1 | −39.8 (−1.2 %) | 260 |
| pair, scope `both` | 275.6 | 1 / 19.5 (ratio 0.05) | 31.2 | 0 / 2.2 | +244.3 (+7.1 %) | 261 |
| pair, scope `wetland_flow` | 4.3 | 0 / 0.3 | 31.2 | 0 / 2.2 | −27.0 (−0.8 %) | 260 |
| pair, scope `stream` | 274.4 | 1 / 19.4 | 43.1 | 0 / 3.1 | +231.3 (+6.7 %) | 261 |
| pair by discharge, 3 m³/s, filled | 61.4 | 0 / 4.3 | 38.9 | 0 / 2.8 | +22.5 (+0.7 %) | 260 |
| pair by order 5 | 290.9 | 2 / 20.5 (ratio 0.10) | 31.0 | 0 / 2.2 | +259.9 (+7.6 %) | 262 |

Base capture is 260 of 291. "Expected" is the band's km times the core's rate. Under #302's floor of record (`--floor=expected`), an added band with 10 or more expected and a ratio under 0.5 is refused. So the pair on ordinary stream edges (scope `both` or `stream`) would be refused: about 275 km added where CH are found at 5 % of the core's rate. Every other band is under 10 expected, so it decides nothing.

CO's door: rearing 3,893.4 → 3,825.5 km (−67.9, −1.7 %), capture unchanged at 992 of 1,234. CO's bands are not compared, because known CO rearing reaches (`user_habitat_classification`) in these groups would sit in the core.

## The ladders (CH rearing, `--floor=expected`)

| step | from → to | band km | found / expected | ratio | decision |
|---|---|---|---|---|---|
| width, D fixed at 1000 m | NA → 30 m (anchor) | 196.3 | 1 / 13.2 | 0.08 | taken by construction |
| | 30 → 20 m | 45.0 | 0 / 3.0 | 0 | keep (expected < 10) |
| | 20 → 15 m | 38.7 | 0 / 2.6 | 0 | keep |
| | 15 → 10 m | 53.1 | 0 / 3.6 | 0 | keep |
| distance, width fixed at 15 m | NA → 250 m (anchor) | 158.3 | 0 / 10.7 | 0 | taken by construction |
| | 250 → 500 m | 52.1 | 0 / 3.5 | 0 | keep |
| | 500 → 1000 m | 71.6 | 1 / 4.9 | 0.21 | keep |
| | 1000 → 2000 m | 87.1 | 1 / 5.9 | 0.17 | keep |

By #302's walk, an underpowered first step past an anchor lands its own value unscored: 20 m, and 500 m. The anchors' own bands are the stronger reading: adding the pair at all, at the tightest values tried, admits 158 to 196 km holding at most one location against 10 to 13 expected.

## What the door does to through-wetland lines (`wetland_flow.csv`)

| group | sp | free km | kept by size | kept by river only | dropped |
|---|---|---|---|---|---|
| ADMS | CH | 25.5 | 21.8 | 3.8 | 1.0 |
| BULK | CH | 184.6 | 153.5 | 5.5 | 27.6 |
| CHWK | CH | 2.5 | 2.1 | 0.6 | 0.3 |
| CLWR | CH | 20.2 | 19.1 | 1.0 | 0.6 |
| SQAM | CH | 5.9 | 3.4 | 2.1 | 0.6 |
| ADMS | CO | 28.1 | 22.8 | | 5.3 |
| BULK | CO | 227.8 | 176.6 | | 51.2 |
| CHWK | CO | 3.1 | 2.1 | | 0.9 |
| CLWR | CO | 24.7 | 21.4 | | 3.3 |
| SQAM | CO | 6.1 | 3.4 | | 2.7 |

On `cw` groups CH's size test is a channel width of 1.5 m, and most through-wetland lines pass it. The door keeps 83 to 95 % of CH's through-wetland rearing in four groups and 58 % on SQAM. The issue's province-wide measurement (10,197 → 2,338 km) was with CH's 0.75 m³/s flow floor, which is #346's `rear_mad_min`, not `default`'s width.

## Other km (`floor.csv`, `stream_edges.csv`, `w_polygon.csv`)

- **The #311 floor under `free`:** CH 1050 / 1150 lines that are accessible and not rearing, inside a wetland under 1 ha. ADMS 1.0, BULK 15.0, CHWK 0.5, CLWR 4.6 and SQAM 0.3 km.
- **The pair on ordinary stream edges** (scope `both` minus `wetland_flow`): ADMS 18.4, BULK 144.5, CHWK 42.8, CLWR 11.4 and SQAM 54.1 km of CH rearing.
- **The W polygon rule alone** (Decision 8): 1000 / 1100 inside a wetland of at least 1 ha, rearing under `default`, failing the stream test. CH: ADMS 16.2, BULK 142.0, CHWK 2.5, CLWR 15.2 and SQAM 9.1 km. CO: 17.1, 172.1, 2.5, 20.0 and 9.1 km.

## Which measure sees the rivers (`measures.csv`, main flow)

| group | edge | rows | fwapg discharge | channel width | stream order |
|---|---|---|---|---|---|
| ADMS | 1250 | 498 | 497 | 498 | 498 |
| BULK | 1250 | 1,411 | 0 | 1,411 | 1,411 |
| CHWK | 1250 | 445 | 445 | 424 | 445 |
| CLWR | 1250 | 772 | 472 | 772 | 772 |
| SQAM | 1250 | 2,854 | 0 | 2,854 | 2,854 |
| ADMS | 1200 | 1,261 | 1,256 | 512 | 1,261 |
| BULK | 1200 | 2,985 | 0 | 1,187 | 2,985 |
| SQAM | 1200 | 1,981 | 0 | 917 | 1,981 |

fwapg has no discharge in BULK or SQAM, so a discharge pair finds no river there without a fill. Width covers every river polygon except 21 CHWK rows. Most lake lines carry no width, so under width they rarely count as a river.

## CO under the `bcfishpass` bundle (`compare_co_bcfishpass.csv`)

| group | CO rearing km before | after | bcfishpass | 1050/1150 rearing km before / after |
|---|---|---|---|---|
| ADMS | 352.55 (+0.4 %) | 352.33 (+0.3 %) | 351.19 | 27.51 / 27.30 |
| BULK | 2,215.57 (−0.3 %) | 2,214.12 (−0.4 %) | 2,221.93 | 223.47 / 222.91 |

Spawning is unchanged (ADMS 312.30, BULK 1,782.09).

## Run notes

The first build attempt's variants slowed from 0.3 min a group in the pre-flight to 6 to 13 min. The habitat gate's count had been planned on statistics taken before the variant's rows were inserted; re-run by hand on fresh statistics, it takes 0.2 s. The harness now runs ANALYZE on the variant tables before the gate (`b26d406f`), and the variants step was re-run on the same base, with identical digests where it had already built. Variants step: 63.7 min.
