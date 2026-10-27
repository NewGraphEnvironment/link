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
| Range count with `OR bw.w @> g.lo` ran past 10 min (the OR defeats the index; 3,133 subqueries each summing millions of rows) | Running total per species (`sum(n) OVER (PARTITION BY sp ORDER BY w)`), two index lookups per range, ancestors by equality on `subpath()`. Killing `psql` left its backend running: cancelled with `pg_cancel_backend` |
| Prefilter as `IN (SELECT ...)` still read 7.24 M rows through `barriers_source_idx` (SALR CH 6.1 s) | `= ANY (ARRAY(SELECT ...))` lets the planner use the btree indexes on `wscode_ltree` and `blue_line_key` (2.9 s) |
| Every quiet-wait loop refused: another session queries m1 continuously | Measured its cost (LSKE walks 67.6 s alone, 68.0–70.1 s beside it); experiments tolerate one other backend and record it per row; `rerun.R` refuses on any other lock in `fresh_default` |
| `min(ltree)` does not exist | `DISTINCT ON (group) ORDER BY wscode_ltree` for lo and `DESC` for hi |

## Exploration, 2026-10-27

- **The anomaly holds at provincial scale.** Committed per-group logs: CHWK 9.26 min vs SALR 0.51 min at `-j4` (`20261017_004619_recompute.log`, 18×); 15.56 vs 0.72 min at `-j8` (`20261023_074321_recompute.log`, 22×). The slowest groups in both runs are SETN, FRCN, LFRA, CHWK, LSKE, LILL: the Fraser through and below the canyon, and the lower Skeena.
- **The recompute walks no observations.** `lnk_access(merge = TRUE)` passes `observations = NULL` (`R/lnk_access.R:204`). Per group: one downstream `frs_network_features()` per present species (`barriers_<sp>_access`, a view over `barriers` filtered on `blocks_species`, natural sources, and an anti-join to `barrier_overrides`) and one per source (`barriers_{anthropogenic,pscis,dams}_unified`). Then the habitat gate, the mapping-code persist and the downstream guard.
- **The walk's SQL is unchanged in fresh since v0.42.0** (the version the run used, `e9793047`); `git log v0.42.0..origin/main -- R/frs_network_features.R` is empty. It joins the group's segments to every feature province-wide on `fwa_downstream()`, so its output is one row per (segment, feature downstream of it) pair.
- **m1's `fresh_default` is the 2026-10-23 build untouched** (241 groups; `log_recompute` all at link `1d00c04c`, fresh `e9793047`). `fresh_default.barriers` holds 7,744,965 rows. m1's database is reachable from m4 directly, so the harness runs here with `LNK_MEASURE_HOST`.
- **A second session was loading m1's database** (`COPY incoming FROM STDIN`) at 20:24 UTC; the harness refuses while any other client backend is active.

## Plan review, folded in (2026-10-27)

Review in `review-plan.md`. Dispositions:

- **B1:** `rerun.R` does not run `wsg_recompute_one.R`; it calls the same four steps with `schema = fresh_default`, config `default`, `build_views = FALSE`, from a worktree at `1d00c04c`, refusing any other HEAD.
- **B2:** accepted. `rerun.R` times the real `frs_network_features()` from R; the harness gives the server side. Their difference is the client share, reported as such. The validation line is reworded.
- **G2:** `rerun.R` splits `lnk_access()` into walks, the rest of `lnk_pipeline_access()`, and setup plus UPDATE, and times prior copy, gate, mapping code and guard separately.
- **G4:** already covered: the digest reads `streams_access`, `streams_mapping_code` and each active species' `streams_habitat_<sp>`.
- **G5:** `rerun.R` backs the group's rows up into `zz261_backup` first and prints the restore if a digest moves.
- **G6:** next harness edit sets `default_transaction_read_only` after the TEMP build; counters stay as a secondary check only.
- **G7, G8:** stated in the README.
- **A1, A2:** 10-23 is primary; 10-17 is reported beside it, not as a noise ceiling. Uncontended harness times on the decomposed groups are the clean dependent variable.
- **A4:** `predictors.R` counts per walked view with each view's own filter. Its outlet count uses the guard's 8-argument `fwa_downstream()`; switch it to the walk's 10-argument form (`true, 1`).
- **A5:** prediction written below, before any count.

### Pre-registered prediction (written 2026-10-27, before predictors.R ran)

