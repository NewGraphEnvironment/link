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

  A data frame with `table_name` and `last_analyze`, and optionally
  `table_exists`. Defaults to reading `conn`; pass directly to test, or
  to judge a stamp collected on another host. Rows in a frame without
  `table_exists` are taken to exist.

- quiet:

  Suppress the human-readable report.

## Value

Invisibly, a list with `ok`, `vintage`, `stale`, `absent`, `unknown`,
`missing` (the union of the last two, kept for callers that only care
that something was wrong), `oldest_days` and `message`.

## Details

The other seven tables in `.lnk_input_primitives()` are bulk-restored
FWA. They are never `ANALYZE`d, so they carry no vintage at all and are
not an axis this can measure — including them would mean every host
failing forever on data that is not the staleness risk.

**Absence is not a pass**, but absence and ignorance are different
failures and are reported as such. A table that does not exist is
`absent`; one that exists but yields no usable timestamp is `unknown`.
Both fail, in the same direction as a stale one — a query returning
nothing must never read as "nothing is stale" — but they send an
operator to different places. Conflating them cost a pilot run, which
reported `never loaded / absent` for a table that was present and
healthy.

Two statistics quirks make this fiddlier than it looks. `last_analyze`
alone is unusable: measured across all ten primitives it is NULL on
every one and only `last_autoanalyze` is populated, so the query takes
`GREATEST` of the pair (in Postgres that ignores NULLs and is NULL only
when every argument is). And on a **freshly restored** database neither
is set — statistics are collected by (auto)analyze, so a table that was
just loaded has rows and no stats at all. The query therefore falls back
to the relation file's mtime, which exists for any real table. That
fallback is why `unknown` should be unreachable in practice.

## See also

Other preflight:
[`lnk_fanout_judge()`](https://newgraphenvironment.github.io/link/reference/lnk_fanout_judge.md),
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
