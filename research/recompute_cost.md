# What a group's recompute costs, and why

**Verified:** 2026-10-27; "Measured since fresh#272" 2026-10-29 · **Issues:** #261, #409
(tracked on #377) · **Produced by:** `data-raw/logs/recompute_cost_261/` and
`data-raw/logs/prefilter_409/` (each README indexes its scripts and outputs), on the
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

Two further levers, not measured: link keeps only whether a natural array is empty
(`has_barriers_<sp>_dnstr`), so an existence test would remove SETN's pairs; and CH, CM,
CO, GR, KO, PK and SK walk barrier sets that are identical before overrides.

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
serially from m4: four times each for SALR, LKEL, LSKE and CHWK, twice so far for SETN (each
version's fastest run):

| group | total, 0.44.0 (s) | total, 0.46.0 (s) | | walks, 0.44.0 (s) | walks, 0.46.0 (s) | |
|---|---|---|---|---|---|---|
| SALR | 42 | 23 | 1.8× | 28 | 10 | 2.9× |
| LKEL | 111 | 46 | 2.4× | 88 | 25 | 3.6× |
| LSKE | 580 | 178 | 3.3× | 518 | 117 | 4.4× |
| CHWK | 686 | 75 | 9.2× | 658 | 45 | 14.7× |
| SETN ¹ | 1,481 | 891 | 1.7× | 1,332 | 774 | 1.7× |
| all five | 2,900 | 1,213 | 2.4× | 2,624 | 970 | 2.7× |

¹ One run per version so far (b1, a1); the second pair waits for a quiet database. Another
client was active on the dispatcher by the end of the 0.46.0 run, so its 891 s may be high.

- **Outputs did not move.** Every run left every table it writes digest-identical, and every
  walk returned the same features per segment under both versions. Three groups built twice at
  model time (ADMS, NATR, ELKR) digest identical in the five table kinds compared (streams,
  barriers, access, mapping code, habitat; not `barrier_overrides`, which is link's, or
  `streams_near_river`, written by fresh code unchanged between the pins). Element order
  changed between versions in 9 per-species natural walks, whose arrays link reduces to
  membership. No two anthropogenic features share a position on the dispatcher's build
  (502,233 rows, 241 groups), so `dam_dnstr_ind`, which reads an array's first element,
  cannot move there.
- **Below #261's estimate.** The natural walks, summed per group, gain 4.7× to 17× (SETN 1.8×,
  output-bound as predicted), against 6.3× to 24.6× server-side for the prefiltered walk
  alone. Every PSCIS and dam walk got slower, by 1.0 to 1.3 s in SALR, LKEL and CHWK, 2.0 to
  2.4 in LSKE and 3.5 to 4.2 in SETN, and a group makes 5 to 11 walk calls; the anthropogenic
  walk got slower in four groups of five (CHWK's went 4.4 → 1.8 s). What costs it is not
  measured here: fresh's own timing of its temp-table build is 0.07 to 0.7 s on a
  province-wide `fresh_default` with no other client active (fresh
  `data-raw/logs/network_features_272/`), less than the rise. Walking each barrier set once
  (#394) makes fewer calls.
- **The walks are no longer nearly all of a recompute:** under 0.46.0 they are 41 % (SALR) to
  87 % (SETN) of these runs, against 66 to 96 % under 0.44.0.
- **The provincial share is not measured here.** These runs are serial; the pool runs at
  `-j8` on the dispatcher, where the database contends (#374). The next provincial run's
  `log_recompute` against 2026-10-23's gives it.
