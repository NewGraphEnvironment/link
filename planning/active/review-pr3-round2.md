# Code-check of PR 3 (#440), round 2

Diff: `branch3.diff` (`data-raw/logs/parity_0.78.0/`, `data-raw/logs/test_builds_440/`, `research/bcfishpass_parity.md`), at HEAD `02d3c418`.

## Checklist read

- `code-check.md`, every H3 under `## Mechanisms`, prose only: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice.
- `code-check-r.md`, headings naming what the diff uses: "A `data-raw/` script must load the source tree, not the installed package"; "Postgres row order is never fixed unless the query fixes it…"; "A database driver's value is not a base R type"; "`paste()` with a zero-length argument returns length ONE"; "`on.exit()` at a script's top level never fires"; "Rscript reads a script as it runs…"; "An `information_schema` lookup by the literal table name misses what Postgres resolves".
- `code-check-shell.md`: "A failed `cd` lets every later command run in the directory you were already in"; "`if ! cmd; then rc=$?`…"; "Parallel writers sharing one output file"; "Empty arrays under `set -u` on bash 3.2".

## The mechanism behind round 1, and behind this round

Round 1's defects share one assumption: **a sentence about an artifact was written from a stand-in for the artifact instead of from the artifact.** The stand-ins were the plan or the expected result ("share few segments", the segment-fall causes), a script's comment or a neighbouring build (MURT's provenance, the run's commit), a label (`_362`/`_361`), and a pin printed by the driver (the reference version). Each fix then corrected the flagged sentence and left the other places that state the same fact. This round finds both halves again:

- The round-1 fix "the reference version changed" took the driver's printed pin as a reading of `fresh.streams_vw_bcfp`. The pin is the newest m1 row of `bcfp_baselines.csv`, and that row is a CSV sync, not a view load (finding 1).
- The MURT fix landed in the README, not in the `run.sh` and `compare.R` headers that state the same thing (finding 6). The rounding caveat landed beside a count it undermines, and the count was left as it was (finding 4). The header moved to `Verified: 2026-11-02` and "the current record", but "What is not yet explained" kept the v0.68.0 numbers (finding 2).
- The causal attribution of the round-1 "segment-fall causes" reappears in the rearing bullet (finding 3).

## Findings

