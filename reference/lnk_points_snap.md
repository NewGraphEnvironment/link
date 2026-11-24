# Snap a Postgres table of points to the FWA stream network

Bulk-snap helper: takes a Postgres table of point geometries and creates
a new table with each row enriched with the nearest FWA stream segment's
`linear_feature_id`, `blue_line_key`, `downstream_route_measure`,
`wscode_ltree`, `localcode_ltree`, `watershed_group_code`, `gnis_name`,
plus snap distance.

## Usage

``` r
lnk_points_snap(
  conn,
  table_in,
  table_out,
  id_col,
  geom_col = "geom",
  snap_tolerance = 100,
  exclude_edge_types = 1425L,
  blue_line_key_col = NULL,
  stream_order_min = NULL,
  num_features = 1L
)
```

## Arguments

- conn:

  A DBI connection.

- table_in:

  Fully-qualified `<schema>.<table>` of input points.

- table_out:

  Fully-qualified `<schema>.<table>` to create. Existing table is
  `DROP TABLE IF EXISTS`'d first.

- id_col:

  Name of a column in `table_in` that identifies each point. Its values
  must be unique and non-missing; the function stops otherwise.

- geom_col:

  Name of the geometry column in `table_in`. Default `"geom"`. A
  MultiPoint is snapped by its first point.

- snap_tolerance:

  Maximum snap distance in metres. Points farther than this from the
  network are dropped. Default `100`.

- exclude_edge_types:

  Integer vector of `edge_type` codes to exclude from the FWA network
  when snapping. Default `1425L` (subsurface flow). Pass `integer(0)` to
  exclude none.

- blue_line_key_col:

  Optional name of a `blue_line_key` column in `table_in` to constrain
  candidate streams to. `NULL` (default) snaps to any FWA stream within
  tolerance. A point whose hint is missing snaps to any stream.

- stream_order_min:

  Optional minimum `stream_order` to include. `NULL` (default) accepts
  any order.

- num_features:

  Integer scalar. Maximum number of stream candidates per input point.
  Default `1L` (nearest only). Set higher (e.g. `5L`) to score and pick
  among nearby streams. Output then has one row per (input row,
  candidate stream) pair and a `candidate_rank` column (1 = nearest).

## Value

`invisible(table_out)`. Side effect: creates `table_out` in `conn`'s
database.

## Details

The snap itself is
[`fresh::frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.html):
one lateral nearest-neighbour query for the whole table. This function
keeps every column of `table_in` beside the snap, under link's column
names, so a pipeline can carry the points' own attributes through. The
candidate rules are fresh's:

- placeholder streams (`wscode_ltree <@ '999'`) and unmapped tributaries
  (`localcode_ltree IS NULL`) are never candidates;

- `edge_type NOT IN (exclude_edge_types)` drops more;

- an exact distance tie, a point nearest to the vertex two segments
  share, goes to the segment with the higher `downstream_route_measure`
  (on one stream, the one starting at that vertex), then the lower
  `linear_feature_id`. This is fwapg's rule for `fwa_indexpoint()`.
  Across two streams the higher measure means nothing; the PSCIS pick,
  which reads every candidate, orders such a tie by which segment starts
  at the vertex.

The measure is a whole metre, as in bcfishpass's `04_pscis.sql`.

Output table columns: every column from `table_in` PLUS
`linear_feature_id`, `snapped_blue_line_key`,
`downstream_route_measure`, `wscode_ltree`, `localcode_ltree`,
`watershed_group_code`, `gnis_name`, `distance_to_stream` (metres),
`candidate_rank` (when `num_features > 1`) and `geom_snapped` (the point
projected onto the segment, EPSG:3005). An input table holding any of
those names is refused. The snap is written first to a scratch table
beside `table_out`, which is dropped on exit.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
lnk_points_snap(
  conn,
  table_in  = "whse_fish.pscis_assessment_svw",
  table_out = "working_adms.pscis_assessment_snapped",
  id_col = "stream_crossing_id",
  snap_tolerance = 150,
  num_features = 5L
)
} # }
```
