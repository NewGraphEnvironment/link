# recompute_cost_261: why a group's recompute costs what it does

Evidence for link#261 (tracked on #377), measured 2026-10-27 20:32 to 23:27 UTC on the
dispatcher's `fresh_default` (PostgreSQL 17.5, `work_mem` 512 MB), which still held the
2026-10-23 provincial build untouched (run_uid `20261023_074321-24d85e8c`, 241 groups,
link `1d00c04c` / 0.68.0, fresh `e9793047` / 0.42.0). The scripts ran from m4 with
`pkgload::load_all()` of this branch (base `4b56a351`) and fresh 0.43.0 (`18d92ceb`),
whose `frs_network_features()` is unchanged since 0.29.0. R 4.5.2. The verdict is in
[`research/recompute_cost.md`](../../../research/recompute_cost.md).

## The question

CHWK's post-consolidate recompute took 15.56 min in the 2026-10-23 run and SALR's 0.72 min
(9.26 and 0.51 at `-j4` on 2026-10-17): 20× the time at 1.26× the segments. #261 proposed
one cause to test before optimising anything: the number of barriers downstream of a
group, walked by `fresh::frs_network_features()`.

## Method

- `walks.R` mirrors `lnk_access(merge = TRUE)` read-only. It copies the group's segments
  into a session TEMP table with the same indexes, captures fresh's walk SQL by mocking
  `frs_db_query()`, and runs every walk the recompute runs (one per present species
  view, three sources) under `EXPLAIN (ANALYZE, BUFFERS)`. Nine groups: #261's four
  (CHWK, SALR, LKEL, CHES), three of the five slowest of 2026-10-23 (LFRA, SETN, LSKE; FRCN, the second slowest, was not
  decomposed, and CHWK is the fourth) and two near the
  median (KOTR, SPAT). Output `walks.tsv`, `plans/<WSG>_<table>.json`; `fresh_default`'s
  tuple write counters were 161,847,271 before and after.
- `range_hypothesis.sql` / `.tsv` tested a first explanation of the probe cost and
  refuted it (kept as the wrong turn; see below).
- `walk_prefilter.R` runs each walk as fresh sends it and with the feature side cut to
  the features `fwa_downstream()` can return: on one of the group's blue lines, or on a
  code that is an ancestor of, or equal to, a group segment's code. Both forms are
  digested (arrays in their own order, and sorted) and timed. Output
  `walk_prefilter.tsv`, `plans/prefilter_*.json`. SALR's lines are in the TSV only; the
  run log covers the other eight.
- `rerun.R` re-runs the whole recompute for SALR and CHWK from a worktree at `1d00c04c`,
  each step timed and the walks timed from R, with every table it writes digested before
  and after and backed up first. Output `steps_<WSG>.tsv`, `rerun_walks_<WSG>.tsv`,
  `rerun_digest_<WSG>.tsv`, `rerun_<WSG>.log`.
- `predictors.R` computes candidate predictors for all 241 groups, among them #261's
  (features downstream of the group's outlet, by the walk's own `fwa_downstream(…, true,
  1)`). It also times one walk of a fixed 200,000-feature sample of the CH view per group,
  as sent and prefiltered (`probe_us`, `probe_pre_us`). `predictors_subset.tsv` is the
  nine-group check.
- `correlations.R` reads those and both runs' recompute logs and writes
  `correlations.tsv`, `misses.tsv`, `pool.tsv` and `minutes_vs_predictors.png`.

Another session queried m1's database continuously from 20:51 UTC (one backend running
watershed-area calls). Every row records `others_active`. In `walks.tsv`, LSKE's CH-shaped
walks took 67.6 to 69.2 s with no other backend and 68.0 to 70.1 s beside one, so that
load did not show, and later scripts accept one other backend. `rerun.R` refuses if any
other backend holds a lock in `fresh_default`. `predictors.R` checks only at its start:
the last 20 groups it probed (UKEC to ZYMO, alphabetically last) ran beside 6 or 8 other
backends, an 8-way parallel query from another session. They carry 2,760 of 33,517
predicted walk seconds, and the correlations read the same without them.

## Measurement

### Where one group's time goes

| | SALR | CHWK |
|---|---|---|
| re-run total | 46.3 s | 617.6 s |
| walks (timed from R) | 28.2 s | 589.4 s |
| setup and UPDATE in `lnk_access()` | 3.8 s | 8.3 s |
| habitat gate | 2.8 s | 8.0 s |
| mapping code | 7.2 s | 7.5 s |
| guard, prior copy, rest of `lnk_pipeline_access()` | 3.7 s | 4.1 s |
| digests before and after | unchanged (4 tables) | unchanged (10 tables) |

The steps sum to within 0.5 s of the wall clock. The walks timed from R here and on the
server in `walks.tsv` come from different runs under different load: the same CHWK CH walk
took 80.3, 86.2 and 93.7 s across the three scripts. So the client side (arrays sent and
parsed) is inside that spread, and these runs cannot separate it further.

