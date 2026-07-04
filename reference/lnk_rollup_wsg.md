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
    rearing_km = "round(sum(length_metre) FILTER (WHERE rearing)::numeric / 1000, 2)"),
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
  `access`, `spawning`, `rearing`. Default emits `accessible_km`,
  `spawning_km`, `rearing_km`. Raw SQL — trusted caller input, like
  `frs_aggregate()`.

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
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
# Coho accessible / spawning / rearing km for Morice, from persisted state.
lnk_rollup_wsg(conn, aoi = "MORR", species = "CO")

# Custom metric: count accessible segments per species.
lnk_rollup_wsg(conn, aoi = "MORR", species = c("CO", "BT"),
  metrics = c(n_accessible = "COUNT(*) FILTER (WHERE access IN (1, 2))"))
} # }
```
