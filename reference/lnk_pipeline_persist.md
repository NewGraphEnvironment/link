# Persist per-WSG output into the province-wide habitat tables

Copies the per-WSG staging tables (`<schema>.streams`,
`<schema>.streams_habitat`) from the working schema into the persistent
province-wide tables (`<persist_schema>.streams`,
`<persist_schema>.streams_habitat_<sp>`, one per species). Wide-per-
species pivot — fresh's long-format `streams_habitat` (one row per
segment-species) becomes one row per segment in each per-species table.

## Usage

``` r
lnk_pipeline_persist(
  conn,
  aoi,
  cfg,
  species,
  schema = paste0("working_", tolower(aoi))
)
```

## Arguments

- conn:

  DBI connection.

- aoi:

  Watershed group code (e.g. `"LRDO"`).

- cfg:

  An `lnk_config` object with `cfg$pipeline$schema` set.

- species:

  Character vector of species codes to persist. Should match what
  [`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md)
  was called with — typically
  [`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)
  output for the AOI.

- schema:

  Working schema (per-WSG staging). Default
  `paste0("working_", tolower(aoi))`.

## Value

`conn` invisibly.

## Details

Idempotent: each call DELETEs all rows for the given AOI before
INSERTing the fresh ones, so re-running a WSG cleanly replaces its data
without affecting other WSGs.

Column projection is driven by `cols_streams` + `cols_habitat` (named
vectors at the top of `R/lnk_persist_init.R`) — single source of truth
shared with
[`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md).

Call after
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
in the per-WSG orchestrator, before computing any rollup queries that
should reflect the final per-species classification.
