# Recompute each group once what it reads has landed (link#374)

**Question.** Can the post-consolidate recompute start group by group while the legs still run, instead of after the last leg and consolidate? If so, under which dependency rule, and how much critical path does that save once its load on the dispatcher's database is counted?

**Answer.** Yes, under the **line** rule, at full width while the legs run. Replayed on `20261023_074321-24d85e8c` with the stalls removed, it ends the recompute 36.7 min sooner (38.1 min if its load on the dispatcher cost nothing). As the run was recorded, with the dispatcher leg 5 h past the cloud legs, it is 89.4 min sooner. The outlet closure #374 proposed is too narrow: it misses dependencies in 150 of 241 groups.

Measured 2026-10-26 on the dispatcher (link at `374-…` branch, fresh 0.42.0), against `fresh_default` as the 2026-10-23 run left it. Times are UTC.

## What a group's recompute reads

`wsg_recompute_one.R` walks downstream from the group's own segments through the persist schema's barrier views. Those views read **every** group's `barriers` and `barrier_overrides`, by position, not by group. So a group can be recomputed once it, and every group holding a row on its downstream path, has landed. The table of reads, writes and locks is in the PWF findings (`planning/archive/…-issue-374-…/findings.md`).

`deps.tsv` (`data-raw/recompute_deps.R … all`) holds three candidate rules over FWA:

