# Plan review — #259 (Plan agent, 2026-10-28 UTC)

Findings as returned (condensed), each with its disposition.

| # | kind | finding | disposition |
|---|---|---|---|
| 1 | Blocker | Speeds can't be fitted from a run's own minutes: a host packed on minutes it measured predicts itself, so its correction is ≈ 1 whatever its speed. Only groups that moved host carry information, mixed with drift. | **Accepted, and it changes the seed.** Phase 1: 160 of 163 cloud groups and 71 of 78 m1 groups stayed on their class, so the 10-23 "seed" (cloud 0.964) is mostly the two classes' different drift (1.159 vs 1.130). Seed the state equal. The calibrator still works: with weights normalized by the current speed estimate, a group that stays predicts itself (neutral), and a group that moves predicts with the estimated ratio, so the estimate's error drives a damped correction. A simulation test proves it converges. |
| 2 | Assumption | Nothing fixes the scale: run-wide drift is booked as host speed. | **Accepted.** Each correction is divided by the run's pooled correction (projected-weighted); the run-wide ratio is reported in the history separately. |
| 3 | Assumption | The `model` row is wall time (start-up, failed groups, stalls); the seed was in log minutes; failed groups keep their weight. | **Accepted.** Calibrate on the `model` row (whole leg, as #163 asks); groups not `recompute` in `<TS>_coverage.tsv` leave the projection; stalls are the operator's `--skip`. The seed is equal, so no unit mismatch. |
| 4 | Gap | The plan file is what the packer predicted, not what ran. | **Accepted.** `--plan-out` writes one row per group; the calibrator refuses when a host's groups differ from `<TS>_run_wsgs.tsv`. |
| 5 | Gap | A killed driver can leave two `model` rows per leg; `--recompute-only` has none. | **Accepted.** Later end wins; no model rows refuses. |
| 6 | Gap | Normalizing weights by learned speeds is a second loop. | **Considered; current state kept.** The current state is the best estimate of the true ratio; stayers are neutral under any estimate, movers' error drives the damped correction. The convergence simulation is the check. |
| 7 | Ordering | Golden check on the packer breaks once a state exists, and `buckets_default.md`'s minutes schema is now renamed and on m1. | **Accepted.** The golden is a pure `pack()` test on Phase 1's exported weights at equal speeds. |
| 8 | Assumption | The summary is `run_finish_report` in `study_area_finish.sh`. | **Accepted.** The command prints there, before the INCOMPLETE branch; test in `test-study_area_finish.R`. |
| 9 | Assumption | The packer's segment weight is FWA segments, which #326 does not change; the minutes-per-segment rate shifts instead. | **Accepted.** Research wording fixed. |
| 10 | Gap | A worker's own name would be committed in the state. | **Accepted.** Names come from `--host-names` (the operator's alias), never from a worker's self-name; the calibrator refuses a name with `@` or an address shape. |
| 11 | Gap | Segment-unit plans are never calibrated. | **Accepted.** Refused loudly; RUNBOOK says to pack with `--minutes-schema` for a run to calibrate. |
| 12 | Acceptance | No pre-set threshold; rationale "where #246's is"; no test that per-group means are not used. | **Partly.** Phase 1's numbers were seen before a threshold was set; said so in the research. Rationale goes in the packer's header comment and the research doc. The convergence simulation includes a per-group-means mutant that must fail. |
| 13 | Scope | Unnamed workers fall back to the median. | **Accepted.** The printed source column says `median (no learned speed)`. |
