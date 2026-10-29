# What a group's recompute costs, and why

**Verified:** 2026-10-29 · **Issues:** #261, #409, #394 (tracked on #377) · **Produced by:**
`data-raw/logs/recompute_cost_261/` (the cost model, on the 2026-10-23 `default` build,
`20261023_074321-24d85e8c`) and `data-raw/logs/recompute_access_394/` (what the fixes
bought, on the same build). Each log directory's README indexes its scripts and outputs.

## The answer

A group's post-consolidate recompute is mostly its downstream walks: 95 % of CHWK's
re-run (589 of 618 s) and 61 % of SALR's (28 of 46 s). One walk per present species view
plus three sources. Across 240 groups, a walk timing per group predicts the recompute's
minutes at Spearman 0.982, against 0.993 between two provincial runs.

The cost is **not** the barriers downstream of a group, which was #261's hypothesis.
Counted with the walk's own predicate, they correlate at −0.08, and seven of nine
decomposed groups have none. It is the shape of the walk.

That describes the walks up to fresh 0.44.0. Three changes since have cut the access step by 5.6× (SETN)
to 57× (CHWK): see "What fixed it".

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

## What fixed it

Three changes. On SALR, CHWK, LFRA and SETN each one returned the same output digest as
fresh 0.44.0's walks (`data-raw/logs/recompute_access_394/`). The access step, in seconds,
mean of two runs (four for existence walks):

| group | fresh 0.44.0 | prefilter (fresh 0.47.0) | existence walks | one walk per set |
|---|---|---|---|---|
| SALR | 26.9 | 3.9 | 4.0 | 4.0 |
| CHWK | 535.0 | 21.5 | 19.6 | 9.3 |
| LFRA | 1,145.7 | 89.5 | 74.5 | 35.3 |
| SETN | 763.6 | 347.3 | 292.0 | 136.5 |

- **The prefilter** (fresh#272, fresh v0.45.0; link #409) cuts the feature side to what
  `fwa_downstream()` can return before the join: features on one of the group's blue
  lines, or whose wscode is an ancestor of, or equal to, a group segment's. Both are
  index lookups. It is most of the gain where the cost was the probe (CHWK 25×, LFRA 13×,
  SALR 7×), and 2.2× in SETN, whose cost is the output. #261 estimated it would save 36 to 51 %
  of the 2026-10-23 pool's summed work. The next provincial run measures that (#377). It adds a fixed cost to every walk
  (fresh builds a group-scoped temp table each time), so small source walks got slower
  (SETN's `pscis` walk 0.2 → 3.3 s), a few seconds against hundreds saved.
- **Existence walks** (fresh#281, fresh v0.47.0; link #394). link reads the per-species
  views and `pscis` only as "is any feature downstream", so those walks take
  `result = "exists"`: the same join, reduced to distinct segments instead of
  arrays. The join still enumerates every (segment, feature) pair, so SETN gains 1.2×. SETN's species
  walks went from 327 to 270 s and LFRA's from 83 to 68 s. The arrays stay where link
  reads elements: `anthropogenic` and `dams` (`dam_dnstr_ind`), `remediations`
  (`remediated_dnstr_ind`) and the upstream observation walk.
- **One walk per distinct barrier set** (link #394). The species views over one barriers
  table often hold the same rows: CH, CM, CO, PK and SK are one shape before overrides,
  and overrides rarely reach a group. At the existence step, walks repeating an earlier
  walk's segments were 58 % of walk seconds in CHWK, LFRA and SETN, and 0 in SALR. link
  now digests each view's rows that `fwa_downstream()` could admit from the group, and
  walks once per distinct digest. That halves the access step
  in CHWK, LFRA and SETN (7 walks instead of 11). The digest query costs 0.7 to 9.2 s
  there, and 0.16 s in SALR, where nothing repeats.

Scratch models of ADMS and ELKR, built at each of the four steps, digest identical in every persisted
table, so none of the three changes moves an output.

Up to fresh 0.44.0 the walk's `ORDER BY` had no unique tiebreak, so co-located features
came back in plan order. link reads only the anthropogenic array's first element, and that
order matched in all nine groups tried. Since fresh 0.45.0 the order ends on the feature
id (fresh#272).
