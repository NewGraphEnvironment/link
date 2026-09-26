**If we do it:** there is one way to put points on the FWA network, and it takes a whole dataset (data frame, `sf`, or table) and returns everything a downstream consumer needs. Validation, crossings, stations and eDNA all compose it the same way. **If we never do:** snapping stays duplicated. One copy is single-point in fresh and one is bulk in link, each missing fields and with different defaults, and `frs_feature_find(points = )` stays broken.

## Problem

Pinned at fresh@48d05bd (v0.34.0) and link@d864822.

Two snappers exist, and neither is the primitive callers need:

| | `fresh::frs_point_snap()` | `link::lnk_points_snap()` |
|---|---|---|
| input | one `x`, `y` (length-1 numerics) | a Postgres table of geometries |
| output | `sf`: `linear_feature_id`, `gnis_name`, `blue_line_key`, `downstream_route_measure`, `distance_to_stream`, `geom` | a new table: `linear_feature_id`, `blue_line_key`, `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`, distance |
| default tolerance | 5000 m | 100 m |
| `watershed_group_code` | no | no |
| candidates | `num_features` | `num_features` |
| filters | `blue_line_key`, `stream_order_min`, `exclude_edge_types` | `blue_line_key_col`, `stream_order_min`, `exclude_edge_types` |

- **Per-point calls do not scale.** A 1,000-point dataset is 1,000 round trips. That is why link grew its own bulk copy, and its roxygen already says it "likely belongs in a future `pac` package".
- **Nothing returns `watershed_group_code`.** Every consumer that partitions by WSG has to re-join it from `fwa_stream_networks_sp`. `lnk_habitat_validate()` (link#283) requires it for observations from any non-bcfishobs source.
- **The tolerances differ by 50x.** bcfishobs's A/B matches are within 100 m; `frs_point_snap()`'s 5 km default pins a point that is well off the network to some stream anyway.
- **A live bug that the single-point signature caused.** `.frs_feature_find_points()` (`R/frs_feature_find.R:183`) calls `frs_point_snap(conn, points)` with the `sf`. That always fails with `x must be a single numeric value`, so `frs_feature_find(points = <sf>)` does not work at all. The only test (`test-frs_break.R:120`) checks that non-`sf` input is rejected.

Prior work: #2 introduced `frs_point_snap()`; #7, #16, #17 and #18 added candidates, the `blue_line_key` hint and `stream_order_min`; #207 added `frs_candidates_pick()` for scoring and deduplicating candidates. What is missing is the bulk shape and a complete output.

## Proposed solution

One bulk snap, with the candidate / pick split #207 already set up:

- **Input:** a data frame with coordinate columns plus `srid`, an `sf`, or a schema-qualified table. One call, one query, with the lateral KNN pattern `lnk_points_snap()` already uses.
- **Output:** the input's own id, plus `blue_line_key`, `downstream_route_measure`, `watershed_group_code`, `linear_feature_id`, `wscode_ltree`, `localcode_ltree`, `distance_to_stream`, and the candidate rank when `num_features > 1`. Returned as an `sf` / data frame, or written to `to =` for a table input.
- **Options, carried over:** `tolerance`, `num_features`, a per-row `blue_line_key` hint column, `stream_order_min`, `exclude_edge_types`. Scoring stays in `frs_candidates_pick()`.
- **Decide at design time:**
  - Keep the name `frs_point_snap()` and vectorize it, or add a sibling. Its current single-point callers are `frs_watershed_split()` and the broken `frs_feature_find()` path.
  - The default tolerance. 100 m matches bcfishobs A/B.

Then:
- `frs_feature_find(points = )` works through it.
- link's `lnk_points_snap()` becomes a thin wrapper or is removed. That is link-side work, tracked there.
- Callers compose snap → consumer. `lnk_habitat_validate()` takes network-located records and does not snap.

## Acceptance

- One call snaps N points in one query and returns the columns above, including `watershed_group_code`.
- `frs_feature_find(points = <sf>)` has a test that snaps real points, not only one that rejects non-`sf` input.
- Parity: on the PSCIS inputs link snaps today, the bulk snap gives the same `blue_line_key` and measure as `lnk_points_snap()`.

Relates to link#283.
