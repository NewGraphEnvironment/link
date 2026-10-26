# Findings — Provincial run speed-up: one change at a time, measured (#377)

## Issue context

## Goal

Cut the wall clock of a provincial `default` run without changing its outputs, one change at a time, measuring each. Check off the top unchecked item; the next one is the next to do.

**Where we start** (`20261023_074321-24d85e8c`, 241 groups, the dispatcher plus three cloud hosts, `-j8`):
- **Modelling:** cloud legs 247 / 260 / 257 min. The dispatcher's took 306 min, of which 64 were KTSU's stall. OKAN's 4 h stall in one statement is extra.
- **Consolidate:** 42 min, serial, after every leg.
- **Recompute:** 110 min.
- **Critical path without the stalls:** about 6.8 h.

Sources: `research/study_area_run.md` and `data-raw/logs/provincial_361/`.

## Order

Each item: what it cuts, what we expect, and what it measured (filled in once done).

- [x] **#371: bound each modelling statement** (PR #373, v0.68.2). Cuts the stall tail. Expected: a stall costs at most the bound (30 min), not hours. Measured: on the dispatcher, a stalled group was cancelled at a 2 min bound and named, and the run finished by `--recompute-only` (`data-raw/logs/statement_timeout_371/`). A full run at the default bound is still owed (#371 stays open for it).
- [x] **#375: the driver records phase times** (shipped as v0.68.3). Cuts nothing, but every later row reads from it. Expected: `<TS>_phases.tsv` on every run. Measured: on the dispatcher, a two-group run wrote one row per phase, with skipped rows for the phases it did not run. The `model` and `recompute` rows bracket the database's own `log` / `log_recompute` times to the second, and the summary prints the critical path, which was 2.2 min (`data-raw/logs/phases_375/`). The first run with cloud hosts is still owed, and it fills the runs row below (#375 stays open for it).
- [x] **#369: consolidate each cloud host when its leg finishes, then burn it** (PR #379, v0.68.4). Cuts consolidate on the critical path and idle cloud time. Expected: most of the 42 min, and about 17 idle host-hours. Measured: on three small runs with two cloud hosts, each host was consolidated within a minute of its leg ending and burned about half a minute later, 6.5 to 34.5 min before the dispatcher leg ended; the consolidate tail after the last leg was 0.0 min. Dispatcher groups that modelled during a copy ran at a median 1.11x their 2026-10-23 minutes, against 1.19x for the rest (`data-raw/logs/consolidate_on_finish_369/`). The provincial-scale numbers are still owed, and they fill the runs row below (#369 stays open for them).
- [ ] **#376: persistent worker hosts** (the fifth host). Cuts modelling. Expected: about 270 → 216 min (`data-raw/logs/provincial_361/buckets_group5.md`). Built alongside #369, since both rework the driver's host loop. Measured: —
- [ ] **#260: measure the per-job `load_all()` in the recompute.** Cuts recompute. Expected: unknown, so measure first and act only if it is material. Measured: —
- [ ] **#374: recompute each group once its downstream closure is consolidated.** Cuts the recompute on the critical path. Expected: most of the 110 min, overlapped with the slowest leg. Depends on #369. Measured: —
- [ ] **#261: why CHWK takes 20× SALR.** Cuts the recompute's slowest job, which bounds the pool. Measured: —
- [ ] **#259 / #163: pack hosts from measured minutes.** Cuts leg imbalance. Expected: small, since the estimate was about 218 min against 247–260 actual. Measured: —

## Iteration speed: partial runs between provincial runs

A rule change gets tried on a few groups many times before it meets the province. These items shorten that loop and stop a ten-hour run from being the first test. Same rule: check off the top unchecked one.

- [ ] **#372: a scoped pre-run gate.** It models the 2 or 3 groups that stress each rule changed since the last run, and refuses the launch on a failure or a slowdown. Cuts failed or stalled provincial runs: 2026-10-23 lost about five hours to two groups that no test group resembled. Measured: —
- [ ] **#274: recompute the run's groups plus those upstream of them, not every group.** Cuts the recompute of a partial run. Expected: unknown, so measure first; a full run still recomputes everything. Measured: —

## Decided separately (outputs change)

- **#326: break streams only where a present species' access changes.** About half the segments, so everything downstream of segmentation gets cheaper, but outputs move and parity has to be re-scored. It is not checked off here; it gets its own decision.

## Not levers for a full provincial run

- **`--recompute-jobs` past 8:** the database VM is the limit (`data-raw/logs/recompute_width_20261020/`).

## Runs

One row per provincial run, from `<TS>_phases.tsv` once that exists.

| run_uid | hosts | longest leg | consolidate on critical path | recompute | critical path | changes in it |
|---|---|---|---|---|---|---|
| `20261017_004619-3f4c713b` | 4 | 277 min | 46 min | 154 min (`-j4`) | — | baseline |
| `20261023_074321-24d85e8c` | 4 | 306 min (64 of them a stall) | 42 min | 110 min (`-j8`) | ~6.8 h without stalls | `-j8`, group atoms |

All issues here carry the `speed` label: `gh issue list --label speed`.






## Plan-mode probes (2026-10-25, dispatcher)

- load_all warm 0.88–0.96 s (3 runs); first prologue run 2.10 s; library(link) 0.31 s; lnk_config 0.01 s; lnk_load_overrides 0.16–0.33 s.
- 20261023_074321 recompute.log: 240 'recomputed in X min' lines, median 2.63, min 0.24, max 22.76, sum 839.2 job-min; SALR 0.72, CHWK 15.56.

## Errors Encountered

| Error | Resolution |
|-------|------------|
