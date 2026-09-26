# Code-check round 4 — #284 staged diff, re-enumeration (2026-09-26)

Reviewer: round-4 subagent. Read-only. Everything was recomputed from the committed CSVs in
`data-raw/logs/habitat_thresholds_284/` (regenerated 01:04 for obs and 01:15 for FISS, the same
day as round 3), from `planning/active/literature.md`, from `inst/extdata/configs/default/`, from
the `knowledge` repo's FISS inputs, or from read-only DB queries against docker fwapg (no TEMP
tables this round; the 1 m check used `unnest()` parameters). No repo file other than this one
was written. The tree was fully staged, with no unstaged changes, throughout.

## Findings

All seven round-3 claim mismatches are fixed, and so are the stale copies it listed. Three
low-severity defects remain. None of them moves a number or a verdict.

- **[low, dangling cross-reference]** `research/habitat_thresholds.md:103-104`: "This confirms
  the reverted 0.0025 floor in `default_vs_bcfishpass.md` §9." That file has no §9. Its
  numbered sections are 1–5 under "Departures" and 1–8 under "Observations / surprises". The
  floor content is at `## Follow-up: spawn gradient minimum design` (line 443: "Tried
  `spawn_gradient_min = 0.0025` … Reverted to 0 for shipping"). The substance of the claim is
  correct. The bad pointer comes from `default_vs_bcfishpass.md:104` and `:398`, which cite
  "§9" themselves, and it is copied again at `planning/active/findings.md:71`. Fix: name the
  section, e.g. "(§ Follow-up: spawn gradient minimum design)".

- **[low, claim contradicted by an artifact it names]** `planning/active/task_plan.md:68-71`
  (the reworded stamp checkbox): "the stamp is in `stamp.txt` / `fiss_stamp.txt` (… no fresh
  SHA exists to record: the installed fresh has none and the log's `fresh_sha` is NULL …)".
  - This holds for `stamp.txt`. `fresh_default.log` gives `0.32.0@NA, 0.33.0@NA`, and the
    installed fresh 0.34.0 has no `RemoteSha`; both verified.
  - It does not hold for `fiss_stamp.txt`, which the same sentence names. That stamp records
    `fresh 0.33.0@7f12d99` for all five WSGs, read from `fresh.log`, whose `fresh_sha` is
    populated.
  - Fix: scope the clause to `fresh_default` ("the `fresh_default` log's `fresh_sha` is
    NULL; `fiss_stamp.txt` records 7f12d99 from `fresh.log`").

- **[low, stale provenance copy]** `planning/active/findings.md:89` (Phase 2): "Evidence:
  `fiss_presence.csv`, `fiss_width_error.csv` (knowledge@20f0a5a; …)". The committed
  `fiss_stamp.txt` now records `knowledge @ 14afc0d`, because the FISS script was re-run at
  01:15.
  - `20f0a5a` is not an ancestor of `14afc0d`.
  - `git diff --name-only 20f0a5a 14afc0d -- data` touches no `fiss_sites_*_all.csv`, so the
    inputs are byte-identical and every FISS number is unchanged. The recomputation below
    confirms this.
  - Phase 2's superseded note covers only the width-error range, not the SHA.
  - Fix: add the SHA to that note, or say "first run at 20f0a5a; committed outputs at
    14afc0d, same inputs".

## Test and checksum (item 4)

- `NOT_CRAN=true Rscript -e 'devtools::test(filter="lnk_config")'` →
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 171 ]`.
- `digest::digest(file = "inst/extdata/configs/default_tuned/parameters_habitat_thresholds.csv", algo = "sha256")`
  = `f695905587ee51f9053973314e595aff080295a14766b56d5a11191b0d5db075`. This matches
  `config.yaml`'s `checksum:`.

## Enumeration 1 — every numeric / population claim in the current `research/habitat_thresholds.md`

`snap49(x) = floor(100x)/100 + 0.0049`. Line numbers are those of the current staged file.
"acc∩pred" means accessible and `pred_set` ∈ {stream, river_poly}.

| # | Line | Claim | Source | Recomputed | Match |
|---|---|---|---|---|---|
| 1 | 9 | CH spawn_gradient_max 0.0449 keep, **medium** | candidates.csv; rule :61-63 | 0.0449, keep; n 226, literature points lower → medium | y (R3 fix) |
| 2 | 10 | CH rear_gradient_max 0.0549 keep medium | candidates.csv | keep, n 497, literature mixed | y |
| 3 | 11 | CH spawn width 4 keep medium | candidates.csv + literature veto | rule says change to 6.6, n 67, vetoed | y |
| 4 | 12 | CH rear width 1.5 keep medium | candidates.csv | 1.7, \|Δ\| 0.2 → keep | y |
| 5 | 13 | CH spawn_gradient_min 0 keep high | candidates.csv floors; default parameters_fresh | keep ×3 floors; n 226; literature has no minimum | y |
| 6 | 14 | BT spawn_gradient_max 0.0549 keep low | candidates.csv | rule_value 0.1949, keep via inverted clause; DV → low | y |
| 7 | 15 | BT rear_gradient_max 0.1049 → 0.1249 high | candidates.csv | 0.1249 change, n 2,443 | y |
| 8 | 16 | BT spawn width 2 keep low | candidates.csv | rule says change to 1.2 (DV) → low → keep | y |
| 9 | 17 | BT rear width 1.5 keep medium | candidates.csv | 1.9, \|Δ\| 0.4 → keep | y |
| 10 | 18 | BT spawn_gradient_min 0 keep medium | candidates.csv | keep ×3 | y |
| 11 | 19 | BT bridge 0.05 keep medium | candidates.csv; parameters_fresh | 0.0121 < 0.10, keep; 0.05 | y |
| 12 | 21-25 | one value moves; both parameters_fresh values kept, file inherited | CSV diff; config.yaml | one cell differs; no own parameters_fresh | y |
| 13 | 38 | 55 WSGs persisted in fresh_default | DB | 55 | y |
| 14 | 40 | CH 1,745, BT 2,560 locations | obs_ledger step 7; obs_segments | 1,745 / 2,560 | y |
| 15 | 40-43 | gradient stats: acc∩pred, CH 226 spawn / 497 rear, BT 2,443 | obs_segments | 226 / 497 / 2,443 (accessible alone: 244 / 502 / 2,546) | y (R3 fix) |
| 16 | 43-44 | bridge share and UHC use all locations | bridge_bt 2,560; uhc_ch 636 of 1,745 | yes | y |
| 17 | 45-46 | 99 % of points within 1 m of a break | DB, fresh_default.streams ends vs obs m | 100 % (BT 2560/2560, CH 1745/1745); R3 got 99.8 % | y |
| 18 | 47-49 | CH spawn P95 0.044 vs window 0.042, agree | quantiles | 0.0443 / 0.0419; both snap to 0.0449 | y |
| 19 | 49-50 | CH rear 0.060 vs 0.062; window snaps to 0.0649 and flips to change | quantiles | 0.0596 / 0.0619; 0.0549 vs 0.0649, \|Δ\| 1 pp → change | y (R3 fix) |
| 20 | 50-51 | BT 0.125 vs 0.141, 1.6 points apart | quantiles | 0.1253 / 0.1412; 1.59 pp | y |
| 21 | 56-58 | gradient: P95, snap x.xx49, keep within 0.5 pp | script; candidates | consistent | y |
| 22 | 58-60 | width: P5 on stream edges outside waterbodies, keep within 0.5 m | candidates n 67 / 215 / 1,469 / 53 | consistent | y |
| 23 | 59-60 | floor: < 5 % below and ratio < 0.5 | candidates floor rows | all fail → keep | y |
| 24 | 60-61 | bridge raised if > 10 % lost | candidates | 1.21 % | y |
| 25 | 61-63 | confidence definition | task_plan :45-46 | same text | y |
| 26 | 72 | CH spawn P95 0.052 → 0.044, 0.0549 change → keep | obs_segments, all vs accessible | 0.0519 → 0.0443; snap 0.0549 / 0.0449 | y |
| 27 | 73 | CH rear 0.063 → 0.060, 0.0649 → keep | obs_segments | 0.0630 → 0.0596 | y |
| 28 | 74 | BT 0.131 → 0.125, 0.1349 → 0.1249 | obs_segments | 0.1311 → 0.1253 | y |
| 29 | 77-80 | inverted clause fired once, BT spawn gradient | candidates ratio_first_bin_above | 1.32 BT spawn; CH 0.46, 0.51; BT rear 0.59 | y |
| 30 | 84-85 | P95 of 226 spawn obs 0.044 = current | quantiles | 226, 0.0443 → 0.0449 | y |
| 31 | 85 | selection below 1 at 2–3 % | selection CH_spawn | 0.77 | y |
| 32 | 85-86 | ~0.4–0.5 from 3 to 5 % | selection | 0.38, 0.49, 0.46 | y |
| 33 | 86-87 | no spawning obs in (0.05, 0.055], 2,140 km | selection | 0; 2,139.6 km | y |
| 34 | 89-90 | C&H App. C, C-7/C-8, > 5 % excluded for yearling CH | literature.md :61 | matches | y |
| 35 | 90-92 | about a third of CH locations in lower Fraser / coastal Skeena | obs_segments by WSG | 565 / 1,745 = 32.4 % | y (R3 fix) |
| 36 | 91-92 | ocean-type runs there; Busch applies | literature.md :64 (Busch = ocean-type, lower Columbia fall CH) | consistent | y |
| 37 | 93 | Busch 4–7 % at 0.05 | literature.md :64 | matches | y |
| 38 | 94-95 | Rebellato Table 1, 0–3 %, documented origin | literature.md :29, :117 | matches | y |
| 39 | 97 | 3–4.5 % carries 14 spawning obs | selection | 9 + 5 = 14 | y |
| 40 | 98-99 | medium because literature points lower | rule; claim 38 | consistent | y |
| 41 | 102 | flattest bin ratio 2.8, 41 % of spawning obs | selection; candidates floor 0.0025 | 2.78 / 2.82; 0.412 | y |
| 42 | 102-103 | no literature starts spawning habitat above 0 % | literature.md :67 | "No minimum found" | y |
| 43 | 103-104 | reverted 0.0025 floor in `default_vs_bcfishpass.md` §9 | default_vs_bcfishpass.md | floor reverted: yes (line 443+); **§9 does not exist** | **n** (pointer) |
| 44 | 106 | most spawning obs on river polygons | obs_segments | 158 of 244 accessible | y |
| 45 | 107-108 | 67 on stream edges with width, P5 6.6 m | quantiles | 67, 6.637 | y |
| 46 | 108 | no obs at 4–6 m, 3,368 km | selection | 0 + 0; 1,941.2 + 1,426.6 = 3,367.8 | y |
| 47 | 111-112 | C&H 3.6 m wetted, BF < 3.7 none | literature.md :69 | matches | y |
| 48 | 113 | Busch ≤ 4 m bankfull unsuitable | literature.md :70 | matches | y |
| 49 | 114-115 | Woll Table 16 "< 4 m" not suitable, likely origin | literature.md :71, :37 | matches (inference flagged) | y |
| 50 | 117-118 | modelled width good to about −30 % / +55 % | fiss_width_error MODELLED | 0.686 / 1.558 → −31 % / +56 % | y |
| 51 | 120-121 | CH rear P95 of 497 = 0.060 = current | quantiles | 497, 0.0596 → 0.0549 | y |
| 52 | 121-122 | thins above 2 %; ratio 0.1–0.5 from 5 to 10 % | selection CH_rear | 0.59 at 2–3 %; 0.34, 0.51, 0.35, 0.10, 0.20, 0.50 | y |
| 53 | 125 | Beamer no non-natal juveniles above 6.5 % | literature.md :78 | matches | y |
| 54 | 126 | Woll Table 17: 3–7 % low, > 7 % none | literature.md :76 (R2 checked PDF) | matches | y |
| 55 | 126-127 | Agrawal via Sheer 8 % max, very low > 3.5 % | literature.md :75 | matches | y |
| 56 | 128 | C&H > 5 % is expert opinion | literature.md :61 | matches | y |
| 57 | 129-130 | 5 % unsourced; Rebellato → Woll, Porter; neither states it | literature.md :35 | matches | y |
| 58 | 132 | CH rear width P5 1.7 m | quantiles | 1.714 | y |
| 59 | 132-133 | 1.5 m no literature origin; small-stream filter | literature.md :148 | matches | y |
| 60 | 137 | bcfishobs gives BT no life stage or activity | DB bcfishobs.observations | BT 11,375 rows: 0 with stage, 0 with activity | y |
| 61 | 139-140 | DV in 140 of 158 BT WSGs | default wsg_species_presence.csv | 140 / 158 | y |
| 62 | 145 | all-stage BT on accessible segments n 2,443, P95 0.125 | quantiles | 2,443 (acc∩pred, per Method :41-42), 0.1253 | y |
| 63 | 145-146 | ~0.6 from 5 to 12 %; 0.37 at 12–15 %; 0.19 at 15–20 % | selection BT_any | 0.56–0.72; 0.37; 0.19 | y |
| 64 | 147 | DV rear ≥ 1 up to 12 %; 1.37 at 10.5–12 %; 0.70 at 12–15 % | selection BT_rear_dv | ≥ 1 from 1 % to 12 %; 1.37; 0.70 | y |
| 65 | 148-150 | Isaak 15 % trim (< 1 %), max 14.7 %; Porter CPUE steeper Thompson | literature.md :94-95, :105, :108 | matches | y |
| 66 | 151 | FISS presence n 15, P95 0.106 | fiss_presence BT present gradient | 15, 0.106 | y |
| 67 | 152 | current 0.1049 has no source | literature.md :139 | matches | y |
| 68 | 156 | DV spawning n 76 | quantiles BT_spawn_dv | 76 | y |
| 69 | 157-159 | redd < 1 % (McPhail & Murray via Ford); "relatively low gradient" (M&B 1996) | literature.md :90-91 | matches | y |
| 70 | 161 | DV spawning width P5 1.2 m (n 53) | quantiles | 1.16, 53 | y |
| 71 | 162-164 | Hagen 2015 §4.1.2, Parsnip and Pack, 2 m wetted | literature.md :96 | matches | y |
| 72 | 168 | all-stage width P5 1.91; selection ≥ 1 from 3 m | quantiles; selection | 1.912 (n 1,469); 1.41 at (3,4] onward | y |
| 73 | 169 | FISS presence width P5 1.9, none < 1.5 | fiss_presence | 1.9; share_below_rear_min 0 | y |
| 74 | 170-171 | Dunham & Rieman via Dunham & Chandler, pp. 3 and 26 | literature.md :103 | matches | y |
| 75 | 173 | 0.5 m tolerance keeps it | candidates | \|1.9 − 1.5\| = 0.4 | y |
| 76 | 175 | DV spawning selection 2.2, flattest bin | selection BT_spawn_dv | 2.22 | y |
| 77 | 177-180 | 1.2 %, 31 of all 2,560, accessible, pass predicate, rearing FALSE | bridge_bt.csv | 31 / 2,560 = 1.21 % | y (R3 fix) |
| 78 | 182-187 | bridge mechanism; 10 km | R2 fresh read; parameters_fresh cluster_bridge_distance | 10000 | y |
| 79 | 187-188 | bridge has no literature origin | literature.md :149 | matches | y |
| 80 | 192-193 | COTR LNTH PINE UNTH UPCE; 9,679 sites, 362 with width | fiss_stamp.txt | matches | y |
| 81 | 196-198 | 18 MODELLED, median 0.97, p10–p90 0.69–1.56, about −30 / +55 % | fiss_width_error | 18; 0.968; 0.686–1.558 | y |
| 82 | 199-200 | 81 FIELD_MEASURMENT at 1.00, not independent | fiss_width_error | 81; 1; FALSE | y |
| 83 | 201-203 | BT present n 16, median 5.5 m and 2.5 %; absent 1.46 m, 8 % | fiss_presence | 16, 5.53; 0.025 (n 15); 1.458; 0.08 | y |
| 84 | 203 | no CH caught at a measured-width site | fiss_presence | no CH present site-measured row | y |
| 85 | 204-205 | `average_gradient_percent` holds proportions | knowledge fiss_sites_*_all.csv | 469 non-NA values, max 0.43 | y |
| 86 | 211-212 | BT NULL-width (order-1) use 0.08 of availability | selection BT_any NULL | 0.08 (use 4.1 %, avail 48.9 %) | y |
| 87 | 216 | CH threshold 5 since 1990, BT 1 | default parameters_fresh.csv | 5 / 1990-01-01; 1 / NA | y |
| 88 | 216-217 | 98 % CH, 99 % BT observation segments accessible | obs_segments | 98.2 %, 99.5 % | y |
| 89 | 218-219 | UHC holds 636 CH locations | uhc_ch.csv | 394 + 242 = 636 | y |
| 90 | 220 | coverage is fresh_default's 55 WSGs, most interior | DB WSG list | 55; 7 lower Fraser / coastal Skeena | y |
| 91 | 220-222 | LFRA, HARR, CHWK, LSKE, KLUM, LKEL, ZYMO carry 565 of 1,745 CH | obs_segments | 165 + 118 + 21 + 122 + 104 + 14 + 21 = 565 | y (R3 fix) |
| 92 | 222 | Harrison and Chilliwack fall runs are ocean-type | no committed source (Healey 1991 unread) | general knowledge, consistent; not flagged | y (unsourced) |
| 93 | 224 | Vancouver Island and central coast not covered | DB WSG list | none of the 55 | y |
| 94 | 225-228 | 55 obs on NULL-width river polys, 31 in TABR/UPCE/LPCE, all dropped | obs_segments | 55 (BT 30, CH 21, DV 4); 10 + 11 + 10; 0 with spawning/rearing TRUE | y |
| 95 | 237-239 | BULK, MORR in fresh_default; UNTH, LNTH only in fresh | DB | BULK/MORR in both; UNTH/LNTH fresh only | y |
| 96 | 244-247 | pre-change values CH spawn 0.0549, CH rear 0.0649, BT 0.1349 | Method :72-74 | three listed, same as Method | y (R3 fix) |
| 97 | 247 | CH rear 0.0649 is also what the window gradient gives | claim 19 | snap49(0.0619) = 0.0649 | y |

**97 claims checked, 96 match, 1 does not** (#43: a pointer, not a number).

## Enumeration 2 — every place the changed cell is stated

| Place | States | Agrees |
|---|---|---|
| `default_tuned/parameters_habitat_thresholds.csv` | `git diff` vs default: only BT `rear_gradient_max` 0.1049 → 0.1249 | y |
| `default_tuned/config.yaml` description | one cell, BT rear_gradient_max 0.1049 → 0.1249; inherits parameters_fresh | y |
| `default_tuned/config.yaml` checksum | f695905… | y (digest matches) |
| `default_tuned/README.md` Status | one cell 0.1049 → 0.1249; others kept | y |
| `tests/testthat/test-lnk_config.R:326-328` | exactly `BT / rear_gradient_max / 0.1049 / 0.1249` | y (passes) |
| `research/habitat_thresholds.md` verdict table + :143, :152 | 0.1049 → 0.1249; Change 1 and Step 5 give 0.1349 as the pre-change value | y |
| logs `README.md` | no values; the bridge population is now stated | y |
| `task_plan.md` :8, :10 | 0.1049 as the *current* value (issue text, accepted); scope bullet marked superseded | y |
| `findings.md` :14, :122 | 0.1049 current (issue text); 0.1349 → 0.1249 inside the round-1 section, marked as a change | y |
| Other tracked copies of 0.1049 (`default_extrabreaks`, `default_rearbreaks`, NEWS, vignette, literature.md) | describe `default` or other bundles, not `default_tuned` | n/a |

The cell is stated consistently everywhere, and no other cell is claimed changed.

## Enumeration 3 — stamps, field by field

| Field | stamp.txt (obs) | fiss_stamp.txt | Verified against |
|---|---|---|---|
| date | 2026-09-26 01:04 PDT | 2026-09-26 01:15 PDT | file mtimes 01:04:48 / 01:15:39 |
| link @ sha | 0.51.0 @ 9d1f975 | 0.51.0 @ 9d1f975 | HEAD = 9d1f975 |
| dirty scope | R, configs/default, own script | R, configs/default, own script (R3 fixed) | both scripts' `git status --porcelain` pathspecs |
| fresh installed | 0.34.0 @ no recorded sha | absent (the FISS script does not use it) | `RemoteSha` NULL |
| db | docker fwapg localhost:5432 | same (R3 fixed) | — |
| thresholds | configs/default CSV | configs/default CSV (R3 fixed) | — |
| schema vintage | fresh_default: 55 WSGs, 4 log rows, 2026-08-06 → 08-27, 0.32.0@NA, 0.33.0@NA | fresh, per WSG: 0.33.0@7f12d99, 09-02 / 09-03 (R3 fixed @sha) | DB log queries reproduce both strings exactly |
| input counts | bcfishobs.observations 373,050 | sites 9,679; width 362; gradient 353; snapped 5,322 | DB count 373,050 |
| other input SHA | — | knowledge @ 14afc0d (dirty data/) | knowledge HEAD 14afc0d; dirty = untracked reports_pdf (accepted) |
| snap radius | — | 150 m search; statistics use ≤ 50 m | script :103 / :142 / :158 |

The two stamps are now parallel wherever both scripts depend on the same thing. The only
downstream disagreement is the task_plan wording in Finding 2.

## Checked and fine

- Every round-3 fix is present and correct:
  - coverage 565 / 1,745;
  - the stream-type qualification;
  - the window flip disclosed;
  - CH spawn confidence set to medium;
  - Step 5 lists three values;
  - the population labels are defined in Method;
  - bridge 31 / 2,560, accessible;
  - findings.md superseded banners, with NULL-width 48.9 % / 4.1 %;
  - the FISS stamp lines;
  - the logs README bridge population;
  - task_plan scope marked superseded.
- The findings.md project-dominance line (7.9 %, 10.4 % without `source_ref`, BT ≤ 3.5 %)
  recomputes from `projects.csv`.
- The findings.md CH snapped presence line (n 20, median 34.7 m, P5 5.4 m) matches
  `fiss_presence.csv`.
- No unstaged changes. The tests pass and the checksum is current.
