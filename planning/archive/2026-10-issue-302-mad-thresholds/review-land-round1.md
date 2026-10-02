# Review — #302 landing diff, round 1

Scope: `diff_land1.patch` (RUNBOOK §7, default_tuned CSV/config/README, test-lnk_config.R,
research/habitat_thresholds.md MAD Verdict + Results). Read-only; DB queries read-only on
docker fwapg `score302_*`.

## Verified clean

- Landed CSV equals `walked_value_of_record` for every held-out ladder (BT 0.078/0.078,
  GR 0.96/0.97, RB 0.011/0.019) and KO = candidates.csv 0.57; every new `*_mad_max` 9999;
  values are P10 (P05 for RB spawn) floored to 2 s.f. from quantiles.csv.
- `config.yaml` checksum = sha256 of the CSV (247a7088…); shape_checksum unchanged and
  correct; `lnk_config_verify(lnk_config("default_tuned"))` reports no drift.
- The changed test block, evaluated alone against the tree, passes (3 expectations); its
  15-row expected frame matches `diff default/ default_tuned/` exactly.
- Results table (band km, found, expected, ratio, elevation-adjusted, decision): every
  number matches verdict.csv / elevation_adjusted.csv held-out rows. Build stamps (c2fed37,
  145.3 min, 20-WSG closure, 18 variants, LHAF preflight, floor of record expected) match.
- habitat_change table: held-out sums reproduce exactly (BT 12,991 / 8,679 / 10,712 /
  13,235; GR 4,705 / 825 / 2,348 / 5,022; RB 8,186 / 7,821 / 8,853 / 9,849, and the %s).
- Anchor `removed` unadjusted ratios 0.36 / 0.48 / 0.50 / 1.06 match bands_pooled.
- RUNBOOK fresh claims hold at the pinned fresh e3a37f0: `build_wb_pred()` returns
  `FALSE` only under cw with no size range, ANDs `size_sql(size_rear)` when a range
  exists, and is polygon membership under mad with none; `.frs_rule_to_sql()` applies
  `lake_ha_min` only, never `wetland_ha_min`.
- "Inert under cw" holds: under cw `size_col` is channel_width, and `frs_habitat()`'s
  legacy path intersects ranges with gradient/channel_width only.

## Findings

