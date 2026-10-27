# Findings — Why is CHWK 20x SALR at 80% of its size? (#261)

## Issue context

## Problem

Recompute cost does not track segment count, and the spread is extreme.

Measured 2026-09-01 during #250, same host, same schema, same run:

| WSG | segments | recompute | s / 1000 segs |
|---|---|---|---|
| **CHWK** | 8,866 | **226 s** | **25.5** |
| LKEL | 7,446 | 40 s | 5.4 |
| CHES | 9,332 | 27 s | 2.9 |
| SALR | 10,663 | **11 s** | **1.0** |

**SALR has 20% more segments than CHWK and finishes 20× faster.**

This is not confined to the recompute. Over the 104 WSGs with recorded
*modelling* times (`data-raw/logs/**/*_per_wsg_times.csv`), CHWK is also the
**worst of 104** at 9.49 s per 1000 segments, against 1.88 for the best — a 5×
spread there too (see #259). So CHWK is an intrinsically expensive watershed
group on both phases, not a recompute artifact.

## Why it matters more than pool width

A pool's makespan is bounded below by its slowest single job. In #250 that one
WSG was **74%** of a four-WSG set and **52%** of an eight-WSG set, capping the
achievable speedup at 1.53× and 1.92× — and the pool reached 93% and 79% of
those ceilings. There is no headroom left in the pool; the headroom is in the
long pole.

Making CHWK-class WSGs cheaper speeds up the **serial** path too, which pool
width can never do. On a 217-WSG provincial run the makespan floor is whatever
the worst WSG costs, however many machines are thrown at it.

## Hypothesis to test (not assumed)

The recompute's cost centre is the downstream barrier walk —
`fresh::frs_network_features()` over `barriers_<sp>_access`, called from
`lnk_pipeline_access()`. CHWK (Chilliwack) drains through the lower Fraser,
which is barrier-dense, so the walk crosses far more features than its own
segment count suggests. That would explain why cost tracks *downstream barrier
count* rather than *local segments*.

**Test it before building anything.** Count barriers downstream of each WSG's
outlet (`fresh::frs_wsg_outlets()` + the measure-aware `fwa_downstream()`
already used by `lnk_wsg_downstream_check()`), and correlate against the
measured per-WSG recompute time. If that correlates far better than segment
count does, the mechanism is confirmed and the fix is a `fresh`-side question
about the walk. If it does not, the hypothesis is wrong and the profiling
should start over — `EXPLAIN (ANALYZE, BUFFERS)` on the actual
`frs_network_features` query for CHWK vs SALR.

Do not skip to optimising. #250 produced two confident, plausible, wrong
diagnoses (a Postgres worker-pool theory and a Docker I/O theory), both from
theorising about the aggregate instead of measuring the distribution.

## Payoff, if the hypothesis holds

A better downstream-barrier predictor is also the input #259 wants for
bucketing, and would let `recompute_order()` (added in #250) order the pool
without needing a prior run's times.

## Acceptance

- [ ] Downstream-barrier count computed per WSG and correlated against measured
      recompute time, reported alongside the segment-count correlation
- [ ] Hypothesis confirmed or refuted **before** any optimisation work is scoped
- [ ] If confirmed and the fix is upstream, raised in `fresh` with the
      measurement attached rather than described

Relates to #250 (`research/recompute_parallel_2026_09_01.md`), #259
(`comp_weight` wants the same predictor), #227
(`lnk_wsg_downstream_check()` already walks downstream and is ~0.5 s, so the
counting machinery exists).
Version pin: link@v0.48.0.


## Errors Encountered

| Error | Resolution |
|-------|------------|
