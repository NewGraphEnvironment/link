# Apply Rearing-Spawning and Waterbody Connectivity

Sixth and final phase of the habitat classification pipeline. Runs the
connectivity logic that `frs_habitat()` executes internally —
rearing-spawning clustering via
[`fresh::frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.html)
and connected-waterbody rules via `fresh:::.frs_connected_waterbody()` —
configured by per-species flags in `cfg$parameters_fresh`:

## Usage

``` r
lnk_pipeline_connect(
  conn,
  aoi,
  cfg,
  schema,
  species = NULL,
  thresholds_csv = system.file("extdata", "parameters_habitat_thresholds.csv", package =
    "fresh")
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- aoi:

  Character. Watershed group code (kept for signature consistency with
  the other pipeline phases; not used in this phase — connectivity
  operates on the classified table which is already AOI-scoped).

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- schema:

  Character. Working schema name (kept for signature consistency;
  connectivity reads `fresh.streams_habitat` directly).

- species:

  Character vector. Species to run connectivity for. Default derives the
  same way as
  [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md).

- thresholds_csv:

  Path to the habitat thresholds CSV. Default uses the copy shipped with
  fresh.

## Value

`conn` invisibly, for pipe chaining.

## Details

- `cluster_rearing` — enables three-phase rearing-spawning clustering
  for the species

- `cluster_direction`, `cluster_bridge_gradient`,
  `cluster_bridge_distance`, `cluster_confluence_m` — cluster parameters

- `cluster_spawning` — enables spawn clustering for rules with
  `requires_connected: rearing` (e.g. SK spawning adjacent to rearing
  lakes)

Mutates `fresh.streams_habitat` in place, adjusting `spawning` /
`rearing` booleans per species based on connectivity.

`lnk_pipeline_connect` is a thin wrapper over fresh's internal
`.frs_run_connectivity` orchestrator. Accessing fresh internals is an
acknowledged fragility — a fresh issue will be filed to export a stable
API for this composition. The wrapper isolates link from the internal
name, so future renames in fresh affect one file here.

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg  <- lnk_config("bcfishpass")
schema <- "working_bulk"

lnk_pipeline_setup(conn, schema)
lnk_pipeline_load(conn, "BULK", cfg, schema)
lnk_pipeline_prepare(conn, "BULK", cfg, schema)
lnk_pipeline_break(conn, "BULK", cfg, schema)
lnk_pipeline_classify(conn, "BULK", cfg, schema)
lnk_pipeline_connect(conn, "BULK", cfg, schema)

DBI::dbDisconnect(conn)
} # }
```
