# Review — BT+DV pooling, round 2

Scope: `diff_pool_r2.patch` (staged, over `60ca574`). Every number was recomputed from
`data-raw/logs/habitat_thresholds_284/*.csv`. `obs_segments.csv` was re-derived with the
script's own set definitions: `loc = species_code × blue_line_key × round(m)`, ordered
by `obs_species`, and `BT_any_dv = distinct(loc)` so the BT row is kept at the 278 shared
locations. That gives 2,560 BT + 2,544 DV = 5,104. The count of WSGs with BT and DV comes
from the `default` bundle's `wsg_species_presence.csv`. No repo file was edited except
this one.

## Findings

- **[low] research/habitat_thresholds.md:88-89 — "(`evidence_role = comparison`)"
  describes both files wrongly.** `bridge_bt.csv` has no `evidence_role` column. It
  marks the comparison rows by `set = BT_any`. In `candidates.csv` the value is
  `comparison: BT records only`, not `comparison`, so a filter on
  `evidence_role == "comparison"` returns nothing. The logs README gets this right
  ("marked by `evidence_role` / `set`"). No number is affected.
- **[low] research/habitat_thresholds.md:237-238 (Biases) — "BT use on NULL-width
  (order-1) segments is 0.08 of availability" is the BT-only figure, and it is not
  labelled as such.** From `selection.csv`, the NULL bin for `channel_width` is 0.084
  for `BT_any` and **0.122** for `BT_any_dv`, the primary set. Elsewhere the doc now
  labels every BT-only figure ("BT alone", "BT records only"). This one is still
  unlabelled. It is the same class as round-1 finding 7. It sets no threshold.
- **[note] data-raw/logs/habitat_thresholds_284/README.md:45-46 — the numerator is
  "only those on accessible segments".** The numerator of
  `share_lost_to_clustering` is narrower than that. It counts observations that are
  accessible, **pass the rear predicate, and have `rearing = FALSE`**: 85 of 5,104,
  and 31 of 2,560. Read literally, the sentence describes the accessible share, which
  is about 99 %. The research doc (lines 204-206) states the predicate correctly.

Every round-1 finding is fixed correctly, and none of the fixes adds a wrong number:

| Round-1 finding | Now | OK |
|---|---|---|
| pooled pre-change 0.1449 not stated | :50-51 window 0.149 → 0.1449; :76-77 0.140 → 0.135, 0.1449 → 0.1349; :271 Q1 lists 0.1449 and 0.1249 beside 0.1349 | ✓ |
| "spread almost evenly" | :177-181: 46 (61 %) ≤ 5 %, median 0.031, 17 / 7 / 6 | ✓ |
| DV counts labelled "accessible" | :153-155: 82 / 1,042 accessible, of which 76 / 991 are gradient-tested | ✓ |
| "Two changes" | :32 "Three changes" | ✓ |
| "too weak to act on" branch had no members | :21-22 "vetoed by the literature" | ✓ |
| logs README and script header stale | README :40-46, script :23-24 name all three changes and both bridge rows | ✓ (see note above) |
| archive README BT figures unlabelled | :24, :27 labelled BT-only, pooled beside | ✓ |
| draft issue frames DV as a contaminant | draft_knowledge_issue.md:5 reworded | ✓ |

## Every BT/DV numeric claim in research/habitat_thresholds.md

