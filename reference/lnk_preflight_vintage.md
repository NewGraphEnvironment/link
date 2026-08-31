# Are this host's DB primitives fresh enough to model against?

`snapshot_bcfp.sh` loads four primitives from public sources into each
host's local fwapg. Every cypher reloads them during prep; the
dispatcher does not, and nothing checks. On 2026-08-30 the dispatcher's
`cabd.dams` was 2026-05-23 and `fresh.modelled_stream_crossings`
2026-05-26 — a run started that day would have modelled one bucket on
May inputs and three on August inputs, produced one consolidated table
set, and said nothing about it anywhere (link#246).

## Usage

``` r
lnk_preflight_vintage(
  conn = NULL,
  max_age_days = 7,
  tables = .lnk_vintage_primitives(),
  now = Sys.time(),
  vintage = .lnk_vintage_read(conn, tables),
  quiet = FALSE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the host's local fwapg, or `NULL` when `vintage` is supplied
  directly.

- max_age_days:

  Maximum acceptable age of the **oldest** primitive.

- tables:

  Fully-qualified table names to check. Defaults to the snapshot-loaded
  set.

- now:

  Reference time. Injectable so tests are not clock-dependent.

- vintage:

  A data frame with `table_name` and `last_analyze`. Defaults to reading
  `conn`; pass directly to test, or to judge a stamp collected on
  another host.

- quiet:

  Suppress the human-readable report.

## Value

Invisibly, a list with `ok`, `vintage`, `stale`, `missing`,
`oldest_days` and `message`.

## Details

The other seven tables in `.lnk_input_primitives()` are bulk-restored
FWA. They are never `ANALYZE`d, so they carry no vintage at all and are
not an axis this can measure — including them would mean every host
failing forever on data that is not the staleness risk.

**Absence is not a pass.** A table missing from the result, and a table
present with a NULL timestamp, both fail — in the same direction as a
stale one. A query returning nothing must never read as "nothing is
stale".

`last_analyze` alone is unusable here: measured across all ten
primitives it is NULL on every one, and only `last_autoanalyze` is
populated. `GREATEST` of the two is the usable signal — in Postgres it
ignores NULLs and is NULL only when every argument is.

## See also

Other preflight:
[`lnk_preflight_fresh()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_fresh.md),
[`lnk_preflight_parity()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_parity.md),
[`lnk_preflight_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_preflight_stamp.md)

## Examples

``` r
# Judge a vintage table without touching a database:
now <- as.POSIXct("2026-08-30 12:00:00", tz = "UTC")
v <- data.frame(
  table_name   = link:::.lnk_vintage_primitives(),
  last_analyze = now - c(1, 2, 1, 99) * 86400)
res <- lnk_preflight_vintage(vintage = v, now = now, max_age_days = 7,
                             quiet = TRUE)
res$ok
#> [1] FALSE
res$stale
#> [1] "whse_fish.pscis_assessment_svw"
```
