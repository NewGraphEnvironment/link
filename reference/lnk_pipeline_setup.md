# Set Up the Working Schema for a Pipeline Run

Creates the per-run working schema and ensures the `fresh` output schema
exists. Every downstream pipeline helper (`lnk_pipeline_*`) assumes
these schemas are in place.

## Usage

``` r
lnk_pipeline_setup(conn, schema = "working", overwrite = FALSE)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (localhost fwapg, typically from
  [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)).

- schema:

  Character. Working schema name for this run. Default `"working"`.
  Validated as a SQL identifier.

- overwrite:

  Logical. If `TRUE`, drop `schema` (CASCADE) before creating. Default
  `FALSE` — create only if absent so cached contents from prior runs
  survive.

## Value

`conn` invisibly, for pipe chaining.

## Details

When running multiple AOIs (watershed groups, mapsheets, sub-basins) in
parallel on the same host, each run uses its own namespaced working
schema so the runs do not collide. The caller decides the schema name —
a typical WSG-based choice is `paste0("working_", tolower(aoi))`.

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()

# Single-AOI run, canonical per-WSG schema
lnk_pipeline_setup(conn, "working_bulk")

# Fresh start: wipe any prior state first
lnk_pipeline_setup(conn, "working_bulk", overwrite = TRUE)

DBI::dbDisconnect(conn)
} # }
```
