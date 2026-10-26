# loadall_260 — the recompute job prologue, measured

Evidence for link#260 (tracked on #377), 2026-10-26, on the dispatcher (10 CPUs; local
docker `fwapg` with no active client backend, and a 1-minute load average of 4.03 from
other processes before the run). link HEAD `c7e23509`, installed link 0.68.0, R 4.5.2 (`env.txt`).

## The question

Every job in the post-consolidate recompute pool is a fresh `Rscript
data-raw/wsg_recompute_one.R` under `LNK_LOAD=loadall`, so each pays a
`pkgload::load_all()` of the source tree. Is that fixed cost worth removing, at the
price of changing the `LNK_LOAD` contract, which 12 `data-raw/` R scripts read?

## Method

- `prologue.R` runs what `wsg_recompute_one.R` runs before `t0` (`:26-62`): R startup
  (from the shell's launch), `load_all()` or `library(link)`, `DBI` / `RPostgres`, the
  connection, the two `SET`s, `lnk_config("default")`, `lnk_load_overrides()`, and
  species / presence for SALR. Each stage is timed.
- `measure.sh` runs it under each mode in three conditions: 20 in sequence (the first
  reported apart as `cold`), 3 waves of 8 at once (`conc`), and 10 in sequence beside
  7 CPU-bound R processes (`busy`, a slot starting while seven compute, the `-j8`
  shape). Output: `timings.tsv`.
- `span.sql` reads the 2026-10-23 pool (`20261023_074321-24d85e8c`) from
  `fresh_default.log_recompute`, whose `date_start` is written after the prologue, so
  its summed work leaves every prologue out (`span.tsv`).
- `shares.R` reads those, plus the run's per-group minutes in
  `data-raw/logs/study_area_run/20261023_074321_recompute.log`, and writes `shares.txt`.

## Measurement

| condition | prologue, `load_all` | prologue, `library(link)` | `load_all` stage alone |
|---|---|---|---|
| sequence | 1.10 s | 0.62 s | 0.74 s |
| 8 at once | 1.44 s | 0.82 s | 0.94 s |
| beside 7 busy | 1.63 s | 0.92 s | 1.08 s |

Against the busy figure, 1.63 s:

| denominator | work | prologue share |
|---|---|---|
| SALR, 2026-10-23 run | 43 s | 3.6 % |
| median group, 2026-10-23 run | 159 s | 1.0 % |
| CHWK, 2026-10-23 run | 934 s | 0.2 % |
| SALR as #260 framed it (2026-09-01, `-j4`) | 11 s | 12.9 % |
| CHWK as #260 framed it | 226 s | 0.7 % |
| **the whole pool** | 240 × 1.63 s / 8 = **0.81 min** of a 110.3 min span | **0.74 %** |

Switching to `library(link)` would save 0.71 s per job: **0.35 min** of a provincial
recompute (0.32 %).

The pool's span (110.3 min, first job's work start to last job's end) exceeds its
summed work over 8 slots (104.6 min) by 5.7 min, which is at most 11.3 s of untimed
slot time per job. That is the in-run upper bound on everything outside `t0` together:
the prologue, R exit, the driver's 1 s slot poll and the tail. The prologue is 1.6 s of
it.

## Verdict

**Not material, and not changed.** The `LNK_LOAD` contract stays: `load_all()` is what
guarantees each job runs the tree verified at pre-flight, and removing it buys 21 s of
a 110 min phase. Every job's prologue is on the pool's critical path, at a weight of one
slot in eight, because the span is set by the summed work over the slots (104.6 min),
not by the longest job (22.75 min); that is the 240 × 1.63 s / 8 above. It is a real
share only of a short group taken alone: 1.63 s on SALR's 11 s of work is 12.9 % of the
job. The recompute's time is its work, and the same one-slot-in-eight arithmetic holds
for any single group: CHWK's 15.56 min is about 1.9 min of the span. So the next lever is
#374 (overlap the recompute with the slowest leg); #261 pays only if CHWK's cause also
slows other groups.

## Notes

- #260 cites the prologue at `wsg_recompute_one.R:24-28` (v0.48.0); it is now `:26-30`.
- 110 min was a hand-built figure in `research/study_area_run.md`; no `_phases.tsv`
  exists for that run (phases began with #375). `log_recompute` gives 110.3 min.
- Compare the prologue totals, not the load stage alone. `load_all()` loads link's
  Imports inside its own stage, while `library(link)` defers them: its first
  `lnk_load_overrides()` call, in the prologue's order, loads 17 namespaces (crate,
  dplyr, readr, …; counted with `setdiff(loadedNamespaces(), before)` around the call)
  and takes 0.24 s, its second 0.05 s. So `lnk_load_overrides()` reads 0.24 / 0.30 / 0.33 s under
  `library(link)` against 0.11 / 0.15 / 0.15 s under `load_all()` (sequence / 8 at once
  / beside 7 busy), and the load-stage column charges `load_all()` with namespace
  loading `library(link)` pays later. The totals and the 0.71 s saving are unaffected.
