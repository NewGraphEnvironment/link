# Build per-segment per-species mapping_code tokens from schema tables

Schema-aware portable wrapper around
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md).
Queries `table_access`, `table_habitat` (long form), and
`table_streams.feature_code`, assembles the inputs (pivot habitat long →
wide, build feature_code lookup), calls
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md)
for the per-segment token compute, and optionally writes the result to
`table_to`.

## Usage

``` r
lnk_mapping_code(
  conn,
  table_access,
  table_habitat,
  table_streams,
  aoi,
  table_to = NULL,
  presence = NULL,
  species_resident = c("bt", "wct"),
  species_anadromous = c("ch", "cm", "co", "pk", "sk", "st"),
  species_spawn_only = c("cm", "pk")
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the local pipeline DB.

- table_access:

  Character. Schema-qualified name of the `streams_access` table (e.g.
  `"working_pars.streams_access"` or `"fresh_default.streams_access"`).

- table_habitat:

  Character. Schema-qualified name of a long-form habitat source —
  either the working-schema `streams_habitat` table or the persist
  `streams_habitat_long_vw` view. Must have columns `id_segment`,
  `watershed_group_code`, `species_code`, `spawning`, `rearing`.

- table_streams:

  Character. Schema-qualified name of the `streams` table, queried for
  `id_segment` + `feature_code`.

- aoi:

  Character. Watershed group code (e.g. `"PARS"`) — filters all input
  queries to one WSG.

- table_to:

  Character or `NULL`. Optional schema-qualified destination table for
  the result. When non-NULL,
  [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md)
  writes the tibble via `dbWriteTable(overwrite = TRUE)`. Default `NULL`
  — returns-only.

- presence:

  Named logical vector or `NULL`. Per-species presence flag for `aoi`.
  When `NULL` the function derives presence from the data: a species is
  present iff it has at least one habitat row with `spawning = TRUE` or
  `rearing = TRUE`. Pass explicit values to override (e.g. force-include
  a species for QGIS symbology even when no segments are accessible).

- species_resident:

  Character. Species using the resident flavor of
  `mapping_code_barrier`. Default `c("bt", "wct")`. Pass-through to
  [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md)'s
  `resident_species` arg.

- species_anadromous:

  Character. Species using the anadromous flavor. Default
  `c("ch", "cm", "co", "pk", "sk", "st")`. Pass-through to
  [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md)'s
  `anadromous_species` arg.

- species_spawn_only:

  Character. Species without rearing semantics. Default `c("cm", "pk")`.
  Pass-through to
  [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md)'s
  `spawn_only_species` arg.

## Value

Invisibly, the per-segment per-species mapping_code tibble keyed by
`id_segment` with one `mapping_code_<sp>` text column per species in
`union(species_resident, species_anadromous)`.

## Details

Decouples the mapping_code build from any specific schema layout. Caller
passes explicit table names — the function works against working-schema
tables (mid-pipeline) or persist-schema tables (ad-hoc rebuild) without
modification. The companion view
`<persist_schema>.streams_habitat_long_vw` (created by
[`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md))
presents the per-species split as a long-form shape so `table_habitat`
can point at either layout.

This function replaces the inline assembly previously buried inside
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md).
The compare wrapper now goes through this function via
`lnk_pipeline_run(..., mapping_code = TRUE)`. Operators can also call
this directly against persist schema with the tunnel down — the build is
tunnel-independent (the diff vs reference is separate, see
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md)).

Tracks link#187 (tunnel decouple + portable build).

## See also

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost", port = 5432, dbname = "fwapg",
  user = "postgres", password = "postgres")

# Working-schema build during a pipeline run:
lnk_mapping_code(
  conn,
  table_access  = "working_pars.streams_access",
  table_habitat = "working_pars.streams_habitat",
  table_streams = "working_pars.streams",
  aoi           = "PARS",
  table_to      = "working_pars.streams_mapping_code")

# Ad-hoc rebuild against persist (tunnel-free) for QGIS symbology:
lnk_mapping_code(
  conn,
  table_access  = "fresh_default.streams_access",
  table_habitat = "fresh_default.streams_habitat_long_vw",
  table_streams = "fresh_default.streams",
  aoi           = "PARS",
  table_to      = "fresh_default.streams_mapping_code")
} # }
```
