# Is the discharge a config reads loaded in this database?

prepare joins mean annual discharge onto every watershed group's
streams, `cw` groups included, from the source the config names
(`pipeline: discharge_source`): `fwapg`'s
`whse_basemapping.fwa_stream_networks_discharge` by default, or `wet`'s
published `discharge.fwa_v1_segment_monthly`. A host without that table
fails every group at prepare, so a multi-host run checks each host
before it dispatches work there.

## Usage

``` r
lnk_preflight_discharge(
  conn = NULL,
  cfg,
  state = .lnk_discharge_state(conn, .lnk_discharge_source(cfg)),
  quiet = FALSE
)
```

## Arguments

- conn:

  A DBI connection. Not used when `state` is given.

- cfg:

  An `lnk_config` from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- state:

  A one-row data frame with `exists` (the table is there), `valued` (it
  holds at least one value the pipeline reads) and `comment` (the
  table's comment; wet's loader writes its manifest URL, build time and
  commit there). Read from `conn` by default; pass one to judge a state
  without a database.

- quiet:

  Suppress the human-readable report.

## Value

Invisibly, a list with `ok`, `source`, `table`, `comment` and `message`.

## Details

For `wet` the check is for an annual pick (`scenario = 'historical'`,
`month = 0`, `pick`), which is all the pipeline reads. A pipeline host
can load just that:
`wet::wet_db_load(conn, wet::wet_catalog(), months = 0, pick_only = TRUE)`
(about 4.5 M rows, against 103 M for every month and source).

## See also

Other preflight:
[`lnk_fanout_judge()`](https://newgraphenvironment.github.io/link/reference/lnk_fanout_judge.md),
[`lnk_preflight_fresh()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_fresh.md),
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md),
[`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md),
[`lnk_preflight_vintage()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_vintage.md)

## Examples

``` r
cfg <- lnk_config("default")
cfg$pipeline$discharge_source <- "wet"

# Judge a state without touching a database:
res <- lnk_preflight_discharge(cfg = cfg, quiet = TRUE,
  state = data.frame(exists = FALSE, valued = FALSE, comment = NA))
res$ok
#> [1] FALSE
res$message
#> [1] "discharge (wet): discharge.fwa_v1_segment_monthly does not exist. Load it with wet::wet_db_load(conn, wet::wet_catalog(), months = 0, pick_only = TRUE)."
```
