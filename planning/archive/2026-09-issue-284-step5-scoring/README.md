## Outcome

#284 step 5 scored the one moved threshold, BT `rear_gradient_max` 0.1349 in `default_tuned`, against fish observations on eight watershed groups held out from its calibration. It held. Two scripts do the work:
- `data-raw/habitat_variants_build.R` models a drainage closure once under `default` and re-classifies each threshold variant on that shared segmentation.
- `data-raw/habitat_variants_score.R` validates every variant schema and scores each ladder step with the new exported `lnk_habitat_validate_band()`: locations per km on the segments a step moves, against the core every step agrees on.

Along the way:
- The FISS absence taxa became data, with the #283 outputs reproduced byte for byte.
- A counts-only power check reshaped the design before any band was seen: BT only, a widened held-out set, CH dropped as unscorable.
- A discussion with the operator added the taper, an elevation split, an elevation-adjusted ratio and an expected-count floor. It also spun out knowledge#28: weights instead of cutoffs, biology first.

## Measurement

Held out, core 18.1 locations per 100 km.

| step | found | expected at the core rate | ratio | elevation-adjusted |
|---|---|---|---|---|
| to 0.1249 | 46 | 76 | 0.60 | 0.75 |
| to 0.1349 | 21 | 29 | 0.71 | 0.89 |
| to 0.1449 | 8 | 25 | 0.32 | 0.40 |

- 0.1349 holds under both the rule's floor and the expected-count floor, so `default_tuned` is unchanged.
- Capture rises from 81.2 % to 84.2 % for +585 km (+5.7 %) on the held-out WSGs. Across all 12 the change adds 1,105 km of BT rearing (+5.8 %, from 2 % in BABL to 9 % in KOTL and UARL; `habitat_change.csv`).
- The core tapers with gradient (18.6 / 19.8 / 15.6 / 11.8 per 100 km) and with elevation (24.6 / 19.3 / 10.2). The steep bands sit high, which is why the adjusted ratio exists.
- 67–74 % of each band is bridge-only rearing; 101 km of the first band lies outside its gradient window (connectivity-admitted).
- The build ran in 139.6 min (23 WSGs, 4 schemas).

**Wrong turns, kept on purpose:**
- The planned held-out set could decide one step in six (BT 10 / 1 / 0, CH 0 / 1 / 2 locations). The power check found it; the plan review flagged it.
- The first power probe used `DISTINCT ON` and moved staged counts by one between runs.
- The build's first access invariant could never pass. The BULL pre-flight hit it at run time; round 1 of the review had predicted it.
- The walk first treated an underpowered step as a refusal, then walked per row rather than per ladder.
- The nesting guard stopped the full score on 1.1 km of clustering noise.
- Code-check took five rounds and an enumeration. Rounds 3–5 each found a defect inside the previous fix; the mechanism was a partial producer read by a whole-population reader (`review-round*.md`, `review-enumeration.md`).

Durable verdict: [`research/habitat_thresholds.md`](../../../research/habitat_thresholds.md), "Step 5".

## Evidence

`data-raw/logs/habitat_score_284/*` (run `20260930_014921-53610765`; `power_windows.*` from before the build).

Closed by: PR (this branch) — closes #284
