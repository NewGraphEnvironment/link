# Parallelising the post-consolidate recompute — what was measured

**2026-09-01, link#250, v0.48.0.** Dispatcher m1, local docker `fwapg`
(Docker VM 6 CPUs of the host's 10), persist schema `fresh`.

## The headline

The recompute is now correct in parallel and **byte-identical** to serial. The
speedup on the sets measured here is **1.43×–1.51×**, not the ~3.4× #250
projected — and the reason is neither the pool nor the database.

**A pool's makespan is bounded below by its slowest single job.** On every set
tried, one WSG dominated:

| set | `-j1` | `-j4` | measured | ceiling | % of ceiling |
|---|---|---|---|---|---|
| 4 WSGs (LKEL,CHWK,CHES,SALR) | 346 s | 242 s | 1.43× | 1.53× | 93% |
| 8 WSGs (+LSAL,LPCE,TABR,MFRA) | 434 s | 287 s | 1.51× | 1.92× | 79% |

The ceiling is `total ÷ slowest single job`. CHWK alone is **226 s** — 74% of
the 4-WSG set and 52% of the 8-WSG set. The pool is doing close to the best
that is available on this input; there is no headroom in it to recover.

## Recompute cost does not track segment count

This is the part worth carrying forward, because it invalidates the obvious
balancing heuristic.

| WSG | segments | recompute |
|---|---|---|
| **CHWK** | 8,866 | **226 s** |
| SALR | 10,663 | 11 s |
| CHES | 9,332 | 27 s |
| LKEL | 7,446 | 40 s |

SALR is 20% **larger** than CHWK and finishes **20× faster**. The cost is in
the downstream barrier walk, not the segment count — so a bucketing scheme
balanced on segments (or on persisted rows, as `study_area_buckets.R` does for
modelling) does **not** balance recompute time. Whether the 34-WSG field set
or the 217-WSG provincial set contains a similar dominant item is unknown and
was not measured here; it decides the real speedup, and it needs a real run.

## Two wrong diagnoses, recorded so they are not re-derived

Both were plausible, both were stated with more confidence than the evidence
carried, and both were refuted by the next measurement.

**1. "The Postgres parallel-worker pool is the bottleneck."** The reasoning was
sound on its face — `max_parallel_workers = 4` cluster-wide and
`max_parallel_workers_per_gather = 3`, so a single recompute query can consume
the whole pool, and four concurrent jobs would then contend for workers rather
than add capacity.

Tested by sweeping `PGOPTIONS='-c max_parallel_workers_per_gather=0'`, which
reaches every job's libpq connection and needs no server config change. The
prediction was that disabling intra-query parallelism would let process
concurrency scale.

It did the **opposite**:

| | `-j1` | `-j4` |
|---|---|---|
| default (`per_gather=3`) | 346 s | 242 s (1.43×) |
| `per_gather=0` | 330 s | 309 s (**1.07×**) |

Serial time barely moved (330 vs 346 s), so Postgres' parallel workers were
contributing almost nothing to begin with, and the pool was never the
constraint.

**2. "Then it must be Docker I/O."** The Docker VM has 6 CPUs and `-j4` at
`per_gather=0` puts only 4 backends on them, so CPU starvation was ruled out;
Docker Desktop's filesystem is slow and each job writes a per-WSG streams copy
plus two GiST indexes, so I/O looked like the answer.

Refuted by sampling `pg_stat_activity` every second during a `-j4` run:
**269 samples, 100% `CPU(running)`** — zero I/O waits, zero lock waits. And
269 rows over ~242 sample rounds is **~1.1 active backends on average**, i.e.
the database is idle most of the time and the work is in the R client.

The answer was in the per-job timings the whole time, and both wrong turns
came from theorising about the aggregate instead of looking at the
distribution. `recompute_sweep.sh` now keeps per-job logs and prints the
slowest jobs and the slowest job's share, so the first thing seen is the thing
that decides the answer.

## What is settled

- **Byte-identical.** `data-raw/recompute_parity.sh` runs three passes from a
  snapshot — serial, serial again (idempotence), parallel + shuffled from the
  same pre-state. `A == B == C` on LKEL,CHWK,CHES,SALR. Three passes rather
  than two because `lnk_access(merge = TRUE)` reads its own prior output
  (`WHEN t.access_<sp> = 2 THEN 2`), so idempotence had to be measured rather
  than assumed. It holds.
- **The shared-state race was real and is closed.** `lnk_access()` rebuilt
  ~38 schema-scoped barrier views per call; `CREATE OR REPLACE VIEW` takes an
  `AccessExclusiveLock` whose queued request blocks every subsequent
  `AccessShareLock`. Hoisted, and the redundant `DROP VIEW` removed.
- **Recompute failures now fail the run.** They previously could not: `|| echo`
  inside the loop, `RUN_INCOMPLETE` assigned before it, success line
  unconditional.

## Where the remaining time actually is

At `-j4` the database is active ~28% of the time, so the rest is R-side:
`lnk_pipeline_access()` and `lnk_pipeline_mapping_code()` pull whole per-WSG
tables into R and compute there, and every job additionally pays a full
`pkgload::load_all()` of the source tree (`wsg_recompute_one.R:25-27`).

Two candidates, both out of scope for #250 and both worth their own issue:

1. **Drop the per-job `load_all()`** — install once, run jobs under
   `library(link)`. Changes the `LNK_LOAD` contract shared with
   `wsg_run_one.R`, `host_vintage.R` and `host_stamp.R`, and CLAUDE.md's
   "never touch the repo mid-run" rule exists because the dispatcher uses
   `load_all()`.
2. **Find out why CHWK is 20× SALR** at 80% of its size. If the downstream
   walk is the cost, that is a fresh-side question about
   `frs_network_features` over a barrier-dense drainage, and it would speed up
   the serial path too — which is worth more than pool width, because the
   makespan floor *is* the slowest WSG.

## Reproducing

```bash
bash data-raw/recompute_parity.sh "LKEL,CHWK,CHES,SALR" bcfishpass 4
bash data-raw/recompute_sweep.sh  "LKEL,CHES,SALR,LSAL,LPCE,TABR,MFRA,CHWK" bcfishpass 1 4
PGOPTIONS='-c max_parallel_workers_per_gather=0' SWEEP_WARM=0 \
  bash data-raw/recompute_sweep.sh "LKEL,CHWK,CHES,SALR" bcfishpass 1 4
```
