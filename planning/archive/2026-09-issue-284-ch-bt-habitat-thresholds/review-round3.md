# Code-check round 3 — #284 staged diff (2026-09-26)

Reviewer: round-3 subagent. Read-only. Every claim below was recomputed from the committed
CSVs in `data-raw/logs/habitat_thresholds_284/`, from `planning/active/literature.md`, or
(where no committed file carries it) by a read-only query against docker fwapg with TEMP
tables only. No repo file other than this one was written.

## Findings

- **[medium, wrong population claim]** `research/habitat_thresholds.md:212` ("Coverage is
  `fresh_default`'s 55 interior WSGs: no coastal or ocean-type CH") and `:85-86` ("BC
  interior CH are stream-type"). `fresh_default` holds LFRA, HARR and CHWK (Lower Fraser,
  Harrison, Chilliwack) and LSKE, KLUM, LKEL, ZYMO (lower/coastal Skeena). Retained CH
  locations by WSG (`obs_segments.csv`): LFRA 165 (the largest single WSG), HARR 118, LSKE
  122, KLUM 104, CHWK 21, ZYMO 21, LKEL 14 — about 565 of 1,745 (32 %). Spawning-staged:
  LFRA 10, CHWK 8, HARR 4, LSKE 24, KLUM 20, ZYMO 8, LKEL 3. Harrison and Chilliwack fall
  Chinook are the textbook BC ocean-type populations. So the stated coverage limit is
  false, and the argument that the observations align with Cooney & Holzer's stream-type
  (yearling) exclusion rests on it. It does not flip a verdict (all CH values are kept),
  but it is the population statement #283 scoring and any later reader will rely on, and
  it hides that the flattest, most-selected gradient bin is partly lower-Fraser floodplain
  water. Fix: state the coastal/lower-Fraser WSGs and that ocean-type CH are present, or
  split the CH sets by region before leaning on stream-type literature.

- **[low-medium, claim contradicted by the committed quantiles]**
  `research/habitat_thresholds.md:46-48` — "A 100 m FWA window gradient … checks it
  independently of link's breaks; the two agree (CH spawning P95 0.044 vs 0.042, BT 0.125
  vs 0.141)". At the rule's own resolution they do not all agree, and the one that does not
  is omitted: CH rearing segment P95 0.0596 → `snap49` 0.0549 (keep) vs window P95 0.0619 →
  0.0649 (**change**, |Δ| = 1 pp ≥ 0.5 pp). BT is 0.1253 vs 0.1412 (1.6 pp apart, >3× the
  tolerance; snapped 0.1249 vs 0.1449). The independent check therefore flips the CH
  rearing verdict. Step 5 Q1 already asks to test 0.0649, which limits the damage, but the
  sentence should say the window gradient runs higher and would change CH rearing.

- **[low-medium, confidence contradicts the doc's own rule]**
  `research/habitat_thresholds.md:9` — CH `spawn_gradient_max` confidence **high**. The rule
  (`:57-58`, task_plan "Decision rule and confidence") defines high as n ≥ 100 **and the
  literature agrees**. The doc's own text (`:83-89`) says "The literature would go tighter,
  not looser" (Rebellato 0–3 %), and Step 5 Q3 (`:237-238`) asks whether keeping it above
  the literature's 3 % is justified. By the stated rule this is medium. Does not move a
  value (it is a keep), but the table is the published record.

- **[low, one fact stated twice, drifted]** `research/habitat_thresholds.md:72` says "The
  pre-change values are what #283 scoring should test" — three of them (CH spawn 0.0549, CH
  rear 0.0649, BT 0.1349, listed at `:68-70`). Step 5 Q1 (`:233-234`) lists only two (CH
  rearing 0.0649, BT 0.1349); CH spawning 0.0549 is dropped without a reason.

