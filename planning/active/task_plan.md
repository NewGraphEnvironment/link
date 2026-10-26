# Task: study_area_run.sh: recompute each group as soon as its downstream groups are consolidated (#374)

## Problem

The post-consolidate recompute starts only after every host's leg has finished and every host is consolidated. On `20261023_074321-24d85e8c` it took 110 min at `-j8` over 240 groups, after a 42 min consolidate. The cloud legs had finished about four hours before the dispatcher's. So the recompute's whole cost lands on the critical path, even though most groups had their inputs on the dispatcher hours earlier.

## Decided at the gate

Approved by the operator at plan approval, 2026-10-26.

1. **Measure first, with a stop.** Phase 1 simulates the scheduler on 2026-10-23's recorded times. If it saves under 15 min of critical path, I stop after Phase 1, record the result on #374 and #377, and ask before building. (Same discipline as #260.)
2. **On by default, with an opt-out:** `--recompute-at-end` restores today's behaviour, which is also the comparison run in Phase 4. `--recompute-only` is unchanged.
3. **The dependency rule is whatever Phase 1 measures:** closure ∪ any group holding rows on the group's flow path, computed once per run from FWA, never from a guess.

## Context from plan-mode exploration

**What exploration found, which shapes the plan:**
- **What a recompute reads** (`wsg_recompute_one.R`): its own `streams` / `streams_access` / `streams_habitat_<sp>` rows; the persist schema's views `barriers_<sp>_access` and `barriers_{anthropogenic,pscis,dams}_unified`, over **all** groups' `barriers` and `barrier_overrides` (`R/lnk_barriers_views.R:174-245`); the downstream-dam guard. The walk in `lnk_access()` follows `fwa_downstream()` by position, not by group. The override anti-join matches on `blue_line_key` + measure across every group's overrides. Nothing visible reads upstream groups.
- **The gap in "downstream closure = dependency set":** a barrier on a line several groups share is persisted under each of them (Peace rows: FINA, LPCE, PCEA, UPCE). A sliver group can also hold segments on another group's main stem (MORR on the Bulkley). So a group's walk can cross barrier or override rows held by a group that is **not** in `frs_wsg_drainage()`'s closure. The rule has to be measured, not assumed.
- **Model and recompute views don't collide:** `lnk_pipeline_run()` builds its views in the working schema (`R/lnk_pipeline_run.R:258`), not the persist schema, so dispatcher modelling never takes the persist views' AccessExclusiveLock. Consolidate (`schema_consolidate.R` step 3.5/4) deletes and copies one bucket table by table, **not in one transaction**. So a group must never be recomputed while any group it reads is mid-copy. Everything else the two touch is row-scoped.
- **The saving is not obviously large.** #369 consolidates each cloud host only when its leg ends, and well-packed legs end close together (247 / 260 / 257 / 242 min on 2026-10-23 without the stalls). Cloud groups therefore land in three bursts near the end; only dispatcher groups land progressively. The pool is throughput-bound (104.6 min of work over 8 slots, #260). Whether enough work moves off the critical path is the first thing to measure.

## Phase 1: settle what a recompute reads and whether early recompute pays

- [x] Code reading: list every relation `wsg_recompute_one.R` reads and writes, and the lock each takes (`findings.md` table). Do the same for `schema_consolidate.R` and `lnk_pipeline_run()`'s persist writes. (Review B2: `lnk_persist_init()` replaces `streams_habitat_long_vw` per dispatcher group, which every recompute reads.)
- [x] `data-raw/recompute_deps.R`: three rules from FWA (outlet closure, segment owner, line-touch), compared over all groups. The closure misses dependencies in 150 of 241 groups; the line rule (complete by construction, review B1) contains the other two, 2,211 pairs, median 9 per group.
- [x] Digest test on scratch (review A2): re-model TOOD (and NATR) into `fresh_374d` with `LNK_HABITAT_GATE=0` over only its line-rule dependency rows, recompute it, and digest `streams_access`, `streams_mapping_code` and the gated habitat flags against the same build with every group present. Negative control: the same with only the closure rule's dependencies must differ (TOOD's FROG / LKEC / UKEC / ULRD are outside it, #361). Digests after rounding.
- [x] `data-raw/recompute_schedule_sim.R`: 2026-10-23 replayed at `-j8`. Line rule: the recompute ends 89.4 min sooner as recorded and 38.1 min sooner with the stalls removed (tail after the last landing 72.6 min against 110.7).
- [x] Database headroom (moved here from Phase 4, review O2): the same dispatcher groups modelled alone, beside a `-j8` recompute, and alone again (`headroom.sh`). Weigh the slowdown against the saving.
- [ ] Residual check for the separate control-asymmetry issue (review S1): non-owner barrier and override rows no owner matches, indexed, with the groups whose paths cross them.
- [ ] Evidence README in `data-raw/logs/recompute_early_374/`; edit #374's body (closure → line rule; acceptance restated as a tail). **Checkpoint (decision 1).**

## Phase 2: dependency map and readiness (pure, tested)

