# Task: Re-score bcfishpass parity at v0.66.6 and keep one current parity record in research/ (#362)

## Problem

- **The baseline predates #349.** Parity was last scored on 2026-10-17 (run `20261017_093603-31ab6242`, the 17-group closure of ADMS, BULK, BABL and ELKR, built into `fresh_parity246`), at 48/50 within tolerance; BULK SK is over and parked (fresh#190, carried on as #130). v0.66.6 changes the persisted habitat flags and the barrier lifts in every config.
- **What to expect.** On `fresh_parity246`, the segments the gate would settle carry 0 km of spawning in every scored pair and at most 0.6 km of rearing (BT: BULK 0.3, BABL 0.3, ELKR 0.6), and accessible km already sits within 0.07 % (`research/access_columns.md`, "What it should do to bcfishpass parity"). So the four groups check for regression and cannot show a gain. Province-wide lift counting matters only behind a barrier held in another group, and none of the four has one. TURN BT is the candidate that would show it: a UKEC barrier with 69 BT records upstream province-wide and none inside UKEC.
- **No research file says where parity stands.** Results sit in five dated files (`provincial_parity_2026_05_01/_11/_12/_25.md`, `parity_accessible_habitat_2026_07_03.md`). The newest, 2026-10-17, is in none of them: it is in `data-raw/logs/provincial_246/`, one bullet of `research/study_area_run.md` and `CLAUDE.md`. #279 asked for a topic file a parity run revises in place, and it was never created.

## Found during exploration (shapes the plan)

- **TURN BT cannot be scored: bcfishpass does not model TURN or UKEC.** Over the tunnel
  (bcfishpass run 143, `v0.7.15-50-g620dbe43`, same build as the local reference),
  `bcfishpass.streams` has **0 rows** for TURN and UKEC, and the local `fresh.streams_vw_bcfp`
  (188 groups) holds neither. So Phase 3 of the issue is answered now, read-only: record the reason.
- **No other bcfishpass-scorable case exists in #349's list.** Of the 78 rows of
  `data-raw/logs/access_disagree_349/groups_blocked.csv` (mechanism B), the only one for a species
  the `bcfishpass` config models is BT TURN; the rest are RB (61), KO (9), GR (7). Caveat to state:
  that list was built under `default`'s presence and thresholds.
- **Reference is unchanged and pinned.** Local `fresh.streams_vw_bcfp` was loaded by
  `snapshot_bcfp.sh --with-bcfp-views` on 2026-10-17 00:55 UTC (`bcfp_baselines.csv`: bcfp
  `v0.7.15-50-g620dbe4`, completed 2026-10-14 03:00 UTC). The driver touches it only with
  `--refresh-primitives` (default off), so no flag needed to keep it.
- **Vintage window.** Primitives are stamped 2026-10-17 00:46 UTC; the driver's 7-day gate
  expires **Thu 2026-10-23 5:46 PM PDT**. Launch before then. After it, use
  `--preflight-note="same inputs as the 2026-10-17 baseline, #362"`, never a refresh (a refresh
  moves the inputs and the comparison stops isolating code).
