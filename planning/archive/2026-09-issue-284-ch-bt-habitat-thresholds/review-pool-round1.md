# Review — BT+DV pooling, round 1

Scope: `diff_pool_r1.patch` on branch `284-research-calibrate-ch-and-bt-gradient-an`
(working tree over `60ca574`). Recomputed from the committed CSVs in
`data-raw/logs/habitat_thresholds_284/` (`obs_segments.csv` re-derived with the script's
own set definitions, including `distinct(loc)` for `BT_any_dv`). No repo file edited
except this one.

## Findings

- **[medium] research/habitat_thresholds.md:51-53, 75-79, 265-269 — the pooled
  pre-change and window value, 0.1449, is missing, so two statements are now false.**
  Recomputed from `obs_segments.csv` on the first run's basis (all observations on
  stream edges or river polygons, not accessible-only): BT-only P95 is 0.1311, which
  reproduces the doc's "0.131 → 0.125" and so confirms the method. Pooled BT+DV on the
  same basis is **0.1402 (n 4,802), which snaps to 0.1449**. Under the primary evidence,
  Change 1 therefore moved 0.1449 → 0.1349. Lines 75-77 instead say pooling "brought it
  back to 0.1349", which reads as though Change 1 had no net effect on the primary set.
  Two claims follow from that:
  - Line 79 says "the pre-change values are what #283 scoring should test". Scoring
    question 1 (line 266) now lists only BT-only 0.1249 and pooled 0.1349. The primary
    set's pre-change value, 0.1449, is not listed. Before pooling, the list carried BT
    0.1349 as the pre-change value; that slot was dropped instead of being moved up.
  - Lines 51-53 say the window values "are why the scoring questions below keep the
    higher candidates in play". The pooled window P95 is 0.149 (`quantiles.csv`,
    `BT_any_dv` `gradient_w100` p95 0.14919), which also snaps to **0.1449**. No higher
    BT candidate is in play any more, so the sentence is false for BT.

  Fix: state 0.1449 as the pooled pre-Change-1 value (and the window value), and add
  it to scoring question 1 beside 0.1249 and 0.1349.
- **[medium] research/habitat_thresholds.md:175-176 — "The records spread almost evenly
  from 0 to 25 %" is false.** Of the 76 DV spawning records in the gradient subset, 46
  (61 %) sit at ≤ 5 %, the median is 0.031, and the rest fall away: 17 at 5–10 %, 7 at
  10–15 %, 2 at 15–20 % and 4 at 20–25 % (from `selection.csv` `BT_spawn_dv` and
  `obs_segments.csv`). "14 in the flattest bin and 4 above 20 %" is correct. The P95
  comes from a thin tail, not from an even spread, and this sentence is the stated
  basis for dismissing the rule's 0.1949.
- **[low] research/habitat_thresholds.md:151-152 and 173 — "76 spawning and 991 rearing
  on accessible segments" has the wrong qualifier.** 82 DV spawning and 1,042 DV rearing
  locations are on accessible segments. 76 and 991 are the subset that is accessible
  *and* on a stream edge or river polygon with a gradient (the quantile n). Line 173,
  "The 76 DV spawning records", has the same problem. There are 82 in all. Line 150's
  "MORR 23, ZYMO 14, BULK 12" counts all 82, while on the 76 basis MORR is 20, so two
  adjacent sentences use different populations.
- **[low] research/habitat_thresholds.md:32-34 — "Two changes were made to it
  afterwards; both are listed at the end of this section."** The section now lists
  three (Change 3, pooling, is new).
- **[low] research/habitat_thresholds.md:21-23 — "either vetoed by the literature or
  backed only by evidence too weak to act on."** The only rows that ever sat in the
  "too weak" branch were BT spawning gradient and width. With the DV cap lifted, both
  are now literature vetoes (lines 173-186, confidence medium). No row is in the second
  disjunct any more. The sentence still describes the capped framing.
