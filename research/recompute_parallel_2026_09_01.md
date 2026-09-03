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
the downstream barrier walk, not the segment count.

**Two corrections to how this was first written up.** The recompute is not
bucketed at all — buckets distribute *modelling* across hosts, while the
recompute runs dispatcher-only over the union of them. And the bucketing
was already not naively segment-balanced: link#253 made the packing
speed-aware (finish time, not raw segments), after link#246 had already moved
the weight from WSG count to segment count.

**A third correction, 2026-09-02.** The sentence above said "over every WSG in
the schema". It does not, and did not: `ALL_WSGS` is the union of the host
buckets (`study_area_run.sh:1306`), and the 2026-09-01 field run logged
`recompute (lnk_access, 34 WSGs, -j4)` against a 95-WSG schema. The same wrong
claim had propagated into `CLAUDE.md` and `research/study_area_run.md`; all
three are corrected. It matters because the recompute therefore **does** scale
with scope — 217 WSGs is ~6.4x this one, not a constant — which is the opposite
of the planning conclusion the claim was used to support.

Combined with the ceiling measured above, that points somewhere specific: the
pool is already at 79–93% of its Amdahl limit, so parallelism has little left to
give. The remaining lever is doing **less work**, i.e. recomputing
`run ∪ upstream(run)` rather than every run WSG. Tracked as link#274, unmeasured.

What the measurement does bear on is narrower, and genuinely open. #246 chose
segment count because it beats *WSG* count — "a one-WSG component can outweigh
a three-WSG one" — and never against measured time. Checked here against the
104 WSGs of real modelling times already sitting in `_per_wsg_times.csv`:

| | |
|---|---|
| Pearson r | 0.798 |
| R² (time ~ segments) | **0.636** |
| seconds per 1000 segments | 1.88 → 9.49, a **5× spread** |

Segments explain about two thirds of modelling time. **CHWK is the slowest
per-segment WSG in modelling too** — 9.49 s/1000, worst of 104 — the same WSG
that dominated the recompute. So it is an intrinsically expensive watershed
group, not a recompute quirk.

That is still not sufficient to change `comp_weight`. Measured times are more
accurate but are not always present, and an LPT fallback that silently
degraded when they were missing is exactly the incident in
`planning/archive/2026-05-ops-hardening-20260514/findings.md:23-29` — it
ignored host speeds across a 217-WSG run and nobody noticed. Segment count is
one query and never degrades. The tradeoff needs its own measurement on
modelling, and is filed separately.

Whether the 34-WSG field set or the 217-WSG provincial set contains a
similarly dominant item is unknown and was not measured here; it decides the
real speedup, and it needs a real run.

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

0. **Order the pool longest-first — DONE in this PR.** A pool cannot beat its
   slowest job, and the work list was `sort -u`, i.e. alphabetical. It now
   orders on prior recompute times from committed `${TS}_recompute.log` files,
   newest wins, unknown WSGs at the median of the known (the rule
   `study_area_buckets.R` already uses for a WSG missing from the network
   table). With no prior times it returns the input order **and says so**,
   rather than degrading silently. Ordered on recompute times and never on
   segments, which would put the cheap job first here.

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

## The bench is capped below the host — local numbers understate

Everything above was measured against a **local Docker Postgres**, and that
cluster is smaller than the machine it runs on. On the machine used here the
Docker VM had **6 of the host's 10 CPUs**, and the server ran:

| setting | value |
|---|---|
| `max_parallel_workers` | 4 |
| `max_parallel_workers_per_gather` | 3 |
| `max_worker_processes` | 6 |
| `max_connections` | 40 |
| `shared_buffers` | 1 GB |
| `work_mem` | 1 GB |
| `maintenance_work_mem` | 2 GB |

So a **single** recompute query can consume the cluster's entire parallel-worker
pool, and `-jN` beyond a handful of jobs is contending for a pool sized for one.

**Do not conclude from a flat local `-jN` curve that the workload will not scale
on other hardware.** The ceiling measured here is partly this bench's, and a
dispatcher with more cores and a differently-tuned cluster is a different
experiment.

**And do not read that as "the pool was the constraint" either** — the section
above measured that directly and it was not: disabling intra-query parallelism
barely moved serial time, and the database sat idle at ~1.1 active backends
while the cost stayed R-side. Both statements are true at once. The bench
understates *and* the thing it understates was not the bottleneck.

Check the bench before trusting a scaling number from it:

```bash
docker info --format '{{.NCPU}} CPUs / {{.MemTotal}} bytes'
psql -h localhost -p 5432 -U postgres -d fwapg -c "
  SELECT name, setting, unit FROM pg_settings
   WHERE name IN ('max_parallel_workers','max_parallel_workers_per_gather',
                  'max_worker_processes','max_connections','shared_buffers',
                  'work_mem','maintenance_work_mem') ORDER BY name;"
```

Migrated from machine-local memory 2026-09-02 (soul#47). The host's identity
stays in memory; only the shape of the constraint and how to re-measure it
belong here.

## Reproducing

```bash
bash data-raw/recompute_parity.sh "LKEL,CHWK,CHES,SALR" bcfishpass 4
bash data-raw/recompute_sweep.sh  "LKEL,CHES,SALR,LSAL,LPCE,TABR,MFRA,CHWK" bcfishpass 1 4
PGOPTIONS='-c max_parallel_workers_per_gather=0' SWEEP_WARM=0 \
  bash data-raw/recompute_sweep.sh "LKEL,CHWK,CHES,SALR" bcfishpass 1 4
```
