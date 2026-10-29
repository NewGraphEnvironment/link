# What a group's recompute costs, and why

**Verified:** 2026-10-27; "Measured since fresh#272" and "Measured since #394" 2026-10-29 ·
**Issues:** #261, #409, #394 (tracked on #377) · **Produced by:**
`data-raw/logs/recompute_cost_261/`, `data-raw/logs/prefilter_409/` and
`data-raw/logs/recompute_access_394/` (each README indexes its scripts and outputs), on the
2026-10-23 `default` build (`20261023_074321-24d85e8c`); #409's model-time builds and one tie
count ran on m4's local database, as its README says.

## The answer

A group's post-consolidate recompute is mostly its downstream walks: 95 % of CHWK's
re-run (589 of 618 s) and 61 % of SALR's (28 of 46 s). One walk per present species view
plus three sources. Across 240 groups, a walk timing per group predicts the recompute's
minutes at Spearman 0.982, against 0.993 between two provincial runs.

The cost is **not** the barriers downstream of a group, which was #261's hypothesis.
Counted with the walk's own predicate, they correlate at −0.08, and seven of nine
decomposed groups have none. It is the shape of the walk.

That describes the walks up to fresh 0.44.0. "Measured since fresh#272" and "Measured since
#394" below give what has cut them since: the access step is now 5.6× (SETN) to 57× (CHWK)
faster than it was then.

## The mechanism

`fresh::frs_network_features()` joins the group's segments to the walked feature table
on `whse_basemapping.fwa_downstream()`. The planner drives from the feature side, which
holds every feature in the province (7.24 M rows for the CH view). It probes the group's
segments once per feature through a `BitmapOr` on `blue_line_key` and
`wscode_ltree <@ b.wscode_ltree`. So each walk costs:

- **the view's size**, 5.5 to 8.4 s for a CH-sized view across the nine groups measured;
- **the view's size times the per-feature cost of probing the group's segments** (the
  CH walk's inner side over its 7.24 M features): 1.8 µs in SALR, 10.3 µs in CHWK, up to
  21 µs in LFRA. It is highest in groups that own
  segments of a main stem, such as the Fraser (`100`) and the lower Skeena (`400`), and
  in groups with coastal codes beside them. The group's code range does not predict it:
  SETN's range is narrow, and its walks cost about what CHWK's do under the same load;
- **the output pairs**, which dominate only where many features sit inside the group
  above many segments (SETN: 4.83 M pairs, a 526 MiB sort spill).

CHWK's natural walks cost 18× SALR's (546 against 30 s): each CH walk costs 4.1× SALR's
(its probes 5.7×), and its eight natural views hold 4.5× the province-wide rows of SALR's
two.

## What would fix it

Cut the feature side to what `fwa_downstream()` can return, before the join: features
on one of the group's blue lines, or whose wscode is an ancestor of, or equal to, a group
segment's wscode. Both are index lookups on the feature table (the wscode arm through
its GiST, the blue line through its btree). Measured on nine groups, this returns the same
features per segment in all 32 walks tried, and in eight of them a group's walks run 3.6×
(SPAT) to 24.6× (CHWK) faster in total. SETN gains only 1.2×, because its cost is output. Over the 2026-10-23 pool
(50,352 s of summed job time), it would save an estimated 18,221 to 25,534 s (36 to
51 %). The saving is spread across groups (the ten costliest hold 18 % of walk time), and CHWK is 1.9 % of the pool.

