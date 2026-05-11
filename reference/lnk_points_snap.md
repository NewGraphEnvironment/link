# Snap a Postgres table of points to the FWA stream network

Bulk-snap helper: takes a Postgres table of point geometries and creates
a new table with each row enriched with the nearest FWA stream segment's
`linear_feature_id`, `blue_line_key`, `downstream_route_measure`,
`wscode_ltree`, `localcode_ltree`, plus snap distance.

## Usage

``` r
lnk_points_snap(
  conn,
  table_in,
  table_out,
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

- geom_col:

  Name of the geometry column in `table_in`. Default `"geom"`.

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
  tolerance.

- stream_order_min:

  Optional minimum `stream_order` to include. `NULL` (default) accepts
  any order.

- num_features:

  Integer scalar. Maximum number of stream candidates per input point.
  Default `1L` (nearest-only — backwards compatible). Set higher (e.g.
  `5L`) for downstream scoring/dedup workflows that need multiple
  candidates per point (e.g. bcfp PSCIS-to-stream selection where
  stream-name match disambiguates among nearby streams). Output has one
  row per (input row, candidate stream) pair, ordered by distance
  ascending.

## Value

`invisible(table_out)`. Side effect: creates `table_out` in `conn`'s
database.

## Details

Uses a single SQL `CROSS JOIN LATERAL ... ORDER BY <-> ... LIMIT 1`
against `whse_basemapping.fwa_stream_networks_sp` — same lateral-KNN
pattern as `bcfishpass`'s `load_dams.sql` and link's existing CABD dams
snap in
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md).
One round-trip; scales to province-wide point sets.

Generic — not specific to any pipeline phase. Likely belongs in a future
`pac` package once that's scaffolded; ships in link for now.

Output table columns: every column from `table_in` PLUS
`linear_feature_id` (bigint), `blue_line_key` (integer),
`downstream_route_measure` (numeric), `wscode_ltree` (ltree),
`localcode_ltree` (ltree), `distance_to_stream` (numeric, metres),
`geom_snapped` (geometry — point projected onto the segment).

Filters applied to candidate streams (from `fresh::frs_point_snap_knn`
conventions):

- `wscode_ltree != '999'` (placeholder streams excluded)

- `localcode_ltree IS NOT NULL` (unmapped tributaries excluded)

- `edge_type NOT IN (exclude_edge_types)` (subsurface etc. excluded)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
lnk_points_snap(
  conn,
  table_in  = "whse_fish.pscis_assessment_svw",
  table_out = "working_adms.pscis_assessment_snapped",
  snap_tolerance = 100,
  exclude_edge_types = c(1410L, 1425L)
)
} # }
```
