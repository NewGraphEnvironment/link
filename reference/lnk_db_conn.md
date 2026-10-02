# Connect to FWA PostgreSQL database

Opens a connection to a PostgreSQL database containing fwapg,
bcfishpass, and bcfishobs. Defaults to the `PG_*_SHARE` environment
variables used by fresh and fpr (Docker-hosted fwapg). Falls back to
standard `PG*` variables for local PostgreSQL.

## Usage

``` r
lnk_db_conn(
  dbname = Sys.getenv("PG_DB_SHARE", Sys.getenv("PGDATABASE", "postgis")),
  host = Sys.getenv("PG_HOST_SHARE", Sys.getenv("PGHOST", "localhost")),
  port = as.integer(Sys.getenv("PG_PORT_SHARE", Sys.getenv("PGPORT", "5432"))),
  user = Sys.getenv("PG_USER_SHARE", Sys.getenv("PGUSER", "postgres")),
  password = Sys.getenv("PG_PASS_SHARE", Sys.getenv("PGPASSWORD", ""))
)
```

## Arguments

- dbname:

  Database name. Defaults to `PG_DB_SHARE` or `PGDATABASE`.

- host:

  Host. Defaults to `PG_HOST_SHARE` or `PGHOST`.

- port:

  Port. Defaults to `PG_PORT_SHARE` or `PGPORT`.

- user:

  User. Defaults to `PG_USER_SHARE` or `PGUSER`.

- password:

  Password. Defaults to `PG_PASS_SHARE` or `PGPASSWORD`.

## Value

A
[DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
object.

## Details

Checks `PG_*_SHARE` first, then standard PostgreSQL variables (`PGHOST`,
etc.). This is the reverse of
[`fresh::frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.html)
from fresh 0.36.0, which reads `PG*` first and `PG_*_SHARE` only when
none of `PG*` is set. On a machine that sets both groups to different
targets, the two functions connect to different databases.

## Examples

``` r
if (FALSE) { # \dontrun{
# Default — reads PG_*_SHARE env vars (Docker fwapg)
conn <- lnk_db_conn()

# Override for a specific database
conn <- lnk_db_conn(dbname = "fishpass", host = "db.example.com")

# Use with other lnk_* functions
conn <- lnk_db_conn()
lnk_score_severity(conn, "working.crossings")

DBI::dbDisconnect(conn)
} # }
```
