# loadall_260 — the recompute job prologue, measured

Evidence for link#260 (tracked on #377), 2026-10-26, on the dispatcher (10 CPUs; local
docker `fwapg` idle, no active client backend; macOS indexing about 1.3 cores
throughout). link HEAD `c7e23509`, installed link 0.68.0, R 4.5.2 (`env.txt`).

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
a 110 min phase. The prologue is a real share only of a short group in isolation (13 %
of SALR's 11 s), and the pool runs groups in parallel, longest first, so short groups
never sit on its critical path. The recompute's time is its work: the next levers are
#374 (overlap it with the slowest leg) and #261 (CHWK).

## Notes

- #260 cites the prologue at `wsg_recompute_one.R:24-28` (v0.48.0); it is now `:26-30`.
- 110 min was a hand-built figure in `research/study_area_run.md`; no `_phases.tsv`
  exists for that run (phases began with #375). `log_recompute` gives 110.3 min.
- `lnk_load_overrides()` reads 0.24 s under `library(link)` against 0.11 s under
  `load_all()`, in every condition. That is the installed 0.68.0 against the source
  tree, and it leaves the totals above unchanged in direction.
