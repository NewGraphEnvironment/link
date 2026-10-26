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

- [ ] Code reading: list every relation `wsg_recompute_one.R` reads and writes, and the lock each takes (`findings.md` table). Do the same for `schema_consolidate.R` and `lnk_pipeline_run()`'s persist writes.
- [ ] `data-raw/recompute_deps.R`: for each group, list the groups whose stream segments lie on its flow path below any of its own segments (shared lines and slivers included), and compare with `frs_wsg_drainage()`'s closure over the 241 groups. Output a TSV and a count of groups whose dependencies go beyond the closure.
- [ ] Digest test on a scratch schema (`fresh_374`): copy into it only the rows of three groups' dependency sets (a Peace shared-line group, a Fraser main-stem group, a Bulkley/MORR-sliver group), recompute each with `LNK_LOG=0`, and digest `streams_access`, `streams_mapping_code` and the gated habitat flags against `fresh_default`. Negative control: drop one dependency, and the digest must differ.
- [ ] `data-raw/recompute_schedule_sim.R`: from 2026-10-23's dispatcher `log.date_end`, the leg end times, per-host consolidate minutes and `log_recompute` minutes, simulate the recompute end at `-j8` two ways: (a) today with #369 (pool after the last consolidate), (b) early scheduling under the Phase 1 rule. Simulate both as-run and with the stalls removed.
- [ ] Evidence goes to `data-raw/logs/recompute_early_374/` with a README. **Checkpoint (decision 1).**

## Phase 2: dependency map and readiness (pure, tested)

- [ ] The driver writes `${TS}_recompute_deps.tsv` once at run start, before any spend (`recompute_deps.R`, timed).
- [ ] New sourced lib `data-raw/study_area_recompute.sh` with `recompute_ready`. A group has landed when every host whose bucket holds it has landed it: on the dispatcher, its newest `log` row is this `RUN_UID`'s with `date_end` set; on a remote host, the `${TS}_consolidate_state.tsv` row is `ok`. A group outside the run has always landed. Ready = landed itself, every dependency landed, not yet launched.
- [ ] `tests/testthat/test-study_area_recompute.R` with fixture state: overlapping buckets, a failed host, `in_flight` and `failed:*` consolidate rows, groups outside the run, a dispatcher group with an open log row.

## Phase 3: the scheduler in the driver

- [ ] Move the one-time log-table ensure and `barriers_views_build.R` to before the legs, right after the persist init. A view rebuild at the end would take an AccessExclusiveLock against jobs still running. `--recompute-only` keeps its own build.
- [ ] `recompute_scheduler`, a background process started before `legs_wait`. It polls readiness every 30 s and launches ready groups longest-first (`recompute_order`) into `RECOMPUTE_JOBS` slots through the existing `recompute_one`, which writes `.rc` files as today. When a final-set file appears, it launches the rest of that set, drains, and exits.
- [ ] `run_finish`: after coverage, write `COV_RECOMPUTE` as the final set, wait on the scheduler's pid, and run `fanout_judge.R` over `COV_RECOMPUTE`. A group launched early but missing from `COV_RECOMPUTE` is named and the run exits non-zero.
- [ ] The EXIT trap kills the scheduler and its jobs. The `views` phase row moves to before the legs; the `recompute` row runs from the first job's start to the last job's end.
- [ ] `--recompute-at-end` flag, banner line, and structural tests in `test-study_area_legs.R` / a new test file.

## Phase 4: prove it on the dispatcher and the worker

- [ ] Database headroom: model 3–4 dispatcher groups into a scratch schema alone, then again while a `-j8` recompute runs over another scratch schema. Set the width used while legs are running from the result (a separate cap if the slowdown is material).
- [ ] A small run on the dispatcher plus the persistent worker (no cloud spend): about 10 groups whose dependencies cross hosts, early recompute on, into scratch `fresh_374a`. Repeat with `--recompute-at-end` into `fresh_374b`. Sample `pg_stat_activity` lock waits throughout.
- [ ] Acceptance on that run: the last recompute job ends within (longest single job) of the last consolidate; per-group digests of `streams_access`, `streams_mapping_code` and the gated habitat flags match between a and b; `study_area_verify.sql` passes on both.

## Phase 5: record and release

- [ ] RUNBOOK §8d: new subsection "A group is recomputed once what it reads is here (link#374)", covering the rule, readiness and locks.
- [ ] Write a CLAUDE.md status, `research/study_area_run.md`, and #377's measured line (the provincial numbers still owed).
- [ ] NEWS and the version bump as the final commit.

## Owed at the end (reported, done after merge)

- [ ] The provincial `default` run's recompute row and critical path fill #377's runs row; #374 stays open for it.

## Validation

- [ ] Tests pass (`devtools::test()`, the legs / recompute shell tests)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: Phase 1 by the digest test with its negative control and the simulation; Phase 2 by fixture tests with each mutation restored (they must go red); Phase 3 by structural tests plus the Phase 4 run; acceptance by the a/b digests and `study_area_verify.sql` on both scratch schemas.
