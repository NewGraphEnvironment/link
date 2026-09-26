# DRAFT — not filed. For NewGraphEnvironment/link (or fresh), pending approval.

**Title:** River-polygon segments with NULL channel width drop out of spawning and rearing

**If we do it:** mainstem reaches inside FWA river polygons are classified on gradient, as the `waterbody_type: R` rule intends. **If we never do:** every river-polygon segment that happens to carry no channel width is silently excluded from CH/BT (and every other species') spawning and rearing, even though the rule exists precisely to bypass width in river polygons.

## Problem

The default `rules.yaml` river-polygon rule sets `channel_width: [0.0, 9999.0]` to bypass the width test (`river_skip_cw_min` in `dimensions.csv`). fresh renders that as `channel_width BETWEEN 0 AND 9999` (`.frs_rule_to_sql`, fresh `R/utils.R`), and a NULL width fails a `BETWEEN`. So a river-polygon segment with NULL width fails the rule that was meant to ignore width.

Measured in link#284 (`data-raw/logs/habitat_thresholds_284/obs_segments.csv`, `fresh_default`):
- 55 retained CH/BT/DV observation locations sit on river-polygon segments with NULL width.
- All 55 have `spawning = FALSE` and `rearing = FALSE`, while accessible.
- They are concentrated in UPCE (11), TABR (10), LPCE (10) and MORR (6).

The segment count and length affected province-wide is not yet measured.

## Proposed Solution

The fix is fresh's. A rule with no `channel_width` key *inherits* the species width minimum (`dictionary_parameters_habitat_thresholds.csv`), so link cannot express "no width test" by omitting the key. fresh could either treat a `[0, 9999]` range as "no width test" and omit the predicate, or render it as `(channel_width BETWEEN 0 AND 9999 OR channel_width IS NULL)`.

Then measure the length of habitat it restores for `default` and `bcfishpass`. Check bcfishpass's own river-polygon handling first, because this may be a parity question as much as a defect.

Relates to #284