- [x] The driver runs `recompute_deps.R` (line rule, about 80 s) in the background during spin and prep, writing `${TS}_recompute_deps.tsv`; no leg is dispatched until it has succeeded (FATAL otherwise, like the backup).
- [x] New sourced lib `data-raw/study_area_recompute.sh` with `recompute_landed` and `recompute_ready`. A group has landed when every host whose bucket holds it has landed it: on the dispatcher, its newest `log` row is this `RUN_UID`'s with `date_end` set; on a remote host, the `${TS}_consolidate_state.tsv` row is `ok`. A group outside the run, or a SKIP, has always landed. Ready = landed itself, every dependency landed, not yet launched. **Fails closed** (review A1: an early recompute that reads too little cannot be undone): an unreadable state file, a failed poll or an unknown host means not landed.
- [x] `tests/testthat/test-study_area_recompute.R` with fixture state: overlapping buckets, a failed host, `in_flight` and `failed:*` consolidate rows, groups outside the run, SKIPs, a dispatcher group with an open log row, a failed poll. Each guard restored to its bug must go red.

## Phase 3: the scheduler in the driver

- [x] `lnk_persist_init()`: replace `streams_habitat_long_vw` only when absent or its species set differs (catalog first, as #369 did for indexes and columns), with a live test that a second init takes no lock on it (review B2).
- [x] In early mode, initialise the dispatcher persist on every run, not only with remote hosts (review G1); then the log tables, then `barriers_views_build.R`, then the backup (review G2). A failure is FATAL before dispatch. `--recompute-only` keeps its own build.
- [x] `recompute_scheduler`, a background process started before `legs_wait`: polls readiness every 30 s, launches ready groups longest-first (`recompute_order`) into `RECOMPUTE_JOBS` slots through `recompute_one` (`.rc` files as today). Its own error handling, not the driver's `set -e` (review G4); it exits when its parent has gone; on a final-set file (written tmp + mv) it launches the rest of that set, drains and exits.
- [x] `run_finish`: after coverage, write `COV_RECOMPUTE` as the final set, wait on the scheduler. If it died, run the groups of the final set with no `.rc` file in the existing pool. `run_finish_recompute` keeps the early `.rc` files and writes no second `views` row (review G3). `fanout_judge.R` over `COV_RECOMPUTE`; a group launched early but missing from it is named and the run exits non-zero.
- [x] The EXIT trap stops the scheduler launching and lets running jobs finish, as a killed pool does today (review G4). Phase rows: `views` before the legs; `recompute` from the first job's start to the last job's end, written by the scheduler as the legs write theirs (review G5).
- [x] Readiness audit as a run post-condition (review AC2): every recomputed group's `log_recompute.date_start` is after each dependency's landing (model `date_end`; consolidate `state_utc`).
- [x] `--recompute-at-end` flag, banner line, structural tests.

## Phase 4: prove it on the dispatcher and the worker

- [x] A small run on the dispatcher plus the persistent worker (no cloud spend), early recompute on, into scratch `fresh_374a`, with dependencies forced to land after their dependants (on the slower host, or `LNK_TEST_STALL_WSG`; review AC1). Repeat with `--recompute-at-end` into `fresh_374b`. Sample `pg_stat_activity` lock waits and statement timeouts throughout (review A3).
- [x] Acceptance: per-group digests (after rounding) of `streams_access`, `streams_mapping_code` and the gated habitat flags match between a and b; the readiness audit and `study_area_verify.sql` pass on both; the recompute tail (last job end minus the later of the last leg and the last consolidate; review AC3) is shorter in a than in b.

## Phase 5: record and release

- [x] RUNBOOK §8d: new subsection "A group is recomputed once what it reads is here (link#374)", covering the rule, readiness and locks. Reword the kept-host recovery text, which says "upstream of it", from the dependency rule (review S2).
- [ ] File the control-asymmetry issue (review S1), after showing its body.
- [x] Write a CLAUDE.md status, `research/study_area_run.md`, and #377's measured line (the provincial numbers still owed; #377 edited once the PR exists).
- [ ] NEWS and the version bump: by `/gh-pr-merge` at merge, as for #369, #375 and #376 (the `Release vX` commits land on main); the PR body carries the NEWS text.

## Owed at the end (reported, done after merge)

- [ ] The provincial `default` run's recompute row and critical path fill #377's runs row; #374 stays open for it.

## Validation

- [x] Tests pass (`devtools::test()`: 4,307 pass, 0 fail; `devtools::check()`: 0 errors, the 3 warnings and 4 notes pre-existing)
- [x] `/code-check branch`: 3 rounds (6 / 3 / 4 findings, all fixed), ended by enumeration (`review-enumeration.md`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: Phase 1 by the digest test with its negative control, the simulation and the A-B-A headroom benchmark; Phase 2 by fixture tests with each mutation restored (they must go red); Phase 3 by structural tests plus the Phase 4 run; acceptance by the a/b digests and `study_area_verify.sql` on both scratch schemas.
