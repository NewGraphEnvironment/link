## Outcome

Backlog move 2 (#470) as one release, 0.84.0. One record rule now decides which bcfishobs records count, as which species, for the observation cuts, code 2 and the barrier lifts. The alias codes (`SST`, `WST`, `ADV`, `ABT`, `CCT`, `ACT`, `CT/RB`, and `BT/DV`, `DV/BT` where DV pools into BT) are rows in `default`'s `species_pooling.csv` at a new `province` scope, and `pipeline: observation_record_date: lift_floor` holds salmon, steelhead, GR and KO records to the lift floor (#400, #398, #425). Every lift is published with the records behind it in `barrier_override_evidence` (#434). The `bcfishpass` bundle drops the cutthroat aliases, as bcfishpass's filter does, and takes its strict date test (#426). `default` lifts on 2 salmon records (#427). #236 is narrowed to multi-rule lifts and left open. Four code-check rounds found ten defects. Their shared mechanism was the record rule re-derived by each consumer, and twice a fix (the negative script's skip, then the lift harness) reproduced the defect one axis over. The harness that informed #427 rebuilt prepare's lift call by hand and twice left out an argument, so the operator decided on numbers that were too high (SQAM +22 lifts, corrected to +4). It now calls prepare's own step. The general lesson: a measurement that stands in for a pipeline step should call that step, not restate it.

## Measurement

- **bcfishpass drops CT alias records:** 0 of 2,004 alias keys appear in its upstream arrays in SQAM, LFRA and VICT, against 2,921 of 2,963 CT records.
- **The record rule alone** (eight `default` groups, three `bcfishpass` groups):
  - DV no longer lifts BT where the tracker does not pool it: LSKE 61 → 0 BT lifts and 216 km, KLUM 123 → 4 and 168 km, SQAM 160 → 13 and 254 km.
  - Pre-1990 salmon records stop making code 2: LSKE −1,172 km, KLUM −424, HOMA −366.
  - Aliases add code 2: FINA BT +18 km, HOMA ST +10.
  - `bcfishpass` access did not move.
  - Every changed piece is traced; one 1 m HOMA strip was traced by hand (an alias merged into CT's top).
- **#426** moves no lift in ten groups.
- **#427**, through prepare's own lift step: threshold 2 adds SQAM 4 lifts per salmon species (steelhead 24), LSKE 6 and HARR 8, none on a single record. Threshold 1 would add 55, 14 and 37, mostly on single records. The operator chose 2 on the first table, which was too high (SQAM 22, LSKE 7, HARR 9).

The verdict is in RUNBOOK §7, "The record rule", and `research/species_presence.md`.

## Evidence

`data-raw/logs/record_rule_470/` (its README indexes it); code-check rounds `review-round*.md` here.

## Owed

- Provincial re-model of `fresh_default` and `fresh` at `acc-v6` / `acc-bcfp-5` (operator's word), after the pre-run gate runs again (`R/` changed); the next provincial run is also the first full run of `study_area_verify_negative.sh` cases 6j to 6l.
- The export carrying `barrier_override_evidence` for knowledge#178 (move 5, #473)

Closed by: PR for branch `470-backlog-move-2-which-fish-records-count`