| Line | Claim | Recomputed | Match |
|---|---|---|---|
| 15 | BT rear_gradient_max 0.1049 → 0.1349 | default CSV 0.1049; tuned CSV 0.1349; candidates BT_any_dv 0.1349 | ✓ |
| 14, 16 | BT spawn gradient / width confidence medium | n 76 and 53 ≥ 30; literature veto | ✓ |
| 15 | rear gradient confidence high | n 4,764 ≥ 100; Isaak max 14.7 % > 13.49 % | ✓ |
| 39 | BT 2,560 locations | 2,560 | ✓ |
| 39 | 2,822 DV | 2,822 | ✓ |
| 40 | 5,104 BT+DV once shared are counted once | 2,560 + 2,822 − 278 = 5,104 | ✓ |
| 43 | BT+DV 4,764 (gradient) | 4,764 | ✓ |
| 43 | BT alone 2,443 | 2,443 | ✓ |
| 50 | pooled 0.135 vs window 0.149 | 0.134825 / 0.149188 | ✓ |
| 51 | window snaps to 0.1449, one step above the candidate | snap49(0.1492) = 0.1449 | ✓ |
| 57-58 | kept within 0.5 percentage points | `abs(cand - current) < 0.005` | ✓ |
| 61-62 | bridge raised if > 10 % | `sh > 0.10` | ✓ |
| 75-76 | BT-only P95 0.131 → 0.125, 0.1349 → 0.1249 | 0.13112 (n 2,457) → 0.12533; snaps 0.1349 → 0.1249 | ✓ |
| 76-77 | pooled P95 0.140 → 0.135, 0.1449 → 0.1349 | 0.1402 (n 4,802) → 0.134825; snaps 0.1449 → 0.1349 | ✓ |
| 83 | inverted clause fired only for BT spawning gradient | ratio_first_bin_above_current ≥ 1 only for BT_spawn_dv (1.324) | ✓ |
| 90 | pooling moved one value, 0.1249 → 0.1349 | rear width stays keep (1.9 → 1.5 rule, both keep); bridge stays keep | ✓ |
| 151 | DV in 140 of 158 BT WSGs | presence CSV: 158 BT, 140 BT&DV | ✓ |
| 152 | DV mostly Skeena and interior | region 400: 1,929 of 2,822 | ✓ |
| 152-153 | DV spawning mostly MORR, ZYMO, BULK | 23 / 14 / 12 of 82 | ✓ |
| 153-155 | 82 spawning and 1,042 rearing accessible; 76 and 991 gradient-tested | 82 / 1,042; 76 / 991 | ✓ |
| 161 | pooled n 4,764, P95 0.135, rule 0.1349 | ✓ | ✓ |
| 162 | BT-only n 2,443, P95 0.125, rule 0.1249 | ✓ | ✓ |
| 163 | DV rearing-staged n 991, P95 0.158 | 991, 0.15765 | ✓ |
| 165 | pooled selection ~0.7 at 5–12 % | 0.716–0.755 | ✓ |
| 165-166 | 0.42 at 12–15 %, 0.26 at 15–20 % | 0.416, 0.265 | ✓ |
| 167 | DV rear ≥ 1 up to 12 %; 1.37 at 10.5–12; 0.70 at 12–15 | ≥ 1 from 1–12 %; 1.366; 0.698 | ✓ |
| 171 | FISS presence n 15, P95 0.106 | 15, 0.106 | ✓ |
| 176-177 | 76 gradient-tested DV spawning, P95 0.196, rule 0.1949 | 76, 0.196425, 0.1949 | ✓ |
| 177-178 | 46 (61 %) ≤ 5 %, median 0.031 | 46 (60.5 %), 0.0314 | ✓ |
| 178-179 | 17 at 5–10, 7 at 10–15, 6 above 15 % | 17 / 7 / 6 | ✓ |
| 179 | the six sit on 15–25 % segments | 2 in (0.15, 0.2] and 4 in (0.2, 0.25]; max 0.221 | ✓ |
| 186 | DV spawning P5 1.2 m, n 53, rule 1.2 | 1.16 (n 53) → 1.2 | ✓ |
| 195 | pooled P5 1.48 m (BT alone 1.91) | 1.48 (n 3,035); 1.912 | ✓ |
| 195 | pooled selection ≥ 1 from 3 m | (2,3] 0.862; (3,4] 1.544 and every bin above ≥ 1 | ✓ |
| 196 | FISS presence P5 1.9 m, none below 1.5 | 1.9; share_below_rear_min 0 | ✓ |
| 200 | pooled P5 sits on the current value | round(1.48, 1) = 1.5 | ✓ |
| 202 | DV spawning selection 2.2 in flattest bin | 2.220 | ✓ |
| 204-205 | 1.7 %, 85 of 5,104; BT alone 1.2 %, 31 of 2,560 | 1.665 %; 1.211 % | ✓ |
| 212 | newly admitted 10.5–13.5 % | 0.1049 → 0.1349 | ✓ |
| 227-228 | BT presence n 16, median 5.5 m, 2.5 %; absent 1.46 m, 8 % | 5.53, 0.025; 1.458, 0.08 | ✓ |
| 238 | BT use on NULL width 0.08 of availability | BT_any 0.084; pooled 0.122 | ✓ BT-only, unlabelled (finding 2) |
| 242-243 | 99 % of BT observation segments accessible | BT 99.45 %; pooled 99.26 %; DV 99.11 % | ✓ |
| 252-253 | 55 retained observations on NULL-width river polygons, 31 in TABR/UPCE/LPCE | 55 (30 BT, 21 CH, 4 DV); 31 | ✓ |
| 271-272 | Q1 tests 0.1249 and 0.1449 beside 0.1349 | as computed above | ✓ |

## Current-state text against the four facts

The four facts: pooled BT+DV is primary; 0.1349 is adopted; DV is not capped; there
are three post-hoc changes.

| Place | Result |
|---|---|
| research/habitat_thresholds.md | consistent. The only remaining "low confidence" is at :88 and :91, and both say the cap was lifted |
| research/README.md:31 | no value stated ✓ |
| data-raw/logs/habitat_thresholds_284/README.md | pooled primary; three changes ✓ |
| query_habitat_thresholds_obs.R header :23-24, :66-73, :230-231 | pooled primary; three changes ✓. No leftover "sensitivity" or "cap" wording |
| obs_ledger.csv | "(pooled with BT)" ✓ |
| default_tuned/parameters_habitat_thresholds.csv | BT 0.1349 ✓; sha256 `8ee57893…e187ff463` = config.yaml:27 ✓ |
| default_tuned/config.yaml:7, README.md:14 | 0.1349 pooled, 0.1249 labelled BT-only ✓ |
| archive README :5, :24, :27, :44-52 | 0.1349 adopted, cap lifted ✓. :30-32 is the historical wrong-turn record, accepted |
| draft_knowledge_issue.md:5 | ✓ |

## Tests

`NOT_CRAN=true Rscript -e 'devtools::test(filter="lnk_config")'` →
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 171 ]`.