- **[low, population label]** `research/habitat_thresholds.md:41-42` ("the ones on
  accessible segments (CH 226 spawning-staged and 497 rearing-staged; BT 2,443)") and `:138`
  ("All-stage BT use on accessible segments (n 2,443)"). Accessible staged counts are CH
  spawn **244**, CH rear **502**, BT **2,546**. 226 / 497 / 2,443 are accessible **and** on a
  stream edge or river polygon (lake, wetland and other waterbody segments excluded — 18,
  5 and 103 rows). The numbers are right; the population named is not.

- **[low, number vs its definition]** `research/habitat_thresholds.md:170-172` — "Only 1.2 %
  of BT observations (all 2,560) sit on segments that pass the rearing predicate yet end up
  `rearing = FALSE`". Taken as written that is 31 + 3 = 34 / 2,560 = **1.3 %**
  (`bridge_bt.csv`); 1.2 % is the accessible-only numerator (31). Add "accessible" to the
  sentence. Verdict unaffected (both ≪ 10 %).

- **[low, superseded values not marked]** `planning/active/findings.md`, "Phase 1" (lines
  41-75) and "Phase 2" (line 91). The "Code-check round 1" section marks the P95s (0.052,
  0.063, 0.131) and the bridge 2.4 % as superseded, but these pre-fix copies are left
  unmarked and read as current:
  - `:41-42` CH "232 spawn-staged, 507 rear-staged" (now 226 / 497 in the statistics; 250 /
    512 staged at dedup), DV "1,002 rear";
  - `:45-46` window comparison "0.052 segment vs 0.049 window; BT_any 0.131 vs 0.144" (now
    0.044 vs 0.042; 0.125 vs 0.141);
  - `:54` "0 of 232 spawn obs" (now 226);
  - `:57-58` CH spawn width "69 … P5 6.4 m … 3,335 km … 156 of 232" (now 67, 6.6 m,
    3,368 km, 158 of 244 accessible);
  - `:60` "BT_any … (n 2,457)" (now 2,443);
  - `:62` BT width P5 1.85 m (now 1.91 m);
  - `:68-69` "45 % of accessible BT length has NULL width, yet only 2.5 % of BT obs sit
    there (selection 0.08)" — `selection.csv` gives 48.9 % and 4.1 % (0.08 is right; the two
    shares are not, and 2.5/45 = 0.056 is not even internally consistent);
  - `:91` width error "roughly ±40–50 %" — the same p10–p90 0.69–1.56 is −31 % / +56 %;
    round 2 fixed this range in the research doc only.

- **[low, stamps not parallel]** `data-raw/query_habitat_thresholds_fiss.R:187-202` vs
  `data-raw/query_habitat_thresholds_obs.R:487-504`. The FISS stamp omits three things the
  obs stamp records and the FISS script depends on:
  - no `db:` line, though the script snaps to docker fwapg `fresh.streams` (the logs README
    says "Both are read-only against docker fwapg");
  - no `thresholds:` path, though `fiss_presence.csv`'s `share_below_*`/`share_above_*`
    columns are computed against `configs/default/parameters_habitat_thresholds.csv`;
  - its dirty scope (`R data-raw/query_habitat_thresholds_fiss.R`) omits
    `inst/extdata/configs/default`, which it reads (thresholds and `wsg_species_presence`);
    the obs script includes it.
  Also the FISS vintage records `fresh_version` without the `@sha` the obs stamp carries.
  No effect on the committed numbers today (configs/default is unmodified), but a later
  re-run after a config change would not be flagged.

- **[low, population claim in logs README]** `data-raw/logs/habitat_thresholds_284/README.md:37-38`
  — "`candidates.csv` is the decision rule … applied mechanically to accessible-segment
  use." The `cluster_bridge_gradient` row is not: `n` = 2,560, all BT locations (the
  research doc states this correctly at `:42-43`; round 2 fixed the doc, not this copy).