Two further levers, measured since (#394, below): link keeps only whether a natural array is
empty (`has_barriers_<sp>_dnstr`), so an existence test can skip building the arrays; and CH,
CM, CO, GR, KO, PK and SK walk barrier sets that are identical before overrides.

Until fresh 0.45.0 the walk's `ORDER BY` had no unique tiebreak, so co-located features
came back in plan order; since then it ends on the feature id. link reads two arrays'
first element. `dam_dnstr_ind`'s set has no co-located pair on the 2026-10-23 build (below).
`remediated_dnstr_ind` is computed at model time only (the recompute keeps it); its sets in
the 134 working schemas the dispatcher had kept, from builds of unrecorded date, have none.

## Measured since fresh#272

fresh v0.45.0 (fresh#272) built the fix above into `frs_network_features()`: a downstream
walk given `aoi` copies the group's segments into an indexed, analyzed session temp table
and walks only the features on one of the group's blue lines or on an ancestor-or-equal
watershed code, the two conditions `fwa_downstream()` needs. link passes `aoi` on every
downstream walk, so adopting it was the pin (v0.46.0, which also carries fresh#242). Five
groups' whole recompute, run alternately under fresh v0.44.0 and v0.46.0 on the dispatcher,
serially from m4: four times each (each version's fastest run):

| group | total, 0.44.0 (s) | total, 0.46.0 (s) | | walks, 0.44.0 (s) | walks, 0.46.0 (s) | |
|---|---|---|---|---|---|---|
| SALR | 42 | 23 | 1.8× | 28 | 10 | 2.9× |
| LKEL | 111 | 46 | 2.4× | 88 | 25 | 3.6× |
| LSKE | 580 | 178 | 3.3× | 518 | 117 | 4.4× |
| CHWK | 686 | 75 | 9.2× | 658 | 45 | 14.7× |
| SETN | 1,424 | 804 | 1.8× | 1,274 | 666 | 1.9× |
| all five | 2,843 | 1,126 | 2.5× | 2,566 | 863 | 3.0× |


- **Outputs did not move.** Every run left every table it writes digest-identical, and every
  walk returned the same features per segment under both versions. Three groups built twice at
  model time (ADMS, NATR, ELKR) digest identical in the five table kinds compared (streams,
  barriers, access, mapping code, habitat; not `barrier_overrides`, which is link's, or
  `streams_near_river`, written by fresh code unchanged between the pins). Element order
  changed between versions in 9 per-species natural walks, whose arrays link reduces to
  membership. No two anthropogenic features share a position on the dispatcher's build
  (502,233 rows, 241 groups), so `dam_dnstr_ind`, which reads an array's first element,
  cannot move there.
- **Below #261's estimate.** The natural walks, summed per group, gain 4.7× to 17× (SETN 2.2×,
  output-bound as predicted), against 6.3× to 24.6× server-side for the prefiltered walk
  alone. Every PSCIS and dam walk got slower, by 1.0 to 1.3 s in SALR, LKEL and CHWK, 2.0 to
  2.4 in LSKE and 3.5 to 3.9 in SETN, and a group makes 5 to 11 walk calls; the anthropogenic
  walk got slower in four groups of five (CHWK's went 4.4 → 1.8 s). What costs it is not
  measured here: fresh's own timing of its temp-table build is 0.07 to 0.7 s on a
  province-wide `fresh_default` with no other client active (fresh
  `data-raw/logs/network_features_272/`), less than the rise. Walking each barrier set once
  (#394) makes fewer calls.
- **The walks are no longer nearly all of a recompute:** under 0.46.0 they are 41 % (SALR) to
  83 % (SETN) of these runs, against 66 to 96 % under 0.44.0.
- **The provincial share is not measured here.** These runs are serial; the pool runs at
  `-j8` on the dispatcher, where the database contends (#374). The next provincial run's
  `log_recompute` against 2026-10-23's gives it.

## Measured since #394

link 0.69.7 pins fresh v0.47.0 and changes how `lnk_pipeline_access()` walks. Measured on
the access step alone (`lnk_pipeline_access()` as `lnk_access(merge = FALSE)` runs it, under
its own table names) on the dispatcher's 2026-10-23 build, each variant run twice per group
in the order A-B-C-C-B-A, then `exists` against `dedup` the same way. Seconds, mean of the
runs:

| group | fresh 0.44.0 | prefilter (fresh 0.47.0) | existence walks | one walk per set |
|---|---|---|---|---|
| SALR | 26.9 | 3.9 | 4.0 | 4.0 |
| CHWK | 535.0 | 21.5 | 19.6 | 9.3 |
| LFRA | 1,145.7 | 89.5 | 74.5 | 35.3 |
| SETN | 763.6 | 347.3 | 292.0 | 136.5 |

- **Existence walks** (fresh#281, fresh v0.47.0). link reads the per-species views and `pscis`
  only as "is any feature downstream", so those walks take `result = "exists"`: the same
  join, reduced to distinct segments instead of arrays. The join still enumerates every
  (segment, feature) pair, so SETN gains 1.2×, not the removal of its pairs predicted above.
  SETN's species walks went from 327 to 270 s and LFRA's from 83 to 68 s. The arrays stay
  where link reads elements: `anthropogenic` and `dams` (`dam_dnstr_ind`), `remediations`
  (`remediated_dnstr_ind`) and the upstream observation walk.
- **One walk per distinct barrier set.** The species views over one barriers table often hold
  the same rows: CH, CM, CO, PK and SK are one shape before overrides, and overrides rarely
  reach a group. At the existence step, walks repeating an earlier walk's segments were 58 %
  of walk seconds in CHWK, LFRA and SETN, and 0 in SALR. link now digests each view's rows
  that `fwa_downstream()` could admit from the group, and walks once per distinct digest.
  That halves the access step in CHWK, LFRA and SETN (7 walks instead of 11). The digest
  query costs 0.7 to 9.2 s there, and 0.16 s in SALR, where nothing repeats.
- **Outputs did not move.** Every run's output digest equals the fresh 0.44.0 baseline's, and
  scratch models of ADMS and ELKR built at each of the four steps digest identical in every
  persisted table.
- **The prefilter's per-walk cost** shows here too: SETN's `pscis` walk went from 0.2 to 3.3 s.
  One walk per set makes four fewer calls in the three groups with repeats.