- **[claim]** research/habitat_thresholds.md, Results, "What the anchor costs" ("Adjusted
  for elevation, that is 0.86, 1.41, 1.11 and 1.67") and "Reading it" → "Two things point
  that way" ("The anchor's `removed` band is used at or near the core rate once elevation
  is adjusted. Much of what `mad` at P10 drops is used, small water included.") — the
  adjusted figures are not the same band adjusted. In `habitat_variants_score.R`
  (`band_case`, ~l.700) a segment is labelled by the FIRST threshold step whose flags
  differ, and the anchor's `removed` label only applies when no loosening rung restores
  it. So `elevation_adjusted.csv`'s "`<sp>_p10 removed`" class is the residual that even
  P02 never restores: BT rear 1,444 km of the 4,505 km in bands_pooled, BT spawn 791 of
  2,752, GR rear 794 of 3,893, RB rear 296 of 864. Decomposing (same core density):

  | ladder | whole removed band | residual (P02 never restores) unadj / adj | part P05/P02 restore |
  |---|---|---|---|
  | BT rear | 4,505 km, 240 obs, 0.36 | 1,444 km, 205 obs, 0.97 / 0.86 | 3,062 km, 35 obs, **0.08** |
  | BT spawn | 2,752, 225, 0.48 | 791, 205, 1.51 / 1.41 | 1,961, 20, **0.06** |
  | GR rear | 3,893, 158, 0.50 | 794, 68, 1.05 / 1.11 | 3,099, 90, **0.36** |
  | RB rear | 864, 123, 1.06 | 296, 91, 2.30 / 1.67 | 569, 32, **0.42** |

  The jump 0.36 → 0.86 is composition, not elevation (elevation adjustment actually
  *lowers* BT rear 0.97 → 0.86 and RB 2.30 → 1.67). The part of the dropped habitat that
  is small water by construction (what loosening restores) is used at 0.06–0.42 of core —
  the opposite of "much of what mad at P10 drops is used, small water included". The
  residual that *is* used is not simply small streams either: for BT rear (held-out,
  queried from `score302_*` + `fwa_stream_networks_discharge`) it is ~500 km on NULL-MAD
  lines (455 km inside waterbodies), ~800 km of streams below P02, ~140 km P02–P05 that
  some other predicate excludes. As written, this bullet is the main evidence offered for
  the sampling-density hypothesis and it does not support it.

- **[claim]** research/habitat_thresholds.md, Results, "Reading it" bullet 1: "elevation
  does not explain it (adjusted 0.12–0.57)". For GR it does cross the rule's own line:
  GR rear P10→P05 adjusts 0.46 → 0.57 and GR spawn 0.46 → 0.54, both ≥ 0.5, so an
  elevation-adjusted reading would *take* both GR steps. True for BT and RB (≤ 0.16),
  not for GR. Say so, since GR is also the species with the −82 % cost.

- **[claim]** RUNBOOK.md:716-719 ("At the landed values a `mad` group keeps less stream
  rearing than `cw` (held-out: BT −33 %, GR −82 %, RB −4 %)"); research Verdict paragraph
  ("At these values … −82 %"); Results table header "`mad` P10 (landed)"; "What it costs"
  bullet ("Landing P10 makes a `mad` group keep a third less BT rearing, and four-fifths
  less GR"). For BT and GR these rows are the rearing ladder, which held spawning at its
  P05 candidate (variants_302.csv `set`: BT spawn 0.027, GR 0.095), not the landed 0.078 /
  0.96. The landed combination was never built (the doc's own last-but-one bullet says
  so), and spawning at P10 alone costs rearing: `bt_spawn_mad_p10` (rear at P05) is
  10,215 km vs 10,712 at both-P05; `gr_spawn_mad_p10` is 1,558 vs 2,348. So −33 % / −82 %
  are lower bounds on the landed loss, not "the landed values". Only RB's −4 % is the
  landed pair (rb_rear_mad_p10 sets spawn 0.011). RUNBOOK and the Verdict sentence state
  it without the caveat; at minimum say "at least".

- **[claim]** research/habitat_thresholds.md, last Results bullet: "Clustering moved a
  little habitat the other way (BT rear 3.5 and 1.6 km against 2,037 and 2,523 km added)".
  3.5 and 1.6 are held-out + in-sample (3.22 + 0.23; 1.09 + 0.53, bands.csv), while 2,037
  and 2,523 are held-out only, and the section opens "The held-out WSGs are pooled
  throughout". Held-out figures are 3.2 and 1.1 km (bands_pooled.csv).

- **[claim]** research/habitat_thresholds.md, "What it costs": "P05 halves that loss." True
  for BT (−33 % → −18 %), not GR (−82 % → −50 %, a 39 % reduction).

- **[claim, minor]** research/habitat_thresholds.md, after the Results table: RB spawning
  P10→P05 "is taken under the expected floor of record … and kept under the found floor".
  The found-floor decision is `keep (n < 10)`, but its walk is "underpowered at
  rb_spawn_mad_p05 - its value lands unscored" with `walked_value` 0.011 — the same value.
  "Kept" reads as if the found floor would land P10 (0.05). Worth one clause: both floors
  land 0.011; they differ only in whether it is scored.

- **[claim, minor]** research/habitat_thresholds.md, KO bullet: "Documented spawning sits
  at MAD 0.28–0.40 (AMEC 2015)". literature.md l.92: Creek 661 spawning is at MAD
  **≤ 0.283** (mouth) and above 0.105, upper limit not stated. The range extends below
  0.28; "0.28–0.40" understates it (in the direction that strengthens "argues lower").

- **[claim, minor]** research/habitat_thresholds.md:19 (top Verdict, unchanged): "One value
  moves: BT rearing gradient loosens." The doc title now covers discharge and
  `default_tuned` now differs from `default` in 15 cells; scope the sentence to gradient
  and width, or point to the MAD section. Same for research/README.md:31 ("CH and BT
  gradient and channel-width thresholds"). config.yaml's "so a group put on the `mad`
  model keeps their stream habitat" also reads stronger than the evidence (it keeps part
  of it, −33 %/−82 % at best); the README wording is accurate.

- **[note, not this diff]** Method says calibration used the "46 WSGs persisted in
  `fresh_default` that carry discharge" (matches stamp.txt), while Scoring design says
  held-outs are "outside the 55 calibration WSGs" (power_windows.txt: "calibration: 55").
  One of the two counts is a different set; reconcile the wording.
