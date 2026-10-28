# Task: Pack hosts from measured minutes: group weights and learned host speeds (folds in #163) (#259)

Packing estimates a host's finish time as **the sum of its groups' weights ÷ its speed**. Neither half has been checked against a run's measured leg times, and host speeds are typed by hand (#163 asks for them learned from each run).

## Context

`data-raw/study_area_buckets.R` predicts each host's finish as **sum of its groups' weights ÷ its speed**.
Weights are FWA segment count by default or newest measured minutes (`--minutes-schema=`, built in
v0.48.0); speeds are equal unless typed in `--host-speeds=`. Neither half has been checked against a
run's measured leg times: 2026-10-23 packed ~218 min per host and ran 247 / 260 / 257 (cloud) and 314
(m1, KTSU's 65 min stall included). #163 asks for speeds learned from each run, damped and clamped,
calibrated on whole-leg time against prediction (not per-group means, which feedback-loop).

Measured during exploration (read-only, m1's `fresh_default.log`, run `20261023_074321-24d85e8c`):
`m1` 74 groups / 314 min, `cypher-job1` 57 / 247, `cypher-job2` 68 / 260, `cypher-job3` 42 / 257.
`log.host` and `<TS>_stamps.tsv` carry host **names** (`m1`, `cypher-job1`); `<TS>_phases.tsv` carries
driver **keys** (`dispatcher`, `job1`, `worker1`). The 2026-10-23 run predates phases.tsv (#375).

Found while exploring: measured-minute weights carry the speed of whichever host measured them, so they
are not "dispatcher-equivalent" once speeds differ. Phase 1 measures whether that matters.

## Decided at the gate (operator, 2026-10-27)

- **Speed key:** by host name as `log.host` / stamps record it (`m1`, `m4`, a worker's own name);
  every cloud host (`cypher-job*`) pooled into one `cloud` class (same droplet size, three legs of
  evidence per run). Driver role keys are not used: the dispatcher moved m1 → m4.
- **Who calibrates:** a separate script, `data-raw/host_speeds_calibrate.R`; the driver's summary prints
  the exact command, and the operator runs it, so a stalled run is excluded by judgment.

## Phase 1: Measure — predicted against measured leg time (2026-10-17 → 2026-10-23)
- [x] Export per-group rows (wsg, host, run_uid, date_start, date_end, minutes) for both runs from m1's
      `fresh_default.log` and `fresh_default_20261017.log` (SQL on stdin over ssh, `bash -lc`), plus
      FWA segment counts per group, to `data-raw/logs/packing_259/` with the producer script
      `data-raw/logs/packing_259/fit.R` and a README index
- [x] Out-of-sample: fit on 10-17, predict 10-23's actual buckets (each group on its 10-23 log host).
      Weights: (a) FWA segments × 10-17 min-per-segment rate, (b) 10-17 raw minutes (what the run
      used), (c) 10-17 minutes normalized by the measuring class's fitted speed. Speeds: equal; fitted
      from 10-17 legs (cloud pooled), raw and one damped step. Report per-leg error, share error and
      makespan, with and without the stalls (KTSU, OKAN); report how many groups moved class (review #1)
- [x] Record the verdict + rationale in `research/study_area_run.md` ("How hosts are packed") and the
      packer's header comment (where #246's sits), including the #326 caveat as it applies to each
      weight (review #9) and that the numbers were seen before any threshold was set (review #12)

## Phase 2: Packing helpers, tested (pure functions, no DB)
- [x] New `data-raw/study_area_packing.R` (sourced by the packer, the calibrator and tests): `pack()`
      moved out of the packer unchanged; `host_class()` (`cypher-*` → `cloud`); speed resolution
      (`--host-speeds` > state file > equal; a host missing from the state takes the median of known
      factors and its source says `median (no learned speed)`); weight normalization by the measuring
      host's class at the current state; the calibration step
- [x] Calibration math, #163's with speed as throughput (larger = faster, so inverted): per class
      `correction = Σ actual / Σ projected` over its legs, divided by the run's pooled correction
      (projected-weighted; review #2), `observed = old / correction`, `new = 0.7·old + 0.3·observed`,
      clamped to `[0.5·old, 2·old]`; the run-wide ratio returned for the history
- [x] `tests/testthat/test-study_area_packing.R` (skip when `data-raw/` is absent): golden `pack()` on
      Phase 1's exported weights at equal speeds (review #7); precedence; median fill and its source
      label; damping and clamping fire; class pooling; drift removed; a convergence simulation
      (true speeds unequal, iterate pack → measure → calibrate, factors approach the truth), and a
      per-group-means mutant that must not (kept only if it is shown to fail; review #12).
      Restore-the-bug check on each guard

## Phase 3: The packer reads learned speeds and writes its plan
- [x] `study_area_buckets.R`: `--host-names=` in driver order (operator aliases; default: dispatcher =
      local short hostname, workers `worker1..N`, cloud hosts `cloud`); refuses a name with `@` or an
      address shape (review #10); speeds from the helper with each host's speed and source printed;
      measured-minute weights normalized by `log.host`'s class
- [x] `--plan-out=<tsv>`: one row per group (run order, wsg, host key, name, class, speed, speed
      source, weight unit, weight); a host's prediction is the sum of its rows' weight ÷ speed
- [x] Loud fallback pinned: a group with no weight takes the median and is counted (the rule since
      v0.48.0); zero weighted groups refuses

## Phase 4: Calibrator, state and audit log
- [ ] `data-raw/host_speeds_calibrate.R --plan=<plan.tsv> --phases=<TS>_phases.tsv
      [--skip=<name>:<reason>] [--dry-run]`: reads `<TS>_run_wsgs.tsv` and `<TS>_coverage.tsv` beside
      the phases file; refuses when a host's groups differ from the plan (review #4), a segment-unit
      plan (review #11), a phases file with no `model` rows (review #5); keeps the later `model` row
      per leg; drops groups not `recompute` in coverage from the projection; skips a host whose
      `account` row is not `ok` or that the operator names (review #3)
- [ ] State `data-raw/logs/host_speeds.tsv` (name, factor, last_updated, n_runs, source_run_uid);
      append-only `data-raw/logs/host_speeds_history.tsv` (run_uid, name, old, observed, damped,
      clamped, new, run_ratio, action incl. `skipped: <reason>`)
- [ ] Seed the state **equal** (m1 1, cloud 1), history row citing `packing_259/fit.R` (review #1:
      the 10-23 data cannot tell the classes apart)
- [ ] `run_finish_report` (`study_area_finish.sh`) prints the calibrate command before the
      INCOMPLETE branch; it runs nothing. Structural test in `test-study_area_finish.R` (review #8)
- [ ] RUNBOOK §8d: how speeds are learned, where the state lives, the precedence, the name rule, and
      that a run must pack on `--minutes-schema` to be calibrated (review #11)

## Owed at the end (reported, done after merge)
- [ ] On the next provincial run (#377's runs row): pack with `--plan-out`, run the calibrator, re-run
      `packing_259/fit.R` on post-#326 minutes, and close #163's acceptance (3 runs converging,
      idle time after the fastest cloud host < 10 min) over the runs that follow
- [ ] fresh#272's release changes the dispatcher's speed (recompute beside its leg); the damping
      absorbs it over later runs — note it on #377 when it lands


## Validation
- [ ] Tests pass (`devtools::test()`), lintr clean on touched files
- [ ] `/code-check branch` clean (three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion; PR closes #259 and #163

Verification: Phase 1's out-of-sample numbers are the evidence for the weight/speed choice; the packer's
default-flag output matches `buckets_default.md` (no regression); unit tests prove precedence, median
fill, damping, clamping and pooling, each guard proven to fire by restoring the bug; a calibrator
`--dry-run` against a synthetic phases.tsv shaped like the real one (`test-study_area_phases.R`'s
fixtures) writes the expected state and history rows.
