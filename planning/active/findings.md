# Findings — Re-score bcfishpass parity at v0.66.6 (#362)

## Issue context

**If we do it:** we know whether #349 (habitat flags settled on `streams_access`, barrier lifts counted province-wide) moved link's `bcfishpass`-config output against bcfishpass, and one research file says where parity stands. **If we never do:** the 48/50 baseline describes code that no longer runs, and the next parity result lands in a seventh place.

## Problem

- **The baseline predates #349.** Parity was last scored on 2026-10-17 (run `20261017_093603-31ab6242`, the 17-group closure of ADMS, BULK, BABL and ELKR, built into `fresh_parity246`), at 48/50 within tolerance; BULK SK is over and parked (fresh#190, carried on as #130). v0.66.6 changes the persisted habitat flags and the barrier lifts in every config.
- **What to expect.** On `fresh_parity246`, the segments the gate would settle carry 0 km of spawning in every scored pair and at most 0.6 km of rearing (BT: BULK 0.3, BABL 0.3, ELKR 0.6), and accessible km already sits within 0.07 % (`research/access_columns.md`, "What it should do to bcfishpass parity"). So the four groups check for regression and cannot show a gain. Province-wide lift counting matters only behind a barrier held in another group, and none of the four has one. TURN BT is the candidate that would show it: a UKEC barrier with 69 BT records upstream province-wide and none inside UKEC.
- **No research file says where parity stands.** Results sit in five dated files (`provincial_parity_2026_05_01/_11/_12/_25.md`, `parity_accessible_habitat_2026_07_03.md`). The newest, 2026-10-17, is in none of them: it is in `data-raw/logs/provincial_246/`, one bullet of `research/study_area_run.md` and `CLAUDE.md`. #279 asked for a topic file a parity run revises in place, and it was never created.

## Proposal

1. **Same reference, so only our code moves.** Score against the local `fresh.streams_vw_bcfp` as loaded on 2026-10-16 (bcfishpass `v0.7.15-50-g620dbe4`, run 143, completed 2026-10-14 03:00 UTC; the newest build on 2026-10-20, and the one the 2026-10-17 score used). Do not refresh it in this run, even if a newer bcfishpass build has landed: that is a separate step.
2. **Rebuild and score at v0.66.6.** The same 17-group closure, `bcfishpass` config, into a scratch schema, recomputed, then `parity_crosssection.R` on ADMS, BULK, BABL and ELKR. Logs go to `data-raw/logs/parity_0.66.6/`, stamped with run_uid, link SHA and the bcfishpass build. Report each pair's move against 2026-10-17, not only pass or fail.
3. **TURN BT, if bcfishpass has it accessible.** Check on bcfishpass over the tunnel first (read only). If it does, build TURN's closure under `bcfishpass` and score TURN BT accessible km. This is the one measurement that can show #349 moving link toward bcfishpass.
4. **One topic file.** Create `research/bcfishpass_parity.md`: the current result table, what moved since the last score and why, and the dated files listed as history (not renamed; `CLAUDE.md` and issues cite their paths). Point `research/README.md` and `CLAUDE.md` at it.

## Not in scope

The rest of #279's tidy-up (overlapping comparison files, leftover hand-off notes): #279 keeps it.

## Acceptance

- Every scored pair reported with its 2026-10-17 value and the change; any change beyond rounding explained or filed.
- TURN BT scored, or the reason it was not (bcfishpass blocks it too) recorded.
- `research/bcfishpass_parity.md` exists and `research/README.md` lists it as the current parity record.

Relates to #349, #279, #246.

## Score at v0.66.6 (2026-10-20)

`parity_crosssection.R ADMS BULK BABL ELKR` on `fresh_parity362`: 48/50, PASS, the same pairs as
2026-10-17 (BULK SK spawning +11.0 % and rearing +7.4 %, parked). Annotation classes unchanged on
all 50 pairs (44 WITHIN_TOLERANCE, 1 C, 5 UNEXPLAINED, the same five). bcfp values identical on
every pair (`moves.R` asserts it).