SALR drains Shuswap, South Thompson, Thompson, then the Fraser from Lytton to the sea, so the features below SALR's outlet include every feature below CHWK's outlet on the lower Fraser. If cost tracked features downstream of the outlet, SALR would cost at least CHWK. It costs 1/22 of CHWK, so #261's hypothesis in its literal form is expected to fail on this pair before any correlation.

Phase 1's first plan (SALR) already points elsewhere: the planner drives every walk from the province-wide feature table (7.24 M rows for CH) and probes the group's segments once per feature. A walk's cost is then set by the feature table's size and by how many of the group's segments each probe returns before the filter: same blue line, or a stream whose code descends from the feature's.

## Phase 1: the walks, measured (2026-10-27, m1, 20:32–21:31 UTC)

Harness `data-raw/logs/recompute_cost_261/walks.R` over SALR CHWK LKEL CHES KOTR SPAT LSKE SETN LFRA, one session, `fresh_default` tuple writes 161,847,271 before and after. `walks.tsv`, one plan per walk in `plans/`. `others_active` is 0 through SPAT and 1 or 2 from LSKE's third walk on (another client's `fwa_watershedatmeasure()` calls), so the last three groups ran beside one other query.

- **Every walk has the same plan, driven from the province.** Outer: an index scan of `fresh_default.barriers` on `barriers_source_idx` returning 7,240,975 rows for the CH view (3.48 M for BT/RB, 5.36 M for ST/WCT), with the override anti-join run 7.24 M times. Inner, once per feature: a `BitmapOr` of `blue_line_key = b.blue_line_key` and `wscode_ltree <@ b.wscode_ltree` on the group's TEMP segments. The outer side alone is ~6 s per CH walk in every group.
- **The cost is the GiST probe, not the pairs.** The CH walk's `wscode_ltree` bitmap index scan takes 0.001 ms per loop in SALR and 0.009 ms in CHWK, over the same 7,240,975 loops: 7 s against 65 s. SETN's CH walk returns 4,829,028 pairs and LFRA's 1,171,394, and both take 157–163 s; CHWK's returns 161,974 pairs in 80 s and LKEL's 98,243 in 15 s.
- **Walk seconds per group** (all walks; natural-barrier views in brackets): SALR 31.0 (29.7), CHES 62.5 (61.0), LKEL 91.0 (90.1), SPAT 100.3 (98.0), KOTR 98.6 (91.6), LSKE 473.1 (469.6), CHWK 551.4 (545.7), SETN 1,052.1 (1,042.5), LFRA 1,101.6 (1,090.1). Anthropogenic, PSCIS and dams walks are under 11 s each anywhere: their outer table is 0.5 M rows, not 7.2 M.
- **The walks are most of the job:** 59–106 % of each group's 2026-10-23 logged minutes (CHWK 59 %, SALR 72 %; SETN 106 % because the harness ran beside another query there and the run's job did not). Uncontended server time against contended job time, so a share, not a decomposition.
- **CHWK has 8 natural walks to SALR's 2,** and five of CHWK's (CH, CM, CO, PK, SK) return identical pair counts (161,974). Before overrides, the natural barrier set has three distinct shapes province-wide: CH = CM = CO = GR = KO = PK = SK (7,242,732 rows), BT = DV = RB (3,481,931), ST = WCT (5,361,260). Walk count multiplies the probe cost; it does not explain it (SALR's one CH walk costs 1/4 of CHWK's).
- **Refuted: the group's code range.** A probe should descend only where the feature's code can have descendants in `[lo, hi]` (`range_hypothesis.sql` / `.tsv`). CHWK and LFRA hold coastal codes too (`100` to `970.030628…`), so the range covers 7.17 M of 7.24 M CH features. SETN's range covers 0.75 M, yet SETN is the slowest walk. The range count says nothing about the probe.

## Phase 1: a prefiltered walk, same features (2026-10-27, 22:07–22:39 UTC)

`walk_prefilter.R` runs fresh's walk SQL as sent and the same SQL with the feature side cut to what `fwa_downstream()` can return: features on one of the group's blue lines (criterion 1) or whose wscode is an ancestor of, or equal to, a group segment's wscode (criterion 2, `wscode_a <@ wscode_b`). The cut uses the btree indexes on `barriers.wscode_ltree` and `barriers.blue_line_key` (`= ANY (ARRAY(...))`; a first try with `IN (SELECT ...)` still read all 7.24 M rows through the source index and took 6.1 s for SALR CH, kept in the errors table). One view per barrier-set shape plus anthropogenic, nine groups, one other backend active throughout (another session's area queries).