- **[low, PWF]** `planning/active/task_plan.md:18-19` — the Scope bullet "`default_tuned`
  owns a copy of `parameters_fresh.csv`" still reads as the current decision. Phase 4 strikes
  the item and findings explains why, but the Scope line is not marked superseded, and
  `config.yaml`, the bundle README and the research doc all say it inherits.

- **[low, PWF integrity]** `planning/active/task_plan.md:64-68` is ticked `[x]` for "a README
  carrying the stamp (link/fresh SHA, …)". The logs README points to `stamp.txt` rather than
  carrying it, and `stamp.txt` records "fresh installed: 0.34.0 @ no recorded sha" and
  `fresh 0.32.0@NA, 0.33.0@NA` for the build. No fresh SHA is recorded anywhere. Reword the
  item to what was done.

Not a finding, noted: `planning/active/draft_knowledge_issue.md` names one FISS report key
("17032 in PINE and UPCE"). That is one identifier, not site rows, and FISS submissions are
provincial data; flagging only so the decision is deliberate in a public repo.

## Test and checksum (item 5)

- `NOT_CRAN=true Rscript -e 'devtools::test(filter="lnk_config")'` →
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 171 ]`, exit 0.
- `digest::digest(file = "inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv", algo = "sha256")`
  = `f695905587ee51f9053973314e595aff080295a14766b56d5a11191b0d5db075`; the staged blob gives
  the same; `config.yaml` `checksum:` matches. No unstaged changes.

## Enumeration 1 — every numeric / population claim in `research/habitat_thresholds.md`

`snap49(x) = floor(100x)/100 + 0.0049` (the script's snap). Line numbers are the staged file.

| # | Line | Claim | Source | Recomputed | Match |
|---|---|---|---|---|---|
| 1 | 9 | CH spawn_gradient_max default 0.0449, keep | default CSV; candidates.csv | 0.0449; rule keep | y |
| 2 | 9 | CH spawn_gradient_max confidence high | rule + doc :83 | literature disagrees → medium by the rule | **n** |
| 3 | 10 | CH rear_gradient_max 0.0549 keep medium | candidates.csv | 0.0549; keep; n 497, lit mixed | y |
| 4 | 11 | CH spawn width 4 keep medium | candidates.csv (change 6.6) + veto | rule change, lit veto, n 67 | y |
| 5 | 12 | CH rear width 1.5 keep medium | candidates.csv | 1.7, |Δ| 0.2 < 0.5 keep | y |
| 6 | 13 | CH spawn_gradient_min 0 keep high | candidates.csv floors; parameters_fresh | keep ×3; 0 | y |
| 7 | 14 | BT spawn_gradient_max 0.0549 keep low | candidates.csv | keep (inverted clause); DV → low | y |
| 8 | 15 | BT rear_gradient_max 0.1049 → 0.1249 high | candidates.csv | 0.1249 change; n 2443 | y |
| 9 | 16 | BT spawn width 2 keep low | candidates.csv | rule change 1.2; DV low → keep | y |
| 10 | 17 | BT rear width 1.5 keep medium | candidates.csv | 1.9, |Δ| 0.4 keep | y |
| 11 | 18 | BT spawn_gradient_min 0 keep | candidates.csv | keep ×3 | y |
| 12 | 19 | BT bridge 0.05 keep | candidates.csv; parameters_fresh | 0.0121 < 0.10 keep; 0.05 | y |
| 13 | 21-25 | only one value moves; both parameters_fresh values kept | candidates + PHT diff | one cell differs | y |
| 14 | 38 | 55 WSGs persisted in fresh_default | stamp.txt; DB | 55 | y |
| 15 | 40 | CH 1,745, BT 2,560 locations | obs_ledger step 7 | 1745 / 2560 | y |
| 16 | 41-42 | "on accessible segments (CH 226 … 497; BT 2,443)" | obs_segments | accessible = 244 / 502 / 2546; 226/497/2443 = accessible ∩ stream/river_poly | **n** (label) |
| 17 | 42-43 | bridge and UHC use all locations | script :356, :367 | BT_any all 2560; CH_any all 1745 | y |
| 18 | 45 | 99 % of points within 1 m of a break | DB, retained obs | BT 99.8 %, CH 99.8 %, DV 99.7 % | y |
| 19 | 47 | CH spawn P95 0.044 vs window 0.042 | quantiles.csv | 0.0443 / 0.0419 | y |
| 20 | 48 | BT P95 0.125 vs window 0.141 | quantiles.csv | 0.1253 / 0.1412 | y |
| 21 | 47 | "the two agree" | quantiles.csv | CH rear 0.0596 vs 0.0619 → snap 0.0549 vs 0.0649 (verdict flips) | **n** |
| 22 | 52-53 | P95 snapped to x.xx49, kept within 0.5 pp | script :380, :397 | matches | y |
| 23 | 53-55 | width P5 on stream edges outside waterbodies, kept within 0.5 m | script :280, :402 | matches | y |
| 24 | 55-56 | floor: < 5 % below and ratio < 0.5 | script :431 | matches | y |
| 25 | 56-57 | bridge raised if > 10 % | script :441 | matches | y |
| 26 | 57-59 | confidence definition | task_plan :44-45 | matches | y |
| 27 | 68 | CH spawn P95 0.052 → 0.044; 0.0549 change → keep | obs_segments (all vs accessible) | 0.0519 → 0.0443; snap 0.0549 / 0.0449 | y |
| 28 | 69 | CH rear P95 0.063 → 0.060; 0.0649 → keep | obs_segments | 0.0630 → 0.0596; 0.0649 / 0.0549 | y |
| 29 | 70 | BT P95 0.131 → 0.125; 0.1349 → 0.1249 | obs_segments | 0.1311 → 0.1253 | y |
| 30 | 72 vs 233-234 | pre-change values to be scored | doc | 3 listed at :68-70, 2 in Step 5 | **n** |
| 31 | 75-76 | inverted clause fired once, BT spawn gradient | candidates ratio_first_bin_above | 1.32 BT spawn; CH 0.46, 0.51; BT rear 0.59 | y |
| 32 | 80 | P95 of 226 spawning obs 0.044 | quantiles | 226, 0.0443 | y |
| 33 | 81 | selection below 1 at 2–3 % | selection CH_spawn | 0.77 | y |
| 34 | 81-82 | ~0.4–0.5 from 3 to 5 % | selection | 0.38, 0.49, 0.46 | y |
| 35 | 82-83 | no spawning obs in (0.05, 0.055], 2,140 km | selection | 0 obs, 2139.6 km | y |
| 36 | 85-86 | C&H > 5 % excluded, yearling CH, C-7/C-8 | literature.md §1 | matches | y |
| 37 | 86 | "BC interior CH are stream-type" (as the population) | obs_segments by WSG | ~32 % of CH in lower-Fraser / coastal-Skeena WSGs incl. HARR, CHWK | **n** |
| 38 | 87 | Busch 4–7 % at 0.05 | literature.md | matches | y |
| 39 | 88-89 | Rebellato Table 1 0–3 % | literature.md | matches | y |
| 40 | 91 | 3–4.5 % carries 14 spawning obs | selection | 9 + 5 = 14 | y |
| 41 | 94-96 | flattest bin ratio 2.8, 41 % of spawning obs | selection / candidates floor | 2.78 / 2.82; 0.412 | y |
| 42 | 95-96 | no literature starts spawning above 0 % | literature.md §1 | "No minimum found" | y |
| 43 | 99 | most spawning obs on river polygons | obs_segments | 158 of 244 accessible | y |
| 44 | 100-101 | 67 on stream edges, P5 6.6 m | quantiles | 67, 6.637 | y |
| 45 | 101 | no obs 4–6 m, 3,368 km | selection | 0 + 0; 1941.2 + 1426.6 = 3367.8 | y |
| 46 | 104-105 | C&H 3.6 m wetted; BF < 3.7 = none | literature.md | matches | y |
| 47 | 106 | Busch ≤ 4 m bankfull unsuitable | literature.md | matches | y |
| 48 | 107-108 | Woll Table 16 < 4 m not suitable, likely origin | literature.md | matches (inference flagged) | y |
| 49 | 110-111 | width good to −30 % / +55 % | fiss_width_error MODELLED | 0.686 / 1.558 → −31 % / +56 % | y |
| 50 | 113-114 | CH rear P95 of 497 = 0.060 | quantiles | 497, 0.0596 | y |
| 51 | 114-115 | ratio 0.1–0.5 from 5 to 10 % | selection CH_rear | 0.34, 0.51, 0.35, 0.10, 0.20, 0.50 | y |
| 52 | 118 | Beamer no non-natal juveniles above 6.5 % | literature.md | matches | y |
| 53 | 119 | Woll Table 17 3–7 % low, > 7 % none | literature.md; R2 checked source | matches | y |
| 54 | 119-120 | Agrawal via Sheer 8 % max, very low > 3.5 % | literature.md | matches | y |
| 55 | 121 | C&H > 5 % is expert opinion | literature.md | matches | y |
| 56 | 122-123 | 5 % unsourced; Rebellato → Woll, Porter; neither states it | literature.md §0 | matches | y |
| 57 | 125 | CH rear width P5 1.7 m | quantiles | 1.714 | y |
| 58 | 125-126 | 1.5 m no literature; bcfp small-stream filter | literature.md | matches | y |
| 59 | 133 | DV in 140 of 158 BT WSGs | wsg_species_presence | 140 / 158 | y |
| 60 | 138 | BT all-stage "on accessible segments (n 2,443)", P95 0.125 | quantiles; obs_segments | 0.1253; accessible 2,546 (2,443 = ∩ stream/river_poly) | **n** (label) |
| 61 | 138-139 | ~0.6 from 5 to 12 %; 0.37 at 12–15; 0.19 at 15–20 | selection BT_any | 0.63–0.72, 0.56–0.61; 0.37; 0.19 | y |
| 62 | 140 | DV rear ≥ 1 up to 12 %; 1.37 at 10.5–12; 0.70 at 12–15 | selection BT_rear_dv | ≥ 1 from 1 % to 12 %; 1.37; 0.70 | y |
| 63 | 141-142 | Isaak 15 % trim (< 1 %), max 14.7 % | literature.md | matches | y |
| 64 | 142-143 | Porter BT CPUE highest in steeper Thompson streams | literature.md | matches | y |
| 65 | 144 | FISS presence n 15, P95 0.106 | fiss_presence BT present gradient | 15, 0.106 | y |
| 66 | 149 | DV spawning n 76 | quantiles BT_spawn_dv | 76 | y |
| 67 | 150-152 | redd < 1 % (McPhail & Murray via Ford); "relatively low gradient" | literature.md | matches | y |
| 68 | 154 | DV spawning width P5 1.2 m (n 53) | quantiles | 1.16, 53 | y |
| 69 | 155-157 | Hagen 2015 §4.1.2 2 m wetted | literature.md | matches | y |
| 70 | 161 | BT all-stage width P5 1.91; selection ≥ 1 from 3 m | quantiles; selection | 1.912; 1.41 at (3,4] onward | y |
| 71 | 162 | FISS presence width P5 1.9, none < 1.5 | fiss_presence | 1.9; share_below_rear_min 0 | y |
| 72 | 163-164 | Dunham & Rieman via Dunham & Chandler pp. 3, 26 | literature.md | matches | y |
| 73 | 168 | DV spawning selection 2.2 in flattest bin | selection BT_spawn_dv | 2.22 | y |
| 74 | 170-171 | 1.2 % of all 2,560 pass predicate yet rearing FALSE | bridge_bt.csv | 34/2560 = 1.33 % as worded; 31/2560 = 1.21 % accessible | **n** (wording) |
| 75 | 174-180 | bridge mechanism (upstream boolean; downstream < 5 % within 10 km) | R2 verified in fresh | not re-derived | y (per R2) |
| 76 | 180 | bridge has no literature origin | literature.md | matches | y |
| 77 | 184-185 | COTR LNTH PINE UNTH UPCE; 9,679 sites, 362 with width | fiss_stamp.txt | matches | y |
| 78 | 188-190 | 18 MODELLED sites, median 0.97, p10–p90 0.69–1.56 | fiss_width_error | 18; 0.968; 0.686–1.558 | y |
| 79 | 191-192 | 81 FIELD_MEASURMENT at 1.00, not independent | fiss_width_error | 81; 1.00; independent FALSE | y |
| 80 | 193-194 | BT present n 16, median 5.5 m, 2.5 %; absent 1.46 m, 8 % | fiss_presence | 16, 5.53, 0.025 (n 15); 1.458, 0.08 | y |
| 81 | 194-195 | no CH caught at a measured-width site | fiss_presence | no CH present site-measured row | y |
| 82 | 204 | BT NULL-width (order-1) use 0.08 of availability | selection BT_any; obs_segments | 0.08; all 64 BT NULL-width stream obs are order 1 | y |
| 83 | 208 | CH threshold 5 since 1990, BT 1 | parameters_fresh | 5 / 1990-01-01; 1 / NA | y |
| 84 | 208-209 | 98 % CH, 99 % BT accessible | obs_segments | 98.2 %, 99.5 % | y |
| 85 | 210-211 | UHC holds 636 CH locations in spawning reaches | uhc_ch.csv | 394 + 242 = 636, all uhc_spawning 1 | y |
| 86 | 212 | 55 interior WSGs, no coastal/ocean-type CH | DB WSG list; obs_segments | includes LFRA, HARR, CHWK, LSKE, KLUM, LKEL, ZYMO | **n** |
| 87 | 213-216 | 55 obs on NULL-width river polys, 31 in TABR/UPCE/LPCE, all dropped | obs_segments | 55 (30 BT, 21 CH, 4 DV); 11+10+10 = 31; all spawning/rearing FALSE | y |
| 88 | 225-227 | BULK, MORR in fresh_default; UNTH, LNTH not | DB | BULK, MORR present; UNTH, LNTH absent | y |

**88 claims checked, 81 match, 7 do not** (rows 2, 16, 21, 30, 37/86 — one defect stated
twice — 60, 74). None flips a published candidate value; row 21 would flip the CH rearing
rule verdict under the independent gradient, and rows 37/86 misstate the CH population.

## Enumeration 2 — where candidate values and changed cells are stated

| Place | What it states | Agrees with candidates.csv + vetoes? |
|---|---|---|
| `default_tuned/parameters_habitat_thresholds.csv` | only BT `rear_gradient_max` 0.1249 differs from default (diffed) | y |
| `default_tuned/config.yaml` description | one cell, BT rear_gradient_max 0.1049 → 0.1249; inherits parameters_fresh | y |
| `default_tuned/config.yaml` checksum | f695905… | y (digest matches) |
| `default_tuned/README.md` Status | one cell 0.1049 → 0.1249; spawn_gradient_min, bridge kept | y |
| `tests/testthat/test-lnk_config.R` | exactly `BT, rear_gradient_max, 0.1049, 0.1249` | y (passes) |
| `research/habitat_thresholds.md` verdict table | 11 rows, one change 0.1249 | y (confidence of row CH spawn gradient: see finding) |
| `research/habitat_thresholds.md` Change 1 / Step 5 | pre-change values 0.0549 / 0.0649 / 0.1349 vs Step 5's two | partial (finding) |
| logs `README.md` | no values; population of candidates.csv | population wording (finding) |
| `task_plan.md` | Phase 4 ticked; parameters_fresh copy struck; Scope bullet says a copy is owned | Scope bullet stale (finding) |
| `findings.md` round-1 section | BT 0.1349 → 0.1249; CH rear 0.0649 withdrawn; bridge 2.4 → 1.2 % | y (marked) |
| `findings.md` Phase 1/2 sections | pre-fix counts and values | unmarked (finding) |

## Enumeration 3 — populations per output file

Common base (`o7`): not excluded, not Releases Database, DV only where WSG has BT, WSG in
`fresh_default` with species present, joined to a segment, match class A/B, one per
obs_species × blue_line_key × round(m) (ordered by observation_key).

| Output | Population as computed | As described (logs README / research doc) | Match |
|---|---|---|---|
| obs_ledger.csv | steps 0-7 above | same | y |
| obs_segments.csv | all of `o7`, incl. inaccessible and DV | "one row per retained observation" | y |
| obs_status.csv | every set, all rows (incl. inaccessible) | not described | n/a |
| quantiles.csv | set ∩ accessible; gradient: pred_set stream + river_poly; width: stream only (by source) | "accessible-only"; research doc names the counts as "on accessible segments" | label (finding) |
| selection.csv | set ∩ accessible; gradient stream + river_poly, width stream (NULL bin kept); availability accessible, same WSGs, `waterbody_key IS NULL` stream edges (+ R polys for gradient) | matches README :25-28 | y |
| candidates.csv — gradient/width rows | from quantiles (accessible ∩ pred_set) | "accessible-segment use" | y |
| candidates.csv — floor rows | CH_spawn / BT_spawn_dv ∩ accessible ∩ stream/river_poly | same | y |
| candidates.csv — bridge row | all 2,560 BT (numerator accessible only) | README "accessible-segment use" | **n** (finding) |
| bridge_bt.csv | all BT_any, split by accessible | doc "all 2,560" | y |
| uhc_ch.csv | all CH_any (1,745) | doc "all" | y |
| projects.csv | all `o7` incl. DV, by `source_ref` prefix | not described; findings 7.9 %, 10.4 %, BT ≤ 3.5 % recompute | y |
| fiss_presence.csv | sites in WSGs where species in range, (sampled or caught); site width / site gradient / segment width within 50 m | README / doc | y |
| fiss_width_error.csv | measured width ∧ segment width ∧ dist_m ≤ 50, by source | doc omits the 50 m but states the 18 / 81 | y |

Stage: CH spawn regex also matches activity text "Spawning" with a blank code (checked in
bcfishobs; SPM is "Major spawning location", not migration), so "activity SPL/SPM/S" is a
slight understatement, not an error.

## Enumeration 4 — stamp blocks

| Field | stamp.txt (obs) | fiss_stamp.txt |
|---|---|---|
| date | y | y |
| link version @ sha | y | y |
| dirty flag | y (R/, configs/default, script) | y (R/, script — **omits configs/default**) |
| fresh installed | y (0.34.0, no sha) | n (not used for computation; acceptable) |
| db host/port | y | **n** |
| schema + build vintage | y (count, dates, fresh version@sha) | y (per WSG, fresh version, **no sha**) |
| input row counts | bcfishobs rows | FISS site counts |
| thresholds file | y | **n** (it reads default's) |
| other input SHA | — | knowledge @ 20f0a5a + dirty data/ |

## Checked and fine

- `default_tuned` CSV differs from `default` in exactly one cell; test asserts that and
  passes; checksum current.
- Every literature statement in the doc matches `literature.md` (and R2's source check).
- Pre-change P95s recompute exactly from `obs_segments.csv` without the accessible filter.
- `research/README.md` lists every file in `research/`; `^research$` is in `.Rbuildignore`.
- No absolute home paths or FISS site rows in the staged diff.

/Users/airvine/Projects/repo/link/planning/active/review-round3.md