- **[bug]** `research/bcfishpass_parity.md:54-56`, `data-raw/logs/parity_0.78.0/README.md:16`, `data-raw/logs/parity_0.78.0/expected.txt:17`: "The reference build did change, from `v0.7.15-50-g620dbe4` to `v0.7.15-51-g3bd2824` (`run.log`), whose change codes steelhead … `mapping_code_moves.csv` may carry it". The evidence does not support this, and the ledger points the other way. `run.log`'s "bcfp reference pinned at …" comes from `.lnk_bcfp_log_ledger()` (`study_area_run.sh:1219-1228`, `R/lnk_log.R:1266-`), which returns the newest row for the host in the committed `data-raw/logs/bcfp_baselines.csv`, of whatever kind. At `34c4c598` that row is `2026-10-31 12:21,m1,csv-sync-20261031,…,v0.7.15-51-g3bd2824,…,auto-append by csv-sync`. It was written by `sync_bcfishpass_csvs.R:317` when #429's CSV sync ran on m1, and a CSV sync does not reload `fresh.streams_vw_bcfp`. The newest m1 row that did load the views is `2026-10-23 00:52` (PDT, which is 07:52 UTC: the provincial run's `--refresh-primitives`, `snapshot_bcfp.sh --with-bcfp-views --force`, `study_area_run.sh:1561-1566`) at `-50-g620dbe4`. The run's own vintage gate puts the primitive load at 10 days old, the same load. So the view `fresh_parity441` was scored against is, on the evidence in the repo, the same `-50` load `fresh_parity361` was scored against, and the "0 of 50 pairs moved" follows from that. The same proxy also wrote `bcfp_model_version = v0.7.15-51-g3bd2824` into all 17 `fresh_parity441.log` rows (`run_verify.log` §2), so the database repeats the wrong provenance. That is pre-existing code: tier 2 does not filter to snapshot rows. Remedy: state that the reference view is the 2026-10-23 load at `-50`, and that the `-51` pin is the 2026-10-31 csv-sync row; drop "whose change codes steelhead" and "may carry it"; file the ledger-tier defect (filter `run_label` to `snapshot-*`, or have the CSV sync not stamp a reference row).
  - **Rule:** code-check.md "A proxy is not the property"; code-check.md "Verification that reads its own output"

- **[bug]** `research/bcfishpass_parity.md:134-148` ("What is not yet explained"): the file's header now says `Verified: 2026-11-02` and that it is the current record (lines 3, 9), but this section still says "five pairs are UNEXPLAINED", with v0.68.0 values (ELKR WCT spawning +3.33 %, rearing +2.50 %, BABL ST −2.05 %, BABL CH −2.44 %). At v0.78.0 `parity_annotated.csv` has 2 UNEXPLAINED (BULK SK rearing, ELKR WCT spawning +2.72 %) and one class C, and `parity_crosssection.log` line 1 says "(2 UNEXPLAINED)". BABL ST, BABL CH and ELKR WCT rearing are now `WITHIN_TOLERANCE` (`pair_moves.csv`, `class_0.78.0`). "The same five as on 2026-10-17" is no longer true.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"; code-check.md "Written data outlives the fix"

- **[bug]** `research/bcfishpass_parity.md:59-62`: "On segments both builds share the gain is already there … so it is a rule, not where streams break … and the only change in the range that adds rearing here". Neither inference follows from `segment_diff.csv`. Rearing on a shared segment (same start, same length) can still flip because of where streams break elsewhere: `cluster_rearing` joins or cuts rearing clusters through neighbouring segments, and #324 recorded exactly that ("the flips join or cut rearing clusters", `research/bcfp_segmentation_parity.md`). 17,527 of the four groups' lines are re-broken here. "The only change in the range that adds rearing" has no enumeration behind it. Nothing in the evidence ties the gained segments to `rear_stream_order_bypass` (stream order, parent order or width on the gained segments). This is the attribution class round 1 removed from the test-build README ("segment-fall causes stated as measured"), back one section over. Remedy: say the order-1 exception is the expected cause and that it is not measured, or measure it: the stream order and parent order of the gained rearing segments in `fresh_parity441`.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (an unmeasured justification, the third state)

- **[fragile]** `research/bcfishpass_parity.md:56` and `:66`: "40 of the 50 pairs moved by 0.1 km or more, all 17 accessible pairs among them" and "Accessible km fell 0.1 to 2.1 km a pair". These count differences of totals rounded to 0.1 km, and the caveat added in round 1 (line 70) says such a difference "can read 0.1 for a move of 0.01 km". It names ADMS BT accessible, the one pair at exactly −0.1, whose measured move on shared segments is 0.064 km. So the count is 39 or 40, and "all 17 accessible" may be 16. The caveat was added and the count it qualifies was left as it was.
  - **Rule:** code-check.md "One fact derived twice"

- **[fragile]** `research/bcfishpass_parity.md:58-59`: "toward the reference for every pair but BULK CO, which crossed it". BULK CH (−0.46 % → +0.22 %) and BULK ST (−0.50 % → +0.03 %) also crossed the reference. What sets BULK CO apart is that it ended farther away (3.3 → 8.5 km), not that it crossed. Remedy: "… but BULK CO, which crossed it and ended farther away (BULK CH and ST also crossed, and ended closer)".
  - **Rule:** none

- **[fragile]** `data-raw/logs/test_builds_440/run.sh:4-5` and `data-raw/logs/test_builds_440/compare.R:3`: both headers still say `zz432_post` is "the same groups at fresh 0.52.0, link a6942b5d" and "its last build at fresh 0.52.0". Round 1 corrected the README: MURT's newest row there is `2774f5b2` at fresh 0.48.0 (`zz432_post.log`, `432_murt`, confirmed). Also `data-raw/logs/parity_0.78.0/moves.R:3,37-38`: "unlike that one it does not assume a fixed bcfishpass reference" and "The reference is NOT fixed between these two builds: the provincial run of 2026-10-23 reloaded the bcfishpass views". That was copied from `parity_0.68.0/moves.R`, where it was true. For this pair both builds post-date that reload, so the stated reason does not apply.
  - **Rule:** code-check.md "A fix lands in one of two callers that share a harness"

- **[fragile]** `data-raw/logs/test_builds_440/README.md:15` ("m1 `fresh_default`, 2026-10-23, link 0.68.0, fresh 0.42.0"): no committed evidence states the provenance of the four groups' rows in m1's `fresh_default`. `summary.R` writes counts and km and reads no `log` row, and `summary_m1_fresh_default.csv` has no SHA, version or date column. Whether BULK, KETL, KOTL and MURT there are still the 2026-10-23 build (not a later single-group re-model) cannot be checked from the repo. Remedy: have `summary.R` add each group's newest `log` row (`date_end`, `link_sha`, `fresh_version`, `run_uid`) and re-run it on m1.
  - **Rule:** code-check.md "A guard that fails toward pass" ("Provenance, and repair")

- **[fragile]** `research/bcfishpass_parity.md:52-54` and `parity_0.78.0/README.md:21-22`: "Inputs were held equal in value … so every move is code". The evidence for "the same primitive load" is the vintage gate's load stamps, which cover four primitives (bcfishobs, cabd, crossings, PSCIS). FWA and discharge are not covered, and `fwapg_sha` differs between the builds (`6d48dabf` at v0.68.0, `83365223` now; a checkout HEAD, not a data version, so it neither confirms nor refutes). `log_input` fingerprints, which CLAUDE.md names as the way to tell whether two builds read the same FWA data, were not compared. Plausible but unsourced. Remedy: compare `fresh_parity361.log_input` with `fresh_parity441.log_input` on m1, or narrow the claim to the four stamped primitives.
  - **Rule:** code-check.md "A proxy is not the property"

- **[fragile]** `parity_0.78.0/README.md:23` and `research/bcfishpass_parity.md:71`: "`expected.txt` was committed before scoring". The commit time is 09:24:51Z (`7c36b882`), but nothing records when `parity_crosssection.R` ran: its log has no timestamp, and the driver's compare (09:22:54Z) is a different step. The pre-registration rests on a time the evidence does not hold. Remedy: cite the score's start time from m1's shell history or file mtime, or say it is unrecorded.
  - **Rule:** code-check.md "Verification that reads its own output"

## Enumeration

Every number, quantifier, causal attribution and provenance statement in the named files and sections. ✓ = holds against the cited source; ✗ = contradicted; ? = no checkable source; ~ = holds with the qualification noted.

### `data-raw/logs/test_builds_440/README.md`

| claim | source | verdict |
|---|---|---|
| 2026-11-02, m4, link 0.78.0, fresh 0.52.0 | `zz440_default.log`, `log_recompute` | ✓ |
| "the code PR #443 pins" | `R/`, `inst/`, `DESCRIPTION` identical `34c4c598`..`7c36b882` | ✓ |
| KETL built at `4069fdfc` | `zz440_default.log` | ✓ |
| KOTL, BULK, MURT and all four recomputes logged `7c36b882` | `log`, `log_recompute` | ✓ |
| because `expected.txt` was committed while `run.sh` modelled (commit 09:24:51Z; KETL start 09:24:19, KOTL 09:26:43) | git, log | ✓ |
| `run.sh` checks the tree only at start | `run.sh:11` | ✓ |
| `R/` identical between the two | `git diff --stat 4069fdfc 7c36b882` (expected.txt only) | ✓ |
| every row clean | `link_dirty`/`fresh_dirty` f on 4 + 4 rows | ✓ |
| MURT: only paused species present | presence CSV: MURT `rb` only | ✓ |
| KOTL recompute exit 1, `BLOCKED (link#227)` | `status.tsv`, `recompute_KOTL.log` | ✓ |
| its dam lies in a group this schema does not hold | log: LARL, Grand Coulee | ✓ |
| check runs after the recompute's work has committed | `wsg_recompute_one.R:178-213` | ✓ |
| as in `minimal_breaks_415/run.sh`'s pass rule | that file, lines 13, 81-82 | ✓ |
| `compare.R` copied, output path changed | diff with original | ~ the argument handling also changed (round 1) |
| identical (segments, breaks, barriers, overrides, km) | `summary.csv`, `km.csv` (all 0) | ✓ |
| "the segment under each fish record" in all four groups | `obs.csv` | ~ MURT has 0 records (modelled + DV only), so vacuous there; covered anyway by identical breaks |
| BULK, KETL, KOTL in `zz432_post` are `a6942b5d`, fresh 0.52.0 | `zz432_post.log` | ✓ |
| MURT newest is `2774f5b2`, fresh 0.48.0 | `zz432_post.log` (`432_murt`) | ✓ (`run.sh`/`compare.R` headers not updated: finding 6) |
| provincial build 2026-10-23, 0.68.0, 0.42.0 | none committed | ? finding 7 |
| table: 87,640/42,458; 102,101/41,394; 109,951/38,287; 37,569/14,403 segments | summary CSVs | ✓ |
| table: barrier rows 60,990/61,005; 81,149/81,174; 92,588/92,628; 25,742/25,765 | summary CSVs | ✓ |
| segments fall 2.1- to 2.9-fold | 2.06, 2.47, 2.87, 2.61 | ✓ (2.06 rounds to 2.1) |
| #433 measured 0.2 to 6.0 % | CLAUDE.md #432 status | ✓ |
| causes #326, #396, #432 "not decomposed" | — | ✓ stated as attributed (accepted) |
| KO and RB have no habitat or access | summary: 0 km, 0 habitat rows | ✓ |
| MURT built, with no habitat | summary | ✓ |
| BULK chum 5,164 km accessible, 1,862 km spawning | summary: 5164.47, 1861.83 | ✓ |
| chum from #402 | presence CSV note | ✓ |
| barrier rows rise 15 to 40 per group | +15, +25, +40, +23 | ✓ |
| "the scale #326 restored (4 to 31 lost)" | CLAUDE.md #326 | ~ attributed, 40 > 31 (accepted class) |
| accessible 0.0 to 0.3 % | max 0.27 % (KOTL WCT) | ✓ |
| spawning and rearing under 1 % | max 0.97 % (KOTL WCT spawning), 0.96 % (KETL WCT rearing) | ✓ (close) |
| KOTL BT rearing 2,179 to 2,167 | 2179.27 → 2166.69 | ✓ |
| KETL WCT spawning 1,387 to 1,377 | 1386.80 → 1377.10 | ✓ |

### `data-raw/logs/parity_0.78.0/README.md`

| claim | source | verdict |
|---|---|---|
| 17-group closure, scratch `fresh_parity441`, m1 | `run.log` | ✓ |
| compared with `fresh_parity361` | `moves.R` | ✓ |
| run_uid, label, dispatcher only | `run.log` | ✓ |
| worktree at `34c4c598` | `run_verify.log` §2, log dir `link-441` | ✓ |
| 08:32 → 09:22, critical path 50.0 min | `run.log` phases | ✓ |
| link 0.78.0 `34c4c598`, PR #443's head | DESCRIPTION; `gh pr view 443` head `34c4c598` | ✓ |
| fresh 0.52.0 `245c8d8d` | `run_verify.log` | ✓ (install route: operator, accepted) |
| primitives are the 2026-10-23 load | vintage gate 10 d, load stamp | ✓ for 4 primitives; ? FWA (finding 8) |
| `--preflight-note` recorded it | `run.log` OVERRIDE line | ✓ |
| reference pinned at `-51` | `run.log` | ✗ as a statement about the view: the pin is a csv-sync ledger row (finding 1) |
| `fresh_parity361` scored at `-50` | `parity_0.68.0` | ✓ |
| no scored value moved | `pair_moves.csv` | ✓ |
| `--pretest-note` | `run.log` | ✓ |
| 48/50 PASS | `parity_crosssection.log` | ✓ |
| `run_verify.log` PASS | log | ✓ |
| reference moved on 0 of 50 | `moves.log` | ✓ |
| no override added or lost | `override_diff.csv`, 4750/4750 | ✓ |
| so every move is code | — | ? finding 8 |
| `expected.txt` committed before scoring | commit time only | ? finding 9 |
| three of four bounds wrong | `expected.txt` vs `pair_moves.csv` | ✓ |
| 17,527 lines re-broken | `moves.log` | ✓ |

### `research/bcfishpass_parity.md` (the named sections)

| claim | source | verdict |
|---|---|---|
| header: run, link `34c4c598`, fresh 0.52.0 | `run_verify.log` | ✓ |
| 48 of 50; BULK SK +10.99 / +7.39 | annotated | ✓ |
| accessible within 0.11 % on all 17 | annotated, max −0.11 | ✓ |
| table: 17 rows × 3 cells, brackets ≥ 0.1 | rebuilt from `pair_moves.csv` by script | ✓ 0 mismatches |
| five pairs left out (CM/PK) | `parity_crosssection.log` | ✓ |
| The build: m1, worktree, verify PASS, reference 0 of 50 | logs | ✓ |
| v0.68.0 score 48/50 | parity_0.68.0 | ✓ |
| inputs held equal in value | — | ? finding 8 |
| reference build changed to `-51`, codes steelhead, may carry | ledger | ✗ finding 1 |
| 40 of 50 moved ≥ 0.1, all 17 accessible | rounded totals | ~ finding 4 |
| rearing rose in BULK/BABL BT CH CO ST, 4.6 to 23.3 | `pair_moves.csv` | ✓ |
| toward the reference but BULK CO, "which crossed it" | `pair_moves.csv` | ~ finding 5 |
| −0.14 % to +0.38 % | csv | ✓ |
| BULK BT +22.1 of +21.4 on shared segments | `segment_diff.csv` 28.514 − 6.406 − 0.011 | ✓ |
| "so it is a rule, not where streams break"; "only change that adds rearing" | — | ✗/? finding 3 |
| spawning fell toward ref: ADMS BT −4.5, ELKR BT −8.2, ELKR WCT −9.1 | csv | ✓ |
| spawning changed on 0 km of shared segments | `segment_diff.csv` | ✓ |
| every spawning move on re-broken lines | `resegmented_habitat.csv` (−4.445, −8.243, −9.142, −1.065, −2.661, +0.279) | ✓ |
| "#326's segmentation" | — | ~ attributed |
| ELKR WCT rearing −15.5, toward | csv | ✓ |
| accessible fell 0.1 to 2.1, within 0.11 % | csv | ~ lower end, finding 4 |
| eight pairs moved away; BULK CO 3.3 → 8.5; seven by 0.2 to 2.1; ELKR WCT accessible 1.8 → 3.9 | computed | ✓ |
| ADMS BT accessible 0.064 km on shared segments | `segment_diff.csv` | ✓ |
| 95,106 of 129,329 shared | `moves.log`; 129,329 − 34,223 | ✓ |
| `expected.txt` wrong on 3 of 4 | csv | ✓ |
| bounds leaned on #326 on other groups | `expected.txt` | ✓ |
| `default` paragraph: match exactly; moves line up, not checked row by row | test_builds | ✓ (hedged) |
| Re-scoring: today `fresh_parity441`, `fresh_parity361` before | on m1 | ? not checkable from m4 (not raised) |
| History row: 2026-11-02, `34c4c598`, 48/50 | logs | ✓ |
| (outside the named sections) "What is not yet explained": five UNEXPLAINED | annotated: 2 | ✗ finding 2 |

## Code checked and clean

`moves.R` (merge guard, shared-segment arithmetic, temp table in place of `VALUES`, `blue_line_key` fits int4), `compare.R` (required arguments, `EXCEPT` row diffs, piece join), `summary.R` (`integer64` coercion, schema regex), `run.sh` (`cd … && …` in a subshell, rc per step, no `set -e` traps). No functional defect found in them; the round-1 fix to `compare.R`'s defaults holds.
