# Review: commit 21e0fea2 (round 4), `.lnk_sql_locate()` in `lnk_barriers_unify()`

## Checklist read

- `idx_code-check.md`: all 37 index headings read. In full: the prose of every H3 under `## Mechanisms`. "A fixture that cannot reach the failure mode" is the one that applies here. Not read in full: the 23 standalone, security and spreadsheet sections, which concern no tool this diff uses.
- `idx_code-check-r.md`: all 111 index headings read. In full: "Postgres row order is never fixed unless the query fixes it" and the `sprintf("%g")` / `information_schema` neighbours. Not read in full: 108.
- `idx_code-check-spatial.md`: all 93 index headings read. In full: "FWA `upstream_route_measure` misses the next segment's start". Not read in full: 92.

## Findings

- **[severity: bug]** R/lnk_barriers_unify.R:227 and :322, with the helper at :348-362. The gradient and subsurface branches pass the unqualified names `"blue_line_key"` and `"downstream_route_measure"` to `.lnk_sql_locate()`. Inside the fallback subquery, `FROM whse_basemapping.fwa_stream_networks_sp n` has columns with those same names, and SQL resolves an unqualified name to the innermost scope. So the fallback reads n's columns, not the barrier's:
  - `WHERE n.blue_line_key = blue_line_key` becomes `n.blue_line_key = n.blue_line_key`, which is true for every row.
  - The fraction `(downstream_route_measure - n.downstream_route_measure)` is always 0.
  - The `ORDER BY least(abs(..)…)` key is 0 for every row, so `n.linear_feature_id` decides alone.

  The subquery is no longer correlated, so Postgres plans it as an InitPlan. It runs a parallel seq scan and sort over all 4.9 M FWA rows, and returns the start point of the lowest `linear_feature_id` in BC. Every gradient or subsurface row that reaches the fallback gets that one point, `POINT(559276.48 1692679.657)` on ATLL blue line 360670233. Those are exactly the rows this commit exists to keep.

  **How I verified it:**
  - `EXPLAIN VERBOSE` of the rendered helper over `(VALUES (360611439, 1153.64)) AS g(blue_line_key, downstream_route_measure)` shows `InitPlan 2` as `Parallel Seq Scan on fwa_stream_networks_sp n`. The scan has no blue_line_key filter, and its expressions read `(n.downstream_route_measure - n.downstream_route_measure)`.
  - The live table shows it too. `working_pcea.barriers`, rebuilt at this commit, has 82,913 GRADIENT rows (the full raw count). 40 of them sit within 1 m of that ATLL point: 31 with NULL `wscode_ltree` and 9 with one. That matches `unify_dropped_rows.csv` for PCEA (31 + 9).
  - With the outer references qualified, the same call (`f.blue_line_key` over the same VALUES) returns `POINT(895589.7049 998631.6400)`. That is the end of the MORR segment below the gap, as intended.
  - Falls and user-definite are unaffected: they pass `f.` / `d.`-qualified names.

  **What it affects.** Access is still right, because access reads ltree, blue line and measure, not geom. The geometry is wrong in `<schema>.barriers`, in `<persist>.barriers` and in the `barriers_<sp>_access` views (QGIS, exports, the GiST index). The run also pays one extra full-table scan and sort per unify call.

  **Fix:** alias the source tables (`FROM %3$s.gradient_barriers_raw g`, `FROM %3$s.barriers_subsurfaceflow b`) and pass `g.blue_line_key` / `g.downstream_route_measure` (and the `b.` equivalents). Or make the helper refuse an unqualified argument (`stopifnot(grepl("\\.", blk), grepl("\\.", measure))`), so the shape cannot come back.

- **[severity: fragile]** tests/testthat/test-lnk_barriers_unify.R:228-243. This is a fixture that cannot reach the failure mode. The live test calls `.lnk_sql_locate("360611439", "1153.64")` with literals, so no column name can collide, and it only checks `^POINT\(`, not where the point is. The mocked test counts `FROM FWA_LocateAlong\(` and passes on the buggy SQL. Both tests stay green with the bug above.

  To make them able to fail, run the helper with the arguments a branch really passes, over a row source whose columns carry the production names, for example `SELECT %s FROM (VALUES (360611439, 1153.64::float8)) g(blue_line_key, downstream_route_measure)`. Then assert the gap point lies within about 1 cm of the segment-below's end (or `ST_DWithin` of `FWA_LocateAlong(360611439, 1153.65)`).

- **[severity: fragile]** R/lnk_barriers_unify.R:253-258 and :292-296, with RUNBOOK.md:153. The RUNBOOK now says "Every staged barrier row is persisted, located or not". The falls and user-definite branches still `JOIN fwa_stream_networks_sp s ON measure >= s.drm AND measure < s.urm`, which is an inner join. A falls or user-definite point in the same few-millimetre gap matches no segment and is dropped before `.lnk_sql_locate()` runs, so for those two sources the change does nothing at the gap.

  The impact is latent today. A count of falls / `barriers_definite` rows with no `[drm, urm)` segment in 12 working schemas (BULK, ELKR, FINA, KISP, KOTR, LARL, LFRA, LKEL, MORR, PARS, PCEA, USKE; 347 falls, 94 definite) found 0. Either use a `LEFT JOIN LATERAL (… ORDER BY s.downstream_route_measure, s.linear_feature_id LIMIT 1)` with a nearest-segment fallback, or narrow the RUNBOOK sentence to the gradient and subsurface sources.

## Checked, no issue

- **sprintf numbering:** `%1$s`–`%4$s` in all four templates pass the intended arguments. In the helper, `%1$s` is the blue line and `%2$s` the measure, in both subqueries.
- **id_barrier stability:** Postgres evaluates window functions before a target-list SRF. A probe, `SELECT g, row_number() OVER (ORDER BY g), generate_series(1, CASE WHEN g=2 THEN 0 ELSE 1 END) FROM generate_series(1,3) g`, returns ids 1 and 3. So the old code already numbered the dropped rows, and keeping them changes no existing id.
- **Determinism:** the fallback's `ORDER BY` ends on `linear_feature_id`, the primary key. `FWA_LocateAlong` uses `DISTINCT ON (blue_line_key)` and returns at most one row, so `LIMIT 1` cannot pick arbitrarily.
- **Indexes and evaluation:** `fwa_stream_networks_sp` has btree indexes on `(blue_line_key)` and `(blue_line_key, downstream_route_measure)`. The qualified fallback is correlated and evaluated only when the first COALESCE arm is NULL.
- **Geometry type:** the MORR segment is a single `LineString`, and `ST_GeometryN(line, 1)` returns the line. `ST_Force2D(...)::geometry(Point, 3005)` is valid.
- **Nullability:** a line with no FWA segment gives a NULL geom, and `cols_barriers` has no `NOT NULL` on `geom` or `wscode_ltree`, so such rows persist without error.
