# What a group's recompute costs, and why

**Verified:** 2026-10-27 · **Issues:** #261 (tracked on #377) · **Produced by:**
`data-raw/logs/recompute_cost_261/` (its README indexes the scripts and outputs), on the
2026-10-23 `default` build (`20261023_074321-24d85e8c`).

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

- **the view's size**, about 6 s for a CH-sized view, the same in every group;
- **the view's size times the per-probe cost of the group's wscode GiST**: 0.001 ms in
  SALR and 0.009 ms in CHWK, up to 0.019 ms in LFRA. It is highest in groups that own
  segments of a main stem, such as the Fraser (`100`) and the lower Skeena (`400`), and
  in groups with coastal codes beside them. The group's code range does not predict it:
  SETN's range is narrow and its probe is among the dearest;
- **the output pairs**, which dominate only where many features sit inside the group
  above many segments (SETN: 4.83 M pairs, a 539 MB sort spill).

CHWK costs about 20× SALR because its probe costs about 9× and it walks 8 natural views
to SALR's 2.

## What would fix it

Cut the feature side to what `fwa_downstream()` can return, before the join: features
on one of the group's blue lines, or whose wscode is an ancestor of, or equal to, a group
segment's wscode. Both are btree lookups. Measured on nine groups, this returns the same
features per segment in all 33 walks tried, and walks run 3.6× (SPAT) to 24.6× (CHWK)
faster. SETN gains only 1.2×, because its cost is output. Over the 2026-10-23 pool
(50,352 s of summed job time), it would save an estimated 18,221 to 25,534 s (36 to
51 %). The saving is spread over every group, and CHWK is 1.9 % of the pool.

Two further levers, not measured: link keeps only whether a natural array is empty
(`has_barriers_<sp>_dnstr`), so an existence test would remove SETN's pairs; and CH, CM,
CO, GR, KO, PK and SK walk barrier sets that are identical before overrides.

The walk's `ORDER BY` has no unique tiebreak, so co-located features come back in plan
order. link reads only the anthropogenic array's first element, and that order matched
in all nine groups tried.
