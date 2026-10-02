<!-- DRAFT — not filed. For review; could instead be folded into #300's body. -->

# Title

Tune MAD (discharge) thresholds for BT, GR, KO and RB rather than leave them missing

# Body

**If done:** a `mad` watershed group keeps stream habitat for every modelled species, on
discharge windows set from evidence. **If never:** any group moved to `mad` loses all
stream spawning and rearing for BT, GR, KO and RB by construction. That is not a finding
about the fish. Only waterbody rules (wetlands, lakes, the 1050/1150 edges) keep them.

## Problem

`parameters_habitat_thresholds.csv` carries `spawn_mad_*` for CH, CM, CO, PK, SK, ST and
WCT, and `rear_mad_*` for CH, CO, ST and WCT only (`default`, `default_tuned` and
`bcfishpass` alike). The gap was inherited from bcfishpass `example_newgraph`. Under
the `mad` model, fresh writes `FALSE` in place of the size test for a species with no
range, as bcfishpass does. Since #299, `lnk_habitat_validate()` names a miss the missing
range alone explains `no_mad_threshold`. Misses from the same cause also read
`width_null` (no discharge on the line) or `fails_gradient_and_width` (gradient fails
too), so that label is a floor on the loss, not a count of it. On ADMS on `mad`, 27 BT
locations read it against spawning and 8 more read `fails_gradient_and_width`
(`data-raw/logs/habitat_validate_299/`). The operator's direction (2026-10-02,
#299 plan gate): tune and add the thresholds, rather than leave them missing in the long
run.

## Proposed Solution

- **Measure first.** Use #300's held-out, discharge-covered groups (Peace, Fraser,
  Columbia). Take the distribution of `mad_m3s` at BT / GR / KO / RB observation locations
  by stage (pooled DV per `species_pooling.csv`), alongside accessible availability. This
  is the #284 method with discharge in place of width.
- **Literature and FISS** for each species' discharge range, recorded in
  `research/habitat_thresholds.md` as one verdict per threshold.
- **Land the values in `default_tuned`** (a thin bundle) first, scored out-of-sample with
  `lnk_habitat_validate_band()`. `default` stays untouched until a score supports a move.
- **Score before/after with capture and cost** (`share_*`, `*_km`) and
  `lnk_habitat_validate_band()`, not with `no_mad_threshold`. Once a range exists, the
  label cannot fire, so its "after" is 0 whatever the value.

Depends on #299 and #300. Relates to #284, #286.