| rule | pairs | groups with any | median |
|---|---|---|---|
| closure (`frs_wsg_drainage()`, #374's proposal) | 965 | 184 | 4 |
| owner (groups with a segment on the path) | 1,243 | 198 | 5 |
| line (groups touching any line on the path) | 2,211 | 208 | 9 |

- **closure ⊂ owner ⊂ line**, in every group.
- **The closure is not the dependency set.** The owner rule adds groups in 150 of 241, because a watershed group is not one drainage: coastal groups hold many rivers, and inland groups hold tributaries that enter another group's main stem. It finds #361's TOOD and NATR cases on its own (TOOD reads FROG, LKEC, UKEC and ULRD; NATR reads the Fraser groups through two Fraser-coded segments).
- **The owner rule is not complete by construction.** Gradient barriers are found along the whole of every line a group touches and persisted under that group's code. In `fresh_default`, 1,224 barrier positions are held by more than one group (all gradient, up to 13 holders: every Fraser main-stem group). Copies agree at all but 1 position, and no override copy differs. 1,864 rows are held by a group that does not own the segment they sit on, and the owner holds an identical copy of all but 2. 285 rows sit on no persisted segment. Controls are filtered to each group, so another build could differ.
- **The line rule is complete by construction**, and the scheduler uses it. Every barrier row is on a line its holder touches (gradient: the whole line; every other source: the holder's own segments), and an override sits at its holder's own barrier positions.
- FWA's unassigned codes (`999…`, construction lines) are left out on both sides. No persisted segment carries one, and `999` is never an ancestor of a real code. Left in, they made every group depend on 245 others.

## How much it saves: `sim_summary.tsv`, `sim_jobs.tsv`

`data-raw/recompute_schedule_sim.R` replays the run's recorded times through the end-of-run pool (#369's driver: each cloud host consolidated as its leg ends) and the early scheduler. Both are `-j8`, longest first, with each job given its `log_recompute` minutes plus #260's 9.7 s gap. Minutes from the first model start:

| scenario | rule | recompute ends | after the last landing | saving |
|---|---|---|---|---|
| recorded | end (today) | 670.8 | 110.4 | — |
| recorded | line | 581.4 | 21.0 | 89.4 |
| no stalls | end (today) | 375.1 | 110.7 | — |
| no stalls | closure (too narrow) | 323.1 | 58.8 | 51.9 |
| no stalls | line | 336.9 | 72.6 | 38.1 |
| no stalls | owner | 326.1 | 61.7 | 49.0 |

"No stalls" is the honest case: KTSU at 1.3 min and OKAN at 7.6 min, their re-run times. The legs then end close together (dispatcher 253, last consolidate 264), most groups read something from the last host to land, and the pool is throughput-bound after it. The owner rule would buy 11 more minutes than the line rule: that is the price of the control asymmetry.

## The load on the dispatcher: `headroom/`, `headroom_j4/`, `sim_coupled.tsv`

`headroom.sh` modelled NEVI, SALM and BOWR into scratch `fresh_374m` three times: alone (A1), beside a `-j8` recompute looping over 16 groups in scratch `fresh_374r` (`headroom_setup.R`: their rows plus every barrier and override row), and alone again (A2).

| group | A1 | B (`-j8`) | A2 |
|---|---|---|---|
| NEVI | 1.20 | 2.37 | 1.17 |
| SALM | 1.43 | 3.03 | 1.48 |
| BOWR | 2.55 | 4.83 | 2.48 |

At `-j4` (`headroom_j4/`) the same three groups took 6.16 min against 4.90 and 5.37 alone (1.20x); at `-j8`, 10.23 against 5.18 and 5.13 (1.99x). The dispatcher's modelling slows faster than linearly in the jobs beside it: the database saturates past about four. A1 and A2 agree in both, so it is not a warming cache. The recompute jobs themselves ran at their usual 3.0 to 4.8 min.

The coupled simulation slows the replayed dispatcher leg while `k` jobs run, and the dispatcher's groups land later accordingly. Stall-free, line rule, by the measured curve (extra time interpolated through (0, 0), (4, 0.20), (8, 0.99)), and by a linear α = 0.125 (2x at `-j8`, so too dear at narrow widths):

| jobs while the dispatcher models | dispatcher leg ends | recompute ends | saving (measured curve) | saving (linear) |
|---|---|---|---|---|
| 0 | 253.4 | 364.0 | 11.1 | 11.1 |
| 1 | 255.4 | 360.8 | 14.3 | 11.7 |
| 2 | 256.6 | 358.5 | 16.6 | 12.9 |
| 4 | 259.0 | 352.9 | 22.2 | 17.5 |
| 8 | 277.8 | 338.4 | **36.7** | 35.9 |

Full width is best despite the slowdown, because the pool is throughput-bound. So the scheduler keeps one width, `--recompute-jobs`.

Not modelled: the consolidates' own slowdown (they share the database), and a five-host run's balance (#376). The provincial run that uses this measures both.

## Runs on the dispatcher and the persistent worker

Ten groups, `--config=default --buckets-exact --recompute-jobs=4`, no cloud host, each into its own scratch schema. The dispatcher modelled GLAR, SWIR, JENR, UJER, NAHR, BELA and KUSR; `worker1` modelled TESR, ATLL and TUYR. The groups were picked from `deps.tsv` so that the dispatcher's first five read a worker group, and so land minutes before they may start, while BELA and KUSR read nothing in the run.

| run | run_uid | recompute | outcome | tail after the last landing |
|---|---|---|---|---|
| A | `20261026_174957-11297e26` (`run_a/`) | early | exit 0; audit 18 pairs, 0 early; no lock waits sampled (`run_a_waits.tsv`) | 0.8 min |
| B | `20261026_180139-59d231d0` (`run_b/`) | `--recompute-at-end` | exit 0 | 0.65 min |
| A2 | `20261026_181957-51c00c64` (`run_a2/`) | early, with the wake fix | exit 0; audit clean | 0.5 min |

- **The ordering was exercised.** In A, GLAR landed at 17:52:39 and started at 18:00:05, 3 s after the worker's consolidate landed TESR and ATLL; NAHR and SWIR likewise. BELA started 3 s after it landed, while the dispatcher was still modelling KUSR. On a shared line the rule runs both ways: TESR reads the five dispatcher groups on the Teslin.
- **Same outputs.** A, B and A2 match row for row in all 13 output tables (348,857 segments; `ab_compare*.tsv`, `ab_compare.R`). A planted one-row difference in B's mapping code was caught. `study_area_verify.sql` passes all three at `expected_n=10`. (Against `fresh_default` the ten groups also match: nothing since 0.68.0 changes model outputs, so it is no negative control.)
- **A found a latency bug.** Its last groups waited 27 s for the scheduler's next 30 s poll to see the final set, so early lost to B on a run this small. The scheduler now sleeps a second at a time and wakes on the final set or a stop; A2 started the final set 1 s after the last landing.

## Wrong turns

- An "inside its holder's drainage" test flagged 1.43 M rows as foreign. A group is not one drainage, so the outlet is the wrong reference point.
- The line rule by `blue_line_key` first dropped 52 pairs, because the segment table had filtered out NULL local codes, which only the owner rule needs.
- The simulation's first baseline started the end pool 44 min late: `^\[[0-9:]+\]` matched R's `[1]` print prefix in the consolidate log.
- A residual ownership query ran 17 min unindexed and was cancelled before the benchmark.

## Files

- `deps.tsv`: the three rules (`data-raw/recompute_deps.R`).
- `sim_summary.tsv`, `sim_jobs.tsv`, `sim_coupled.tsv`: the replay (`data-raw/recompute_schedule_sim.R`).
- `headroom_setup.R`, `headroom.sh`, `headroom*/`, `headroom*.log`: the benchmark.
- `digest_test.R`, `digest/`, `digest_{TOOD,NATR}.log`: whether a recompute over only the line rule's groups equals one over every group. TOOD (18 line-rule groups, 6 in its closure) and NATR (32 and 4): the line rule matches every group present in every table (0 rows differ of 97,296 and 47,302); the closure differs on 2 segments in each, the ones #361 traced to groups outside it.
