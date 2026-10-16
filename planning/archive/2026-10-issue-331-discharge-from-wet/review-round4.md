# Code-check round 4: phase 5 diff (ce1d6071..HEAD, 33bc88fb)

## What was checked
- Every number in the new research section, the CLAUDE.md block and the default_tuned README, against data-raw/logs/habitat_score_331/verdict.csv, habitat_score_331_spawn_any/verdict.csv, habitat_score_331m/{model_verdict,habitat_change,model_reason,built}.csv and stamps, habitat_score_305/habitat_change.csv, and discharge_wet_331/{source_vs_coverage*.csv, mad_*/quantiles.csv, mad_*/coverage.csv, mad_*/stamp.txt, width_*/width_mad_conversion.csv, fill_reach_1250.csv, cw_unchanged_natr.csv}.
- Every Build A held-out row (bands, found, expected, ratio, decision), every Build B held-out row, the held-out habitat_change sums (-19.8 / -13.7 / -21.3 / -15.5 %, 13,881 -> 11,136 etc.), #305's -32 % and 13,526 km base, the 1.5-point gap, the fill reach (5 / 506 km), the width conversions, the source_vs_coverage table, the nine Skeena groups and their counts, the 47 common calibration groups, the build times and SHAs: all match.
- config.yaml checksum equals sha256 of the shipped thresholds CSV (4c225d10...).
- Ran test-lnk_config.R, test-lnk_discharge.R, test-lnk_pipeline_prepare.R in a git-archive copy with NOT_CRAN=true: 161 / 65 / 158 pass; the only failures (2) are the golden dams test, which CLAUDE.md documents (cabd.dams 8 -> 7). The new `.lnk_hv_discharge_src` expectation can fail (it would if the validator ignored the source, since default_tuned is now wet). cw_unchanged.R's guard can go red (it asserts mad_m3s differs, and `.lnk_discharge_join` NULLs the column before each re-join).

## Findings

- **[severity: claim]** research/habitat_thresholds.md:1162-1163 — "wet gives an annual value to 4.53 M lines against fwapg's 2.72 M". The 2.72 M is the number of rows in fwapg's discharge table, not the number of lines with a value. data-raw/logs/discharge_wet_331/mad_fwapg/stamp.txt reads "discharge rows: 2716652 (2003189 with mad_m3s)", and findings.md records 713 k NULL rows. So fwapg values 2.00 M lines. On wet's side, 29,491 of the 4.53 M picks are 0, which the bundle reads as no value (mad_wet/stamp.txt: 4,503,352 with mad_m3s). The sentence understates the coverage gap the section argues from. Should read about 4.50 M against 2.00 M, or say "rows".

- **[severity: claim]** research/habitat_thresholds.md:1176 (verdict table, BT `spawn_mad_min` 0.043, "How" column) — "any-stage P10 on wet; P10 → P05 refused on any-stage records". The step refused on any-stage records was the spawning-staged ladder, 0.012 → 0.0063. habitat_score_331_spawn_any/verdict.csv: the rungs are 0.012 / 0.0063 / 0.0019, and walked_value_of_record is 0.012. No spawning rung at 0.043, or at its P05 (0.020), was scored. The section's own text says so further down: "The any-stage value is unscored as a spawning rung". The row reads as if the landed value survived a scored refusal. Suggest: "operator: any-stage P10 on wet (unscored as a spawning rung; rearing scored the same value)".

- **[severity: claim]** inst/extdata/configs/default_tuned/README.md:17 and inst/extdata/configs/default_tuned/config.yaml:61-62.
  - The README says "BT's values were re-scored on it" and, a few sentences later, "The BT, GR and RB values were then scored on held-out groups by a rule fixed before the run, and they are what that rule walked to". config.yaml says "its BT MAD minima were scored on it".
  - For BT `spawn_mad_min` = 0.043 none of these holds. On wet, the rule walked to 0.0063 on spawning-staged records (underpowered: habitat_score_331/verdict.csv) and to 0.012 on any-stage records (habitat_score_331_spawn_any/verdict.csv). 0.043 is the operator's choice, unscored as a spawning value (research section, "The landed spawning value…").
  - The README's "The values were calibrated on fish observations in 46 groups" is also no longer true for BT. Its wet percentiles come from 56 calibration WSGs (53 with BT): discharge_wet_331/mad_wet/stamp.txt and coverage.csv.

- **[severity: claim]** research/habitat_thresholds.md:1250-1251 ("Reading it", first bullet) and inst/extdata/configs/default_tuned/README.md:17 say "what only `mad` keeps is used at or above it [the size-matched core rate]". That holds for rearing only.
  - habitat_score_331m/model_verdict.csv, held-out, stage any, `mad_only` spawning: ratio_size_adjusted 0.693 on wet and 0.716 on fwapg. Both are below the core. Rearing is 1.64 / 1.65.
  - The research bullet is unscoped and sits directly under the table that shows 0.69 / 0.72. The README sentence says "For BT", unscoped.
  - The "under a fifth" half holds for both flags (0.18 / 0.14 on wet). Scope the second half to rearing, or state spawning's 0.69.

- **[severity: claim]** CLAUDE.md:18 — "44 of 64 spawning-staged BT records are there". These are locations, not records. Summing `n_records` over the same 64 locations (discharge_wet_331/mad_wet/obs_mad.csv: BT, is_spawn, access 1/2, mad not NA) gives 67 Skeena records of 105.
  - Related, at research/habitat_thresholds.md:1168-1170: "wet gives 58 spawning-staged BT locations in the calibration groups (fwapg 17); 44 of the 64 accessible ones are Skeena". This reads as if the 64 were a superset of the 58 from wider groups. They are the same 53 groups.
  - The 64 adds 6 locations outside the tested `stream` / `river_poly` sets (`other`, `waterbody_rule`). The like-for-like Skeena share is 41 of 58 (mad_wet/quantiles.csv, BT spawn Skeena tested n = 41). The P10 of 0.013 holds on either set.

- **[severity: claim, minor]** research/habitat_thresholds.md:1255-1256 — "The rest of the band is below the minimum (3,091 km, 20 locations)." The `cw`-only wet rearing band is 3,109 km and 22 locations. Taking away `mad_null` (6 km, 1 location) leaves 3,103 km and 21 locations, of which 12 km and 1 location are `in_mad_range` (habitat_score_331m/model_reason.csv). The 3,091 km / 20 is only the `outside_mad_range` part, so "the rest" overstates it slightly.

No code bugs found in the diff. The thresholds CSV, checksum, variants file, test edits and the two evidence scripts are sound.