- **[low] data-raw/logs/habitat_thresholds_284/README.md:40-44 (last bullet) — stale on
  two counts.**
  - "the bridge row uses all BT observations" should now say there are two bridge rows,
    the primary one over pooled BT+DV (5,104) and the comparison over BT only (2,560).
  - It calls `candidates.csv` "the decision rule in the PWF … applied mechanically" and
    names the accessible-only restriction as the one departure. There are now two more:
    the inverted keep clause is removed, and the primary BT set is pooled where the
    PWF's `task_plan.md:53` makes DV "sensitivity-only". The script header comment
    (`query_habitat_thresholds_obs.R:23`, "the decision rule in task_plan.md, applied
    mechanically") has the same gap. The research doc does document both changes
    (Change 2, Change 3); these two pointers do not.
- **[low] planning/archive/2026-09-issue-284-ch-bt-habitat-thresholds/README.md:23-27
  (`## Measurement`) — the headline numbers are BT-only and are not labelled as such.**
  "BT rearing P95 0.125 (n 2,443)" and "bridge loss 1.2 % of BT observations" are
  presented as the measurement. The addendum gives 0.135 / n 4,764 but not the pooled
  bridge share (1.7 %, 85 of 5,104). Label these rows as BT-only, or add the pooled
  values beside them.
- **[note] draft_knowledge_issue.md:5 (unfiled draft, pending approval)** — "BT stage
  stays inferred from DV records, which mix two chars." This is not the
  capped/low-confidence wording. It does frame DV as a contaminant, which Change 3 no
  longer does. Worth a glance before filing.

Historical text, correctly left alone: `task_plan.md:53,57` (DV sensitivity-only, the
plan as written), `README.md:30-32` (the wrong-turn record, 0.1349 → 0.1249 on BT-only),
`findings.md`, `progress.md`, `review-round*.md`.

## (a) Every BT/DV numeric claim in research/habitat_thresholds.md, recomputed

| Line | Claim | Source / recompute | Verdict |
|---|---|---|---|
| 15 | BT rear_gradient_max 0.1049 → 0.1349 | candidates.csv BT_any_dv rule_value 0.1349; bundle CSV 0.1349 | ✓ |
| 40 | BT 2,560 locations | ledger step 7 BT 2560 | ✓ |
| 40 | 2,822 DV | ledger step 7 DV 2822 | ✓ |
| 41 | 5,104 BT+DV once shared counted once | 2560 + 2822 − 278 shared = 5104; candidates n 5104; bridge sum 5104 | ✓ |
| 44 | BT+DV 4,764 (gradient subset) | quantiles BT_any_dv gradient n 4764 | ✓ |
| 44 | BT alone 2,443 | quantiles BT_any gradient n 2443 | ✓ |
| 51 | Pooled 0.135 vs window 0.149, 1.4 points | p95 0.134825 vs 0.149188 → 1.44 pts | ✓ (but see finding 1) |
| 53 | window values keep higher candidates in play | pooled window snaps 0.1449; not in scoring list | ✗ |
| 75 | BT-only P95 0.131 → 0.125 | all-seg 0.13112 (n 2457) → acc 0.12533 | ✓ |
| 76 | 0.1349 → 0.1249 (BT-only) | snap49(0.1311)=0.1349; snap49(0.1253)=0.1249 | ✓ |
| 76-77 | pooling "brought it back to 0.1349" | pooled pre-change 0.1402 → 0.1449, not 0.1349 | misleading (finding 1) |
| 83 | inverted clause only ever fired for BT spawning gradient | ratio_first_bin_above_current ≥ 1 only on BT_spawn_dv (1.324); BT_any_dv 0.723, BT_any 0.595, CH 0.458/0.513 | ✓ |
| 90 | pooling moved 0.1249 → 0.1349 | candidates.csv | ✓ |
| 149 | DV in 140 of 158 BT WSGs | wsg_species_presence: bt 158, bt&dv 140 | ✓ |
| 150 | DV spawning MORR 23, ZYMO 14, BULK 12 | all 82 DV spawning locs: 23/14/12 (gradient subset: 20/14/12) | ✓ on all-82 basis |
| 150 | DV mostly Skeena and interior | DV region 400: 1,929 of 2,822 | ✓ |
| 151 | 76 spawning, 991 rearing "on accessible segments" | accessible: 82 / 1,042; 76 / 991 = accessible and stream/river_poly | ✗ qualifier |
| 158 | pooled n 4,764, P95 0.135, rule 0.1349 | 0.134825 → 0.1349 | ✓ |
| 159 | BT-only n 2,443, P95 0.125, rule 0.1249 | ✓ | ✓ |
| 160 | DV rearing-staged n 991, P95 0.158 | 0.15765 | ✓ |
| 162 | pooled selection ~0.7 from 5–12 % | 0.716–0.755 | ✓ |
| 162 | 0.42 at 12–15 %, 0.26 at 15–20 % | 0.416, 0.265 | ✓ |
| 164 | DV rearing ≥ 1 up to 12 %; 1.37 at 10.5–12; 0.70 at 12–15 | ≥ 1 from 1 % to 12 % (bins below 1 % are 0.61/0.56/0.91); 1.366; 0.698 | ✓ (pre-existing, "from 1 %" implicit) |
| 168 | FISS presence n 15, P95 0.106 | fiss_presence BT present gradient n 15, p95 0.106 | ✓ |
| 173 | 76 DV spawning records | 82 records; 76 in gradient subset | ✗ minor |
| 174 | P95 0.196, rule 0.1949 | 0.196425 → 0.1949 | ✓ |
| 175 | "spread almost evenly from 0 to 25 %" | 46/76 ≤ 5 %, median 0.031 | ✗ |
| 175 | 14 in flattest bin, 4 above 20 % | 14; 4 + 0 | ✓ |
| 181 | DV spawning P5 1.2 m, n 53, rule 1.2 | 1.16 → 1.2, n 53 | ✓ |
| 190 | pooled P5 1.48 m (BT alone 1.91) | 1.48 (n 3035); 1.912 | ✓ |
| 190 | pooled selection ≥ 1 from 3 m | (2,3] 0.86; (3,4] 1.54 and every bin above ≥ 1 | ✓ |
| 191 | FISS presence P5 1.9 m, none below 1.5 | p05 1.9; share_below_rear_min 0 | ✓ |
| 195 | pooled P5 sits on current (1.5) | rule_value 1.5 = current | ✓ |
| 197 | DV spawning selection 2.2 in flattest bin | 2.220 | ✓ |
| 199 | 1.7 %, 85 of 5,104 | 85/5104 = 1.665 % | ✓ |
| 200 | BT alone 1.2 %, 31 of 2,560 | 31/2560 = 1.211 % | ✓ |
| 207 | newly admitted 10.5–13.5 % | 0.1049 → 0.1349 | ✓ |
| 222 | BT presence sites n 16 (width) | fiss_presence width n 16 | ✓ (unchanged) |
| 266 | scoring: test 0.1249 beside 0.1349 | omits pooled pre-change / window 0.1449 | ✗ (finding 1) |

## (b) Where the BT rear candidate or its evidence is stated

| Place | States | OK? |
|---|---|---|
| inst/.../default_tuned/parameters_habitat_thresholds.csv:2 | 0.1349 | ✓ |
| inst/.../default_tuned/config.yaml:7 | 0.1049 → 0.1349, pooled | ✓ |
| inst/.../default_tuned/README.md:14 | 0.1349 pooled; 0.1249 labelled BT-only | ✓ |
| tests/testthat/test-lnk_config.R:328 | tuned 0.1349 | ✓ |
| research/habitat_thresholds.md | 0.1349 primary; 0.1249 labelled comparison / historical | ✓ except findings 1, 4, 5 |
| data-raw/logs/.../README.md | pooled primary | ✓ except last bullet (finding 6) |
| data-raw/query_habitat_thresholds_obs.R:66-72, 229-230 | pooled primary | ✓ (header line 23, finding 6) |
| data-raw/logs/.../obs_ledger.csv | "(pooled with BT)" | ✓ |
| planning/archive/.../README.md:5, 44-52 | 0.1349 adopted, 0.1249 pre-pooling | ✓ |
| planning/archive/.../README.md:23-27 | 0.125 / 1.2 % unlabelled | finding 7 |
| planning/archive/.../task_plan.md:53,57 | DV sensitivity-only | historical plan, OK |
| research/README.md:31, NEWS.md, CLAUDE.md | no BT value stated | ✓ |

## (c) Population descriptions against the code

- `BT_any_dv = filter(use, species_code == "BT") |> distinct(loc, .keep_all = TRUE)`.
  `use` (o7) comes out of `group_by(obs_species, loc) |> slice(1) |> ungroup()`, so it
  is ordered BT-rows-then-DV. `distinct(loc)` therefore keeps the **BT** row at the 278
  shared locations (kept: BT 2,560 + DV 2,544 = 5,104). Dropping the DV row there loses
  its `is_spawn`/`is_rear`, but `BT_any_dv` is never used for stage, so nothing is
  affected. The descriptions ("5,104 … shared locations counted once", "BT and DV
  records at one location are one location there") match.
- `bridge_bt.csv`: each set's `share` has denominator `sum(n)` over that set's rows,
  which is all observations, accessible or not (5,104 / 2,560). `share_lost_to_clustering`
  in `candidates.csv` uses the same denominator. The doc's "85 of 5,104" / "31 of 2,560"
  matches.
- Keep-clause removal: the only row whose `rule_says` changed because of it is BT
  `spawn_gradient_max` (keep → change). That matches the doc.

## (d) Checksum and tests

- `digest::digest(file = "inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv", algo = "sha256")`
  = `8ee57893…e187ff463`, which equals `config.yaml:27`. ✓
- `NOT_CRAN=true Rscript -e 'devtools::test(filter="lnk_config")'` →
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 171 ]`. ✓
