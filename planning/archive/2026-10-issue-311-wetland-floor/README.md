## Outcome

link now pins fresh v0.39.0 (floor 0.38.0). Two fresh changes reach link through the pin: a W rule's `wetland_ha_min` gates `rearing` (fresh#237), and the lake/wetland buckets are sized by polygon area alone (fresh#240). The operator decided that a declared `rear_wetland_ha_min` bounds both wetland rear rules. `lnk_rules_build()` therefore emits the 1050/1150 wetland-flow rule as `waterbody_type: W` + `wetland_ha_min` when the species declares a floor and the polygon rule is emitted.
- It is emitted **after** the polygon W rule. fresh takes the first W rule as the bucket rule and `requires_connected` anchor, and the first L/W rule for waterbody-connected spawning.
- `bcfishpass` is unchanged.

Lessons from the review:
- **The plan review earned its cost.** It caught the `rear_wetland_polygon = no` case, where the floored rule would have become the only W rule and flipped the bucket. It also showed that "≈0 sub-floor rearing" had to be restricted to 1050/1150 lines, because the stream rule admits mainlines in small wetlands by design.
- **The doc review earned its cost too.** Its defect class was claims written from intent and copied between documents, with scope words like "all", "exactly" and "locations" never checked against the data. Round 2 found instances inside round 1's fixes, so the loop ended on a grep enumeration, not on a quiet round.

## Measurement

One segmentation per WSG (ADMS, BULK, NATR, PARS), re-classified three ways:
- **A:** fresh 0.36.2 with the old rules;
- **B:** 0.39.0 with the old rules;
- **C:** 0.39.0 with the floored rules.

**A → B (fresh alone)** reproduces five of fresh's six published numbers exactly:
- NATR BT −40 segments / −2.124 km;
- PARS BT −60 / −3.128 km;
- BULK CO −2;
- NATR BT lake bucket 309.9 → 521.4 km and wetland bucket 683.9 → 1,287.3 km.

The sixth, sub-floor wetland-flow km, is 26.6 here against fresh's ~26.4 upper bound.

**B → C (the floor)** removes 198.8 km of rearing (2,078 segment-species):
- sub-floor wetland-flow rearing goes to 0;
- the rest is rearing that `cluster_rearing` disconnects (17.4 of BULK ST's 23.8 km).

It costs 3 of 2,265 observation species-locations. It moves the bcfishpass departure by at most 1.1 points.

**Wrong turns kept:**
- The first build's measure step crashed: `count(*)` arrives as integer64, which `data.frame()` would not recycle. A re-classify on the same schemas recovered it.
- The first observation probe returned 0 everywhere, because bcfishobs `match_type` is full text. It was fixed with `left(match_type, 1)`.

Write-up: `research/habitat_thresholds.md`, "The wetland floor on `rearing` (#311)".

## Evidence

`data-raw/logs/wetland_floor_311/` (`measure.csv`, `summary.csv`, `obs_*.csv`, `stamp_*.txt`, README).

Closed by: PR for branch `311-wetland-ha-min-now-gates-rearing-in-fre` (commits `0ca706b`..`6be7ce2`)
