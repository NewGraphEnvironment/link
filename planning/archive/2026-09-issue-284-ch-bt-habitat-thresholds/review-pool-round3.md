# Review — BT+DV pooling, round 3 (final)

Scope: staged diff over `60ca574`. Every figure below was recomputed from
`data-raw/logs/habitat_thresholds_284/{candidates,bridge_bt,selection,quantiles,fiss_presence,fiss_width_error,obs_ledger}.csv`.
One extra probe: the FISS site CSVs in `~/Projects/repo/knowledge/data/<WSG>/`, to test
whether the FISS figures (which match `"Bull Trout"` only) would change under BT+DV pooling.
No repo file was edited except this one.

## Round-2 fixes (a)-(c)

| Fix | Checked against | OK |
|---|---|---|
| (a) research :89-90 names `evidence_role = "comparison: BT records only"` (candidates.csv) and `set = BT_any` (bridge_bt.csv) | candidates.csv has exactly that string on 3 rows; bridge_bt.csv has no `evidence_role` column and uses `set` = `BT_any` / `BT_any_dv` | ✓ |
| (b) research :238-239 NULL-width ratio 0.12 pooled, 0.08 BT alone | selection.csv `BT_any_dv,channel_width,NULL` 0.1218; `BT_any,channel_width,NULL` 0.0842 | ✓ |
| (c) logs README :45-47 bridge numerator = accessible, passes rear predicate, `rearing = FALSE`; denominator all of the set's observations | bridge_bt.csv `TRUE,FALSE,TRUE`: 85 / 5,104 = 0.01665 and 31 / 2,560 = 0.01211; equal to candidates.csv `share_lost_to_clustering` | ✓ |

## Findings

- **[low] research/habitat_thresholds.md:167 — "DV rearing records stay ≥ 1 up to 12 %"
  is false below 1 %.** `BT_rear_dv` gradient ratios are 0.61 at ≤ 0.25 %, 0.56 at
  0.25–0.5 %, 0.91 at 0.5–1 %, and ≥ 1 (1.005–1.406) only from 1 % to 12 %. Read literally
  the sentence says DV rearing is selected at every gradient up to 12 %. Suggest "≥ 1 from
  1 to 12 %". The set label (DV rearing-staged) is correct; no threshold depends on the
  flat end.
- **[note] research/habitat_thresholds.md:227-228 — "BT presence sites (n 16) … (median
  5.5 m, 2.5 %)".** n 16 is the width set; the 2.5 % gradient median is over 15 sites
  (fiss_presence.csv `present,gradient` n 15, which :171 states correctly). Same for the
  absent side: width n 257, gradient n 251. Numbers are right; the n covers only the
  width half.

No figure is computed on one BT set and stated as another. The mechanism that produced
round-1 finding 7 and round-2 finding 2 has no remaining instance.

## Step 2 — every BT figure in research/habitat_thresholds.md, by set

Sets: **pooled** = `BT_any_dv` (BT+DV); **BT-only** = `BT_any`; **DV-spawn** /
**DV-rear** = `BT_spawn_dv` / `BT_rear_dv`; **FISS** = knowledge FISS sites matched on
`"Bull Trout"` only; **param** = a config value, not evidence.