- **Same features per segment in all 33 walks** (the digest with each array sorted). The digest in the arrays' own order differs in four (CHWK CH, BT, ST; CHES CH): features tied on the walk's `ORDER BY` (wscode, localcode, measure, all descending) come back in plan order. link persists only the natural arrays' `has_barriers_<sp>_dnstr` booleans, so no output moves. The anthropogenic arrays, whose `[1]` link reads for `dam_dnstr_ind`, match in their own order in all nine.
- **Walk seconds, sent → prefiltered** (three natural shapes + anthropogenic): CHWK 219.0 → 8.9 (24.6×), LKEL 33.8 → 1.8 (18.8×), LFRA 357.3 → 38.7 (9.2×), LSKE 165.2 → 21.5 (7.7×), SALR 26.9 → 4.3 (6.3×), CHES 29.0 → 4.9 (5.9×), KOTR 69.3 → 18.4 (3.8×), SPAT 76.6 → 21.1 (3.6×), SETN 211.6 → 178.4 (1.2×).
- **SETN is the other regime.** Its prefiltered CH walk keeps 140,159 features (inside the group), each matching about 34 segments: 4,829,028 pairs, sorted with a 539 MB spill to disk. That is output volume. It is intrinsic to building full arrays, and link only keeps whether each one is empty.
- **So the walk's cost has two parts:** the province-wide probe (N view features × per-probe cost of the group's GiST), which the prefilter removes; and the pairs, which only a cheaper question removes (does any barrier lie downstream, rather than which).

## Phase 2 check: the sample walk predicts the measured walks

`predictors.R` times a walk of a fixed 200,000-feature sample of the CH view (no index, so it drives from the sample as the real walk drives from the view) against each group's TEMP segments: `probe_us`. Over the nine measured groups, `outer_rows_natural × probe_us` predicts their measured natural walk seconds with slope 1.00, Spearman 1, Pearson 0.997 on logs (`predictors_subset.tsv`). The same sample walk with the prefilter (`probe_pre_us`) fits SETN and LFRA (559 vs 558 s, 179 vs 149 s) but overstates small groups, because scanning the unindexed sample costs about 2.7 µs per row that the real, indexed prefilter does not pay. Measured over the nine (each shape's prefilter time given to every walk of that shape), natural walks go 3,518 → 1,053 s.

- **#261's own predictor is 0 for seven of the nine groups:** no natural barrier and no crossing lies on the main-stem path below SALR, CHES, LKEL, LSKE, CHWK, SETN or LFRA (KOTR 16, SPAT 23). It cannot rank them.

## Phase 1: the instrumented re-run (gate decision 2; 2026-10-27, 22:47–23:00 UTC)

`rerun.R` from a worktree at `1d00c04c` (the commit that wrote both groups' rows), on m1's `fresh_default`, one other backend active (the same read-only area queries; the guard refuses any other lock in `fresh_default`). The worktree loads fresh 0.43.0 (`18d92ceb`); the run used 0.42.0 (`e9793047`), and the walk's SQL is the same in both.

- **Both reproduce:** every digest unchanged, SALR 4 tables, CHWK 10 (`streams_access`, `streams_mapping_code`, eight `streams_habitat_<sp>`). Backups dropped; `zz261_backup` dropped (empty).
- **SALR 46.3 s** (logged 0.72 min at `-j8`): walks 28.2, the rest of `lnk_pipeline_access()` 1.6, setup and UPDATE 3.8, gate 2.8, mapping code 7.2, guard 2.0, prior copy 0.2.
- **CHWK 617.6 s** (logged 15.56 min at `-j8`, 9.26 at `-j4`): walks 589.4 (95 %), the rest of `lnk_pipeline_access()` 2.1, setup and UPDATE 8.3, gate 8.0, mapping code 7.5, guard 1.5, prior copy 0.5. Steps sum to 617.3 s of 617.6 s wall clock.
- **Client share of the walks:** CHWK's R-timed walks 589.4 s against the harness's server-side 551.4 s, so about 38 s (6 %) is transfer and parsing of the arrays; SALR's R-timed 28.2 s is below its server-side 31.0 s (different moment, same order). The client side is not the cost.
- **So CHWK's 13× over SALR in this re-run (617.6 / 46.3) is the walks**: 561 s more walk time, 13 s more everything else.
