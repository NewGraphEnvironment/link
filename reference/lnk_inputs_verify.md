# Verify that required Postgres tables exist in a connection

Fail-loud precondition check used by pipeline phases that assume their
input tables are already loaded (typically by a separate snapshot
script). Lists every missing `<schema>.<table>` in the error message so
the caller knows exactly what to load before re-running.

## Usage

``` r
lnk_inputs_verify(conn, required)
```

## Arguments

- conn:

  A DBI connection.

- required:

  Character vector of fully-qualified `<schema>.<table>` strings (e.g.
  `c("whse_fish.pscis_assessment_svw", "fresh.dams")`). Identifiers are
  not quoted — bare lowercase form expected.

## Value

`invisible(NULL)` on success.
[`stop()`](https://rdrr.io/r/base/stop.html)s with a list of missing
tables on failure.

## Details

Generic — not specific to any pipeline phase. Likely belongs in a future
`pac` package once that's scaffolded; ships in link for now.

Queries `information_schema.tables` once per call, parameterised with
the parsed `(schema, table)` pairs — single round-trip regardless of how
many tables are in `required`.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
lnk_inputs_verify(conn, c(
  "whse_fish.pscis_assessment_svw",
  "cabd.dams",
  "working_adms.modelled_stream_crossings"
))
} # }
```