### Why a walk costs what it does

Every walk has one plan. The outer side reads the walked view province-wide (7.24 M rows
for CH and its six identical-before-overrides species, 3.48 M for BT/DV/RB, 5.36 M for
ST/WCT), about 6 s per CH walk. For each row it probes the group's segments with a
`BitmapOr` on `blue_line_key` and `wscode_ltree <@ b.wscode_ltree`. Over the same
7,240,975 features, the inner side of the CH walk (the nested loop less its outer scan)
takes 13.0 s in SALR and 74.4 s in CHWK: 1.8 against 10.3 µs per feature, 5.7×. LKEL's
is 1.3 µs, LSKE's 8.4, SETN's 19.7 and LFRA's 21.2. The pairs returned do not set the
cost: SETN's CH walk returns 4.83 M pairs and LFRA's 1.17 M, both in 157 to 163 s; CHWK
returns 162 k in 80 s and LKEL 98 k in 15 s. So CHWK's CH walk costs 4.1× SALR's (80.3
against 19.6 s), and its eight natural views hold 4.5× the province-wide rows of SALR's
two: about 18×, which is the ratio of their natural walks (545.7 against 29.7 s).

**Refuted on the way:** that a probe descends only where the feature's code falls in the
group's code range. CHWK and LFRA hold coastal codes as well as the Fraser main stem
(`100` to `970.…`), so their range covers 7.17 M of 7.24 M features; SETN's covers 0.75 M,
and SETN's walks are the second dearest of the nine, after LFRA's.

### The same walk, prefiltered

| group | sent (s) | prefiltered (s) | |
|---|---|---|---|
| CHWK | 219.0 | 8.9 | 24.6× |
| LKEL | 33.8 | 1.8 | 18.8× |
| LFRA | 357.3 | 38.7 | 9.2× |
| LSKE | 165.2 | 21.5 | 7.7× |
| SALR | 26.9 | 4.3 | 6.3× |
| CHES | 29.0 | 4.9 | 5.9× |
| KOTR | 69.3 | 18.4 | 3.8× |
| SPAT | 76.6 | 21.1 | 3.6× |
| SETN | 211.6 | 178.4 | 1.2× |

One walk per barrier-set shape plus anthropogenic. All 32 walks return the same features
per segment. In four (CHWK CH, BT, ST; CHES CH) the order inside some arrays differs:
fresh's `ORDER BY` (wscode, localcode, measure) ties for co-located features, so that
order is the plan's. link persists only `has_barriers_<sp>_dnstr` from the natural arrays.
The anthropogenic arrays, whose first element `dam_dnstr_ind` reads, match in their own
order in all nine. SETN is output-bound: its prefiltered CH walk keeps 140,159 features
(139,882 of them inside the group), each matching about 34 segments, 4.83 M pairs, and the sort spills 539 MB to disk.

### All 241 groups

| predictor, against 2026-10-23 minutes (240 groups) | Spearman | log-log R² |
|---|---|---|
| the other run's minutes (2026-10-17), the noise ceiling | 0.993 | 0.985 |
| predicted walk seconds (sample walk × view size) | 0.982 | 0.970 |
| features inside the group | 0.881 | 0.745 |
| walks | 0.856 | 0.742 |
| segments | 0.605 | 0.383 |
| features downstream of the outlet (#261) | −0.083 | 0.001 |

The sample walk predicts the nine measured groups' walk seconds at slope 1.00. Against
2026-10-17 the same rows read 0.981, 0.871, 0.857, 0.589 and −0.100. Seven of the nine
decomposed groups have no natural barrier and no crossing below their outlet.

The pool on 2026-10-23: 50,352 s of summed job time (span 110 min at `-j8`). Predicted
walks are 33,398 s of it (single-walk seconds, beside job seconds run eight at once). The prefilter would
leave 7,864 s (calibrated on the nine) to 15,177 s (the sample's own estimate, which
overstates the prefiltered walk except where the walk is output-bound: SETN measured 560 s
against its 539), a saving of 18,221 to 25,534 s, 36 to 51 % of the summed time. The
calibrated fit predicts below zero for 34 groups; each group's estimate is floored at 5 %
of its sent walk (46 groups), and a floor anywhere from 0 to 20 % gives 7,769 to 9,128 s. CHWK is 934 s of the pool, and the ten
costliest groups hold 17.8 % of predicted walk time.

## What changed because of it

#261's hypothesis is refuted, and the cost is not CHWK's alone: every group pays the
province-wide probe. That passes #377's test for being worth fixing. The fix belongs in
fresh's `frs_network_features()` (a feature-side prefilter that leaves its answer
unchanged); a fresh issue is drafted, not filed. No link code changed.

## Owed

- Re-run `predictors.R` and `correlations.R` on the next provincial build (#326's
  segmentation roughly halves segments).
- The pool saving is an estimate from walks timed one at a time; the next run with a
  prefiltered walk measures it.