Against `expected.txt`, written before scoring:

| metric | expected | measured (`pair_moves.csv`, 0.1 km) |
|---|---|---|
| accessible | 0.0 on all 17 | 0.0 on all 17 |
| spawning | 0.0 on all 17 | 0.0 on 14; ADMS SK −0.1, ELKR WCT −0.1 (gate, 0.011 / 0.022 km); ADMS CH +0.1 (#277) |
| rearing | BT −0.3 BULK, −0.3 BABL, −0.6 ELKR | exactly those (gate: 0.269 / 0.325 / 0.633 km); BABL CO −0.1, ELKR WCT −0.1 (gate, 0.030 / 0.041 km); ADMS CH +0.2 (#277) |

- **Gate settle** accounts for every move but ADMS CH (`segment_diff.csv`, cause `gate_settle`:
  access unchanged and 0, habitat cleared; after code-check round 1 the diff joins only segments
  with the same start and length, and the gate rows are then the only changes there). The expectation's "0 km of spawning" was 0 at the
  0.1 km reporting precision; the gate removes 0.002–0.030 km of spawning per pair.
- **ADMS CH (+0.1 spawning, +0.2 rearing) is #277, not #349.** A `MODELLED_CROSSINGS` barrier on
  blue_line_key 356333200 sits at 1,349 m, not 1,446 m. The new break cuts an 88 m piece at
  gradient 0.0441 that passes CH spawning where the old 167.5 m piece (0.0483) did not, and the
  reach rears: that line's CH rearing 0 → 167.5 m (an earlier draft gave 4,025.5 → 4,193.0 m,
  summed over four lines; corrected on code-check round 1). Crossing code changed
  only in a comment between the builds (`9a35cc7b`), inputs are one load, and the break-source
  observations stay AOI-scoped. 39 segments on 8 lines (ADMS, BULK, ELKR) are in one build only;
  7 moved breaks are persisted `MODELLED_CROSSINGS` barriers, 9–97 m apart, and the eighth line
  loses a break at modelled crossing 101833 that is a barrier in neither build
  (`resegmented.csv`). On those lines CH gains 0.088 km spawning and 0.167 km rearing
  (`resegmented_habitat.csv`). Code-check round 2: on all 8 lines a PSCIS crossing has two
  modelled crossings on one `linear_feature_id`, and the builds match it to different ones (the
  tie in `R/lnk_pipeline_pscis_build.R`'s pick, already named in CLAUDE.md's 2026-09-25 status);
  the 101833 line is the same tie. Scope: the four scored groups; `streams` counts also differ
  in BULL, KISP, KOTL, LARL, LFRA and LSKE, not examined. Added to #277's
  body as a measured instance; no new issue.
- **Lifts:** 10 override positions added, 0 lost (`override_diff.csv`): BT and WCT at five
  positions on blue_line_key 356570372 (the Columbia, 1,468–1,602 km), held by LARL. Accessible km
  in the four scored groups did not move, so none reaches a scored pair. Lifts can only be added
  under province-wide counting (review finding 1).
- **mapping_code** (`mapping_code_moves.csv`, all 17 groups): 51 of 86 rows move, by −0.06 to
  +0.05 points of match_pct; confounded by the gate, 91a968ab and the moved breaks (segment count
  differs on 50 of 86 rows, 10 of 17 groups); not diagnosed.

## TURN BT (2026-10-20)

Not scored: bcfishpass run 143 has 0 rows for TURN and UKEC in `bcfishpass.streams` and
`streams_vw` (188 groups), and the local reference holds neither. It is the only mechanism-B row
in `groups_blocked.csv` (built under `default`) for a species the `bcfishpass` config models.
Evidence: `data-raw/logs/parity_0.66.6/turn_bt.txt`.
