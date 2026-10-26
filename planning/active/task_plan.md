# Task: Provincial run speed-up: one change at a time, measured (#377)

Cut the wall clock of a provincial `default` run without changing its outputs, one change at a time, measuring each. This branch takes the tracker's next item: tick #376 (shipped v0.68.5), then #260, measuring the per-job `pkgload::load_all()` in the recompute pool and changing the `LNK_LOAD` contract only if the cost is material.

## Context (from plan mode, 2026-10-25)

#377 is the provincial-speed tracker, and its rule is: check off the top unchecked item, and do the next one. Its top unchecked box is **#376** (persistent workers). That shipped in v0.68.5, with a small-run measurement (`data-raw/logs/worker_376/`), and its provincial numbers are owed, which is how #371, #375 and #369 were ticked. So it gets ticked, with a measured line, and **#260** becomes the work.

#260 asks: measure the fixed per-job cost of `pkgload::load_all()` in the recompute pool, and change the `LNK_LOAD` contract only if that cost is material.

**What exploration measured (plan mode, dispatcher, idle):**
- `load_all()` takes 0.9 s warm (2.1 s on the first, cold run). `library(link)` takes 0.3 s. `lnk_config()` takes 0.01 s and `lnk_load_overrides()` 0.2–0.3 s.
- In `wsg_recompute_one.R`, `t0` starts after the prologue, so the logged "recomputed in X min" leaves the prologue out.
- Run `20261023_074321`: 240 jobs, a median of 2.63 min, from 0.24 min to 22.76 min. They sum to 839 job-minutes, and 839 / 8 = 105 min against a 110 min phase. SALR took 0.72 min and CHWK 15.56 min.
- So the prologue is about 1.1 s per job: roughly 2.5 % of SALR, 0.1 % of CHWK, and under 1 % of the phase (about 0.5 min of wall clock at `-j8`). Switching to `library(link)` would save about 0.6 s per job, about 18 s of wall clock per provincial run.

**Expected verdict:** not material. Leave the `LNK_LOAD` contract alone. It is now shared by 13 scripts, not the five #260 names. Close #260 as measured. The plan confirms this properly first (cold starts, under `-j8` contention, with an environment stamp). If the confirmation disagrees with exploration, by more than 5 % of the phase, stop and bring options back rather than changing the contract.

## Decided at the gate (operator approved the plan, 2026-10-26)

- Tick #376 in #377 now, with its small-run measured line, and leave its provincial numbers owed. This is the same treatment #371, #375 and #369 got.
- #260 is measure-first, and the contract changes only if the cost is material (per #260's own Ask).
- No package code changes, so no version bump: the PR is evidence, research and issue text.

## Phase 1: Measure

- [x] Before each measurement, check the dispatcher is idle: `uptime`, plus `pg_stat_activity` for active non-idle backends. Record both. Another session's load has skewed runs before (CLAUDE.md, 2026-10-23 / 2026-10-25).
- [x] Write `data-raw/logs/loadall_260/measure.sh`, plus an R prologue script beside it. These time the job prologue stage by stage (`load_all`, `library(DBI/RPostgres)`, `lnk_config("default")`, `lnk_load_overrides()`) and `library(link)` for comparison, in three ways:
  - N = 20 sequential runs, each a fresh `Rscript`, keeping the first (cold) run apart;
  - 8 concurrent runs × 3 waves, the `-j8` shape, to catch contention;
  - with the link SHA, R version and installed-link version stamped in the output header.
- [x] Write `data-raw/logs/loadall_260/shares.R`. It reads per-group minutes from `data-raw/logs/study_area_run/20261023_074321_recompute.log` and works out the prologue's share for SALR, the median group, CHWK and the whole phase: 240 × prologue / 8 against 110 min. It also accounts for the remaining 105 → 110 min gap, reported as the in-run upper bound on every untimed per-job cost, the prologue included (plan review B1). *Revised:* the span and summed work come from `fresh_default.log_recompute` (`span.sql`), and the shares use both the in-run minutes and #260's isolated 11 s / 226 s (A2). A third condition runs the prologue beside 7 CPU-busy R processes (A3); `review-plan.md` has every disposition.
- [x] Commit the outputs (`timings.tsv`, `shares.txt`), redacted where needed: no host names.

## Phase 2: Record

- [ ] `data-raw/logs/loadall_260/README.md`: the question, the method, the numbers with units, the verdict, and what changed because of it (the contract stays).
- [ ] Revise `research/recompute_parallel_2026_09_01.md`, "Where the remaining time actually is", candidate 1, in place, with the measured verdict and a pointer to the evidence. Note that the 13 scripts sharing `LNK_LOAD` now outnumber the three it names. The file keeps its name.
- [ ] Check `research/README.md`'s row for that file still describes it.

## Phase 3: Issues and status

- [ ] Edit #260's body: add a Measured section, tick acceptance 1, mark 2 and 3 N/A (conditional on a change; review AC), fix its stale line reference, and give the decision, "not changed: X % of the phase".
- [ ] Edit #377's body:
  - tick #376 with its measured line (Run A from `worker_376`; provincial numbers owed);
  - tick #260 with its measured line;
  - leave #374 as the next item.
- [ ] Add a short CLAUDE.md status entry with the verdict and the one fact not to re-derive (`t0` is after the prologue, so the logged minutes leave it out).

## Owed at the end (reported, done after merge)

- [ ] Close #260 with the PR (`Fixes #260`) if the verdict holds. #377 stays open.
- [ ] #374 is the next tracker item and gets its own `/planning-init 374`.

## Validation

- [ ] `measure.sh` and `shares.R` re-run and reproduce the committed numbers.
- [ ] `/code-check branch` clean.
- [ ] Both issue bodies read back after editing (`gh issue view`), with the checkboxes as intended.
- [ ] PWF checkboxes match the landed work.
- [ ] `/planning-archive` on completion, then `/gh-pr-push`.

How each claim is proved: the prologue cost is timed directly, never estimated. The share uses logged job minutes, which leave the prologue out (verified by reading where `t0` is set). The phase total comes from the run's own log.
