# Record source-artifact identity for DB primitives

Upserts rows into `provenance.source_artifact`, the table that says
which version of which object each primitive in this database was loaded
from (link#265). The bchamp object store is versioned but cannot be
listed, so a version id not recorded at load time is gone for good; this
is where it is recorded.

## Usage

``` r
lnk_artifact_record(
  conn,
  artifacts,
  recorded_by = c("loader", "probe"),
  host = .lnk_host()
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the database the primitives live in.

- artifacts:

  A data frame with `table_name` and `url`, and optionally `version_id`,
  `etag`, `last_modified`, `loaded_at` and `notes`. `kind` is taken from
  the dictionary. `last_modified` may be POSIXct or the raw HTTP header
  string (`"Thu, 16 Apr 2026 02:22:39 GMT"`).

- recorded_by:

  `"loader"` or `"probe"`.

- host:

  Host label. Defaults to `LNK_HOST_ALIAS`, else the node name — the
  same label the run log uses.

## Value

Invisibly, the rows as recorded (before the probe-vs-loader rule is
applied by the database).

## Details

`recorded_by` is the strength of the evidence. `"loader"` rows come from
the thing that did the load (`data-raw/snapshot_bcfp.sh` pins each fetch
to the version it records). `"probe"` rows come from a `HEAD` after the
fact and say only that the version is current now. **A probe never
overwrites a loader row**, so weaker evidence cannot replace stronger.
Nor does a probe overwrite an earlier probe that named a **different**
version while the table's row count is unchanged: the earlier probe was
taken closer to the load, and the store moving on since says nothing
about what is loaded here. A changed row count is taken as a reload, and
the newer probe replaces it. A loader row always replaces whatever is
there.

Every `url` must be one `lnk_artifact_record()` knows for that table —
the primitives dictionary's URL, with `{wsg}` expanded. A loader that
fetches from somewhere else stops here rather than recording an identity
for an object the rest of link does not know about.

`n_rows` is counted from the database at record time: exactly, per
watershed group for the per-group stream objects. A table that does not
exist records `n_rows` NULL and says so in `notes`.

## See also

Other provenance:
[`lnk_artifact_probe()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_probe.md),
[`lnk_artifact_read()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_read.md)

## Examples

``` r
# Which artifacts the dictionary knows, without touching a database:
prims <- link:::.lnk_input_primitives()
prims[, c("table_name", "kind")]
#>                                            table_name    kind
#> 1             whse_basemapping.fwa_stream_networks_sp  object
#> 2  whse_basemapping.fwa_stream_networks_channel_width  object
#> 3      whse_basemapping.fwa_stream_networks_discharge  object
#> 4   whse_basemapping.fwa_stream_networks_order_parent derived
#> 5                     whse_basemapping.fwa_lakes_poly  object
#> 6                  whse_basemapping.fwa_wetlands_poly  object
#> 7                    whse_basemapping.fwa_rivers_poly  object
#> 8                whse_basemapping.fwa_obstructions_sp  object
#> 9                              bcfishobs.observations  object
#> 10                     whse_fish.pscis_assessment_svw     api
#> 11                                          cabd.dams     api
#> 12                    fresh.modelled_stream_crossings  object

if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
lnk_artifact_record(conn, data.frame(
  table_name = "cabd.dams",
  url = prims$url[prims$table_name == "cabd.dams"],
  loaded_at = Sys.time()), recorded_by = "loader")
} # }
```
