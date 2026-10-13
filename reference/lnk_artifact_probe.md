# Probe the FWA primitives' artifacts and record what is current now

`HEAD`s the object-store artifact behind each FWA primitive in this
database and records the answer with `recorded_by = "probe"` (link#265).
This is the weaker kind of record: it says which version is current
**now**, not which one was loaded. It exists because fwapg's `load.sh`
records nothing, and a version that is not written down before the store
moves on can never be named (link#270 is the loader-side record). A
probe never overwrites a `loader` row. A probe row is **not a
baseline**: anything that compares a recorded ETag against the store to
decide whether a source changed (link#273) must read `loader` rows only,
because a probe's ETag is by construction whatever the store held when
the probe ran.

## Usage

``` r
lnk_artifact_probe(conn, tables = NULL, host = .lnk_host(), max_fail = 5L)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the database the primitives live in.

- tables:

  Primitives to probe. Defaults to every FWA primitive (those loaded by
  fwapg).

- host:

  Host label; see
  [`lnk_artifact_record()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_record.md).

- max_fail:

  Stop sending `HEAD`s after this many consecutive failures (no response
  at all); the rest are recorded with no identity and a note.

## Value

Invisibly, the probed rows, with the HTTP `status` of each `HEAD`.

## Details

The stream network is one object per watershed group. The groups probed
are the ones **loaded in this database**, not a copy of `load.sh`'s
discovery query, so the probe cannot drift from what is actually here.
The derived `fwa_stream_networks_order_parent` gets a `derived` row with
no identity, which is correct and permanent.

## See also

Other provenance:
[`lnk_artifact_read()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_read.md),
[`lnk_artifact_record()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_record.md)

## Examples

``` r
# The FWA artifacts a probe would HEAD for two watershed groups:
prims <- link:::.lnk_input_primitives()
fwa <- prims[startsWith(prims$source, "fwapg/"), ]
link:::.lnk_artifact_expand(fwa, wsg = c("BULK", "MORR"))[, c("kind", "url")]
#>      kind
#> 1  object
#> 2  object
#> 3  object
#> 4  object
#> 5 derived
#> 6  object
#> 7  object
#> 8  object
#> 9  object
#>                                                                                       url
#> 1      https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_sp/BULK.parquet
#> 2      https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_sp/MORR.parquet
#> 3 https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_channel_width.csv.gz
#> 4     https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_discharge.csv.gz
#> 5                                         fwapg/load/fwa_stream_networks_order_parent.sql
#> 6                   https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_lakes_poly.parquet
#> 7                https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_wetlands_poly.parquet
#> 8                  https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_rivers_poly.parquet
#> 9              https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_obstructions_sp.parquet

if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
lnk_artifact_probe(conn)
} # }
```
