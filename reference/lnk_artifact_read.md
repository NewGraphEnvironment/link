# Read the recorded source artifacts, one row per expected artifact

Reports every primitive this host should have a record for, with
`status = "missing"` where it has none — a missing record is reported,
not silently left out. A record whose table no longer exists (dropped
since it was loaded, e.g. by `state_clean.sh`) reads `"table_absent"`:
the record outlives the table, and names a load the database no longer
holds. The stream network expands to one expected artifact per watershed
group loaded in this database.

## Usage

``` r
lnk_artifact_read(conn, host = .lnk_host())
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html).

- host:

  Host label; see
  [`lnk_artifact_record()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_record.md).

## Value

A data frame: the recorded columns plus `status` (`"recorded"` /
`"missing"` / `"table_absent"`).

## See also

Other provenance:
[`lnk_artifact_probe()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_probe.md),
[`lnk_artifact_record()`](https://newgraphenvironment.github.io/link/reference/lnk_artifact_record.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
a <- lnk_artifact_read(conn)
table(a$table_name, a$status)
} # }
```
