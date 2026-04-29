# Classify Stream Segments into Habitat per Species

Fifth phase of the habitat classification pipeline. Builds the
access-gating break table consumed by classification, then calls
[`fresh::frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.html)
with the rules YAML, thresholds, per-species parameters, and barrier
overrides from the config bundle.

## Usage

``` r
lnk_pipeline_classify(
  conn,
  aoi,
  cfg,
  loaded,
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

  Character. Watershed group code (today; extends to other spatial
  filters later).

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- loaded:

  Named list of tibbles from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Carries `parameters_fresh`, `user_habitat_classification`, and
  `wsg_species_presence`.

- schema:

  Character. Working schema name.

- species:

  Character vector. Species codes to classify. Default derives from
  `loaded$parameters_fresh$species_code` intersected with the species
  present in the AOI (via `loaded$wsg_species_presence`).

- thresholds_csv:

  Path to the habitat thresholds CSV. Default uses the copy shipped with
  fresh.

## Value

`conn` invisibly, for pipe chaining.

## Details

The access-gating break table (`fresh.streams_breaks`) is assembled from
the FULL gradient barrier set (not the minimal one used for
segmentation), falls, user-identified definite barriers, and crossings
with their AOI-filtered ltree values attached. Filtering to the AOI
keeps the O(segments × breaks) access-gating join tractable.

Writes to:

- `fresh.streams_breaks` — access-gating breaks

- `fresh.streams_habitat` — per-species classification output (written
  by `frs_habitat_classify`)

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn   <- lnk_db_conn()
cfg    <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
schema <- "working_bulk"

lnk_pipeline_setup(conn, schema)
lnk_pipeline_load(conn, "BULK", cfg, loaded, schema)
lnk_pipeline_prepare(conn, "BULK", cfg, loaded, schema)
lnk_pipeline_break(conn, "BULK", cfg, loaded, schema)
lnk_pipeline_classify(conn, "BULK", cfg, loaded, schema)

DBI::dbDisconnect(conn)
} # }
```