| Line | Figure | Set | Labelled in text | Value check |
|---|---|---|---|---|
| 14 | spawn_gradient_max keep, medium | DV-spawn (n 76) + literature veto | via :176 | ✓ |
| 15 | rear_gradient_max 0.1049 → 0.1349, high | pooled (n 4,764) | via :161 | ✓ |
| 16 | spawn_channel_width_min keep, medium | DV-spawn (n 53) | via :186 | ✓ |
| 17 | rear_channel_width_min keep, medium | pooled (n 3,035) | via :195 | ✓ |
| 18 | spawn_gradient_min keep, medium | DV-spawn (n 76) | via :202 | ✓ |
| 19 | cluster_bridge_gradient keep, medium | pooled (5,104) | via :204 | ✓ |
| 39 | BT 2,560 | BT-only | yes | ledger step 7 ✓ |
| 39 | 2,822 DV | DV (all) | yes | ✓ |
| 40 | 5,104 BT+DV | pooled | yes | 2,560 + 2,822 − 278 ✓ |
| 43 | BT+DV 4,764; BT alone 2,443 | pooled; BT-only | yes | quantiles.csv ✓ |
| 50 | 0.135 vs 0.149 | pooled (segment vs w100) | yes | 0.1348 / 0.1492 ✓ |
| 51 | window → 0.1449 | pooled | yes | ✓ |
| 61-62 | bridge raised if > 10 % of BT observations | rule text, applied to both sets | n/a (rule) | ✓ |
| 75-76 | P95 0.131 → 0.125, 0.1349 → 0.1249 | BT-only | yes | ✓ |
| 76-77 | P95 0.140 → 0.135, 0.1449 → 0.1349 | pooled | yes | ✓ |
| 83-84 | inverted clause fired only for BT spawning gradient | DV-spawn (ratio 1.324) | implicit (BT spawning = DV-spawn per :153) | ✓ |
| 90 | pooling moved one value 0.1249 → 0.1349 | BT-only → pooled | yes | ✓ |
| 151 | DV in 140 of 158 BT WSGs | presence table | yes | ✓ (round 2) |
| 152-153 | DV mostly Skeena/interior; spawning MORR, ZYMO, BULK | DV | yes | ✓ (round 2) |
| 153-155 | 82 / 1,042 accessible; 76 / 991 gradient-tested | DV-spawn / DV-rear | yes | ✓ |
| 161 | n 4,764, P95 0.135, 0.1349 | pooled | yes | ✓ |
| 162 | n 2,443, P95 0.125, 0.1249 | BT-only | yes | ✓ |
| 163 | n 991, P95 0.158 | DV-rear | yes | 0.1577 ✓ |
| 165-166 | ~0.7 at 5–12 %, 0.42 at 12–15, 0.26 at 15–20 | pooled | yes | 0.716–0.755, 0.416, 0.265 ✓ |
| 167 | ≥ 1 up to 12 %; 1.37 at 10.5–12; 0.70 at 12–15 | DV-rear | yes | 1.366, 0.698 ✓; "≥ 1 up to 12 %" false below 1 % (finding 1) |
| 169 | Isaak 14.7 % max | literature | n/a | > 13.49 ✓ |
| 171 | FISS presence n 15, P95 0.106 | FISS | yes ("FISS") | ✓ |
| 176-177 | 76 records, P95 0.196, rule 0.1949 | DV-spawn | yes | ✓ |
| 177-178 | 46 (61 %) ≤ 5 %, median 0.031 | DV-spawn | yes | bins 14+0+2+16+5+6+1+2 = 46 ✓; p50 0.0315 ✓ |
| 178-179 | 17 at 5–10, 7 at 10–15, 6 above 15 % | DV-spawn | yes | 17 / 7 / 6 ✓ |
| 179-180 | six on 15–25 % segments | DV-spawn | yes | 2 + 4 ✓ |
| 186 | P5 1.2 m, n 53 | DV-spawn | yes | 1.16 ✓ |
| 195 | pooled P5 1.48 m, BT alone 1.91 | pooled; BT-only | yes | ✓ |
| 195 | pooled selection ≥ 1 from 3 m | pooled | yes | (3,4] 1.544 and all above ✓ |
| 196 | FISS P5 1.9 m, none below 1.5 | FISS | yes | share_below_rear_min 0 ✓ |
| 200 | pooled P5 on current value | pooled | yes | ✓ |
| 202 | selection 2.2 in flattest bin | DV-spawn | yes | 2.220 ✓ |
| 204-205 | 1.7 %, 85 of 5,104; BT alone 1.2 %, 31 of 2,560 | pooled; BT-only | yes | ✓ |
| 212 | newly admitted 10.5–13.5 % | param (0.1049 → 0.1349) | n/a | ✓ |
| 222-224 | modelled width 0.97×, p10–p90 0.69–1.56, n 18 | FISS (all sites, not species) | yes | ✓ |
| 227-228 | presence n 16, median 5.5 m, 2.5 %; absent 1.46 m, 8 % | FISS | yes | values ✓; n 16 is width only, gradient n 15 (finding 2) |
| 238-239 | NULL-width ratio 0.12 pooled, 0.08 BT alone | pooled; BT-only | yes | ✓ |
| 243 | observation threshold BT 1 | param | n/a | ✓ |
| 243-244 | 99 % of BT observation segments accessible | unlabelled | **ambiguous** | BT-only 99.45 %, pooled 99.26 %, DV 99.11 % (round 2): every set rounds to 99 %, so not wrong |
| 253-254 | 55 retained observations on NULL-width river polygons | mixed CH/BT/DV (30 / 21 / 4) | stated as all retained observations | ✓ |
| 271-273 | Q1: 0.1249 BT-only, 0.1449 pooled pre-change / window, 0.1349 pooled | BT-only; pooled | yes | ✓ |

**FISS figures and pooling.** The FISS script matches `"Bull Trout"` only (`query_habitat_thresholds_fiss.R`, `bt = grepl("Bull Trout", …)`),
so FISS is a BT-name-only set that the doc does not label as such. A probe of the five
snapshots found 7 sites that caught Dolly Varden without Bull Trout (LNTH 3, UNTH 4) and
**none of them has a measured channel width**. The site-measured presence and absence
figures at :171, :196 and :227-228 are therefore the same under BT+DV pooling. Not a
finding.

## Tests

`NOT_CRAN=true Rscript -e 'devtools::test(filter="lnk_config")'` →
`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 171 ]`. The staged tuned CSV has the sha256
`8ee57893…e187ff463`, which matches config.yaml.
