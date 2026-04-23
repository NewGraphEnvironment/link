# Load Crossings and Apply Crossing-Level Overrides

Second phase of the habitat classification pipeline. Loads the
anthropogenic crossing table for an AOI and applies the two
crossing-level override types from the config bundle:

## Usage

``` r
lnk_pipeline_load(conn, aoi, cfg, schema)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (localhost fwapg, typically from
  [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)).

- aoi:

  Character. Today accepts a watershed group code (e.g. `"BULK"`).
  Filtering against `watershed_group_code` columns in the CSVs means
  polygon / ltree AOIs are not yet supported here; those will come as a
  follow-up.

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- schema:

  Character. Working schema name (validated). Must already exist — call
  [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  first.

## Value

`conn` invisibly, for pipe chaining.

## Details

1.  **Modelled crossing fixes** — imagery/field corrections where
    `structure = "NONE"` or `structure = "OBS"` force the crossing's
    `barrier_status` to `"PASSABLE"`. These are modelled culverts that,
    on inspection, turned out to be open channels or observation-only
    points.

2.  **PSCIS barrier status overrides** — expert-curated
    `user_barrier_status` values replace the modelled `barrier_status`
    for a PSCIS crossing.

Falls, user-identified definite barriers, observation exclusions, and
habitat classification CSVs are loaded by
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
where they are consumed, not here.

Writes to these tables under the caller's working schema:

- `<schema>.crossings` — base crossings + misc crossings, with
  overridden `barrier_status` applied

- `<schema>.crossing_fixes` — modelled fixes for the AOI (only when the
  config bundle has fixes matching this AOI)

- `<schema>.pscis_fixes` — PSCIS status overrides for the AOI (only when
  the config bundle has entries matching this AOI)

## See also

Other pipeline:
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg  <- lnk_config("bcfishpass")

schema <- "working_bulk"
lnk_pipeline_setup(conn, schema)
lnk_pipeline_load(conn, aoi = "BULK", cfg = cfg, schema = schema)

# Inspect the result
DBI::dbGetQuery(conn, sprintf(
  "SELECT barrier_status, count(*) FROM %s.crossings GROUP BY 1", schema))

DBI::dbDisconnect(conn)
} # }
```