- **Cost.** The 2026-10-17 model leg ran 09:36-10:30 UTC, about 1 h on the dispatcher alone
  (`fresh_parity246.log`; corrected from "~7 h", which read a checkout's file mtimes, review finding 5). `fresh_parity246` is 3.9 GB; the DB volume has 196 G free.
- Tools reused as they are: `data-raw/study_area_run.sh` (`--focal`, `--config`, `--schema`,
  `--run-label`; no `--cy-workspaces` = dispatcher only), `data-raw/parity_crosssection.R`
  (`LNK_SCHEMA`, `LNK_CONFIG`, `LNK_PARITY_OUT`), `data-raw/study_area_verify.sql`.

## Decided at the gate (approved by the operator 2026-10-20: "go all phases to pr")

1. **Build into a new scratch schema `fresh_parity362`**, keeping `fresh_parity246` beside it so
   every pair's move can be explained segment by segment. Dropping either is the operator's call
   afterwards (listed under Owed).
2. **TURN: record the reason, build nothing.** No other candidate is built; the parity file says
   that province-wide lift counting has no bcfishpass-scorable case today.
3. **Run on the feature branch** (the driver requires it pushed and clean), detached
   (`nohup … & disown`, per `research/study_area_run.md`), with nothing in the repo touched until it ends.

## Phase 1: Run the rebuild (`bcfishpass`, 17-group closure, v0.66.6)

- [x] Push the baseline branch; `bash data-raw/study_area_run.sh --preflight-only --config=bcfishpass --schema=fresh_parity362` clean
- [x] State the run decisions (config `bcfishpass`, schema `fresh_parity362`, closure = the same 17 groups, species from config × presence, no `--refresh-primitives`, `--recompute-jobs=8`) and launch detached:
      `bash data-raw/study_area_run.sh --focal=ADMS,BULK,BABL,ELKR --config=bcfishpass --schema=fresh_parity362 --run-label=parity-4-bcfishpass-362 --recompute-jobs=8`
- [x] Confirm the resolved closure equals 2026-10-17's 17 groups (log line `dispatcher (focal=…)`)
- [x] Wait on a marker only this run's end writes; then `study_area_verify.sql` with `-v schema=fresh_parity362 -v run_uid=<uid> -v expected_n=17` (the schema flag added on review finding 2): PASS
- [x] Stamp the run in `data-raw/logs/parity_0.66.6/README.md` (run_uid, link SHA, fresh SHA, fwapg / bcfishobs SHAs, bcfp build + model_run_id), referencing the driver's `study_area_run/20261020_171738_*` logs rather than copying them (review finding 8)

## Phase 2: Score and explain every move

- [x] `LNK_LOAD=loadall LNK_SCHEMA=fresh_parity362 LNK_CONFIG=bcfishpass LNK_PARITY_OUT=data-raw/logs/parity_0.66.6/parity_annotated.csv Rscript data-raw/parity_crosssection.R ADMS BULK BABL ELKR` → `parity_crosssection.log`
- [x] `pair_moves.csv`: every pair joined to `provincial_246/parity_annotated.csv` (link value, bcfp value, diff_pct before / after, km change)
- [x] For any pair moving beyond rounding (0.1 km): a segment diff `fresh_parity246` vs `fresh_parity362` on the full key, classed as gate settle (`access_<sp>` = 0) / lift change / other; the SQL committed beside the logs (`moves.R`, plus an override-position diff and the 17-group mapping_code compare, review findings 1 and 3; segments in one build only reported separately, `resegmented.csv`)
- [x] An unexplained move is filed as an issue (body reviewed first), not left in prose: none unexplained; ADMS CH is a measured instance of #277, added to its body

## Phase 3: TURN BT

- [x] Record the tunnel and local evidence (0 TURN / UKEC rows in bcfishpass run 143; `groups_blocked.csv` intersection) in `data-raw/logs/parity_0.66.6/turn_bt.txt`

## Phase 4: One parity record

- [ ] Create `research/bcfishpass_parity.md`: provenance line; current result table (50 pairs); what moved since 2026-10-17 and why; the five annotated UNEXPLAINED rows carried forward; TURN; the dated files listed as history (not renamed)
- [ ] `research/README.md`: list it first under "Methodology and parity" as the current parity record
- [ ] `CLAUDE.md` status: replace the "parity was not run on this change" bullet with the result and a pointer; `research/study_area_run.md`'s parity bullet points at the new file
- [ ] `research/access_columns.md` "What it should do to bcfishpass parity": add the measured result

## Owed at the end (reported, done after merge)

- [ ] Operator: drop `fresh_parity246` and/or `fresh_parity362` (3.9 GB each) once the record is merged

## Validation

- [ ] Tests pass (no R code changes expected; run only if any `R/` file changes)
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: `study_area_verify.sql` passes at `expected_n=17` for the run_uid; the parity script
exits 0 (or every failing pair is explained); `pair_moves.csv` has 50 rows and each move > 0.1 km
has a segment-diff class; every number in `bcfishpass_parity.md` traces to a file under
`data-raw/logs/parity_0.66.6/` or `provincial_246/`.

