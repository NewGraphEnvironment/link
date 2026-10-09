# Roll up per-(WSG, species) length metrics from persisted state

Reusable, predicate-driven roll-up over link's persisted per-species
tables. For each species it joins `<schema>.streams` (length + edge
type) to `<schema>.streams_habitat_<sp>` (spawning / rearing flags) and
**left-joins** `<schema>.streams_access` (per-species `access_<sp>`
code) on the full PK `(id_segment, watershed_group_code)` (#203),
exposes the three species-varying inputs under **generic aliases** —
`access` (int: -9 absent / 0 blocked / 1 modelled / 2 observed),
`spawning`, `rearing` (bool) — then aggregates by
`(watershed_group_code, species_code)`.

## Usage

``` r
lnk_rollup_wsg(
  conn,
  aoi,
  species,
  schema = "fresh",
  metrics = c(accessible_km =
    "round(sum(length_metre) FILTER (WHERE access IN (1, 2))::numeric / 1000, 2)",
    spawning_km = "round(sum(length_metre) FILTER (WHERE spawning)::numeric / 1000, 2)",
    rearing_km =
    "round(sum(length_metre) FILTER (WHERE rearing AND NOT connection)::numeric / 1000, 2)",
    rearing_lake_connection_km =
    "round(COALESCE(sum(length_metre) FILTER (WHERE rearing AND connection), 0)::numeric / 1000, 2)"),
  where = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)).

- aoi:

  Watershed group code (e.g. `"MORR"`). Uppercase 3-5 letters.

- species:

  Character vector of species codes (e.g. `c("CO","BT")`). Each must
  name existing `<schema>.streams_habitat_<sp>` and
  `<schema>.streams_access.access_<sp>`. Restricted to alpha characters
  — interpolated into identifiers, so validated to make SQL injection
  structurally impossible.

- schema:

  Persist schema holding `streams`, `streams_access`,
  `streams_habitat_<sp>`. Default `"fresh"`. Validated against the SQL
  identifier whitelist.

- metrics:

  Named character vector: names are output columns, values are SQL
  aggregate expressions over the generic aliases `length_metre`,
  `edge_type`, `waterbody`, `connection`, `access`, `spawning`,
  `rearing`. Default emits `accessible_km`, `spawning_km`, `rearing_km`
  (lines flagged `rearing`, lake connection lines left out) and
  `rearing_lake_connection_km` (the connection lines flagged `rearing`).
  Raw SQL — trusted caller input, like `frs_aggregate()`.

- where:

  Character or `NULL`. Optional SQL predicate applied to the per-species
  rows before aggregation (aliases available). Default `NULL`.

## Value

A data.frame with one row per `(wsg, species)` and one column per
metric. Columns: `wsg`, `species`, then `names(metrics)`.

## Details

The `streams_access` join is a LEFT join: access is optional metadata
for a length roll-up. When a segment has no `streams_access` row (access
not yet built for the WSG), `access` is `NULL` and `accessible_km`
resolves to 0 — build it via `lnk_pipeline_run(mapping_code = TRUE)` (or
the unconditional access phase). Length is never dropped by a missing
access row, so the habitat metrics (`spawning_km`, `rearing_km`) are
unaffected.

Each row also carries `waterbody` (`"lake"`, `"wetland"` or `"stream"`):
the polygon the line sits in, by `waterbody_key` against the polygon
tables fresh's lake and wetland rules read. Lakes and reservoirs
(`fwa_lakes_poly`, `fwa_manmade_waterbodies_poly`) are `"lake"`,
wetlands (`fwa_wetlands_poly`) `"wetland"`, and river polygons or no
polygon `"stream"`. The three partition the network. A lake's centreline
km and its polygon hectares describe the same water and are never added
together.

Each row also carries `connection` (bool): a line in a lake polygon on
FWA edge type 1450 ("connection"), the connector lines that join each
tributary mouth to the lake's main-flow line. fresh keeps them in
`rearing`, where they connect inlet rearing to the lake, but they trace
a join rather than a flow path, so habitat km leave them out and state
them apart. The default `rearing_km` is every line flagged `rearing`
except connection lines, and `rearing_lake_connection_km` carries those
(0 where there are none), so the two sum to the flag total (to rounding;
`rearing_km` is `NA`, not 0, in a group whose only rearing is connection
lines).
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md)
reads the same split, and there
`rearing_stream_km + rearing_lake_km + rearing_wetland_km` equals
`rearing_km`; see the examples.

Because the per-species columns are aliased to fixed names, the
`metrics` SQL is written **once**, species-agnostic — mirroring
[`fresh::frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.html)'s
`metrics` / `where` shape. Adding a species is a `species` vector edit,
not a query edit.

This is a **flat per-WSG `GROUP BY`** — it sums whole-WSG length by
`(watershed_group_code, species_code)`. It is distinct from
[`lnk_aggregate()`](https://newgraphenvironment.github.io/link/reference/lnk_aggregate.md)
/
[`fresh::frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.html),
which roll habitat up the network *upstream of individual crossings*
(point-based traversal). Use this for WSG totals; use those for
per-crossing upstream summaries.

`accessible_km` sums `access IN (1, 2)` — link's per-species access
model on `streams_access`, the number validated against the tunnel-free
bcfp reference in `data-raw/parity_crosssection.R` (accessible +
spawning + rearing, 8 species x 11 WSGs). It deliberately does **not**
use the `accessible` boolean on `streams_habitat_<sp>`, which carries
different (pre-gating) semantics and diverges from the access model
(MORR coho: 3424 km vs the validated 3330 km).

## See also

[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_aggregate()`](https://newgraphenvironment.github.io/link/reference/lnk_aggregate.md),
[`fresh::frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.html)

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_habitat_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate.md),
[`lnk_habitat_validate_band()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_validate_band.md),
[`lnk_log_read()`](https://newgraphenvironment.github.io/link/reference/lnk_log_read.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
# Coho accessible / spawning / rearing km for Morice, from persisted state.
lnk_rollup_wsg(conn, aoi = "MORR", species = "CO")

# Rearing km by the polygon the line sits in (stream / lake / wetland);
# lake connection lines are in none of them, as in the default.
lnk_rollup_wsg(conn, aoi = "MORR", species = "CO",
  metrics = c(
    rearing_stream_km =
      "sum(length_metre) FILTER (WHERE rearing AND waterbody = 'stream') / 1000",
    rearing_lake_km = paste(
      "sum(length_metre) FILTER (WHERE rearing AND waterbody = 'lake'",
      "AND NOT connection) / 1000"),
    rearing_wetland_km =
      "sum(length_metre) FILTER (WHERE rearing AND waterbody = 'wetland') / 1000"))

# Custom metric: count accessible segments per species.
lnk_rollup_wsg(conn, aoi = "MORR", species = c("CO", "BT"),
  metrics = c(n_accessible = "COUNT(*) FILTER (WHERE access IN (1, 2))"))
} # }
```
