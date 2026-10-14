# Load a habitat export into PostgreSQL

Fetches the parts a catalog lists, checks each one's size and md5
against the manifest before reading it, and writes their rows to one
table, keyed
`(config, species, blue_line_key, downstream_route_measure)`. Join it to
`whse_basemapping.fwa_stream_networks_sp` by `blue_line_key` and measure
to cut each segment's line.

## Usage

``` r
lnk_db_load(
  conn,
  catalog,
  configs = NULL,
  table = "habitat.fwa_v1_segment",
  cache_dir = tools::R_user_dir("link", "cache")
)
```

## Arguments

- conn:

  A DBI connection to PostgreSQL.

- catalog:

  A catalog from
  [`lnk_catalog()`](https://newgraphenvironment.github.io/link/reference/lnk_catalog.md),
  optionally filtered to some of its parts. A config is loaded from the
  parts given for it, so filter by config rather than by species when
  reloading.

- configs:

  Configs to load, or `NULL` for every config in `catalog`.

- table:

  Target table, `schema.table`. Defaults to the name the dataset ID
  gives, `habitat.fwa_v1_segment`.

- cache_dir:

  Where downloaded parts are kept. A cached part is reused while its md5
  still matches the manifest. Local parts are read in place.

## Value

Invisibly, a data frame of `key` and `rows` loaded.

## Details

Everything runs in one transaction: a part that fails its md5, a column
mismatch, a duplicate key or a short read leaves the table as it was.
Loading a config replaces that config's rows (all species), so a reload
never mixes two builds of one config. Other configs' rows are untouched.

## See also

Other export:
[`lnk_catalog()`](https://newgraphenvironment.github.io/link/reference/lnk_catalog.md),
[`lnk_scenario_export()`](https://newgraphenvironment.github.io/link/reference/lnk_scenario_export.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cat <- lnk_catalog("s3://fresh-bc/habitat/fwa/v1/manifest.json")
lnk_db_load(conn, cat, configs = "default")

DBI::dbGetQuery(conn, "
  SELECT species, round(sum(length_metre) / 1000) AS rearing_km
    FROM habitat.fwa_v1_segment
   WHERE config = 'default' AND rearing
   GROUP BY species")
} # }
```
