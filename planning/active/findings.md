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
