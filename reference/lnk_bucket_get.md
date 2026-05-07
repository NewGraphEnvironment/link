# Download a single artifact from a public S3 bucket prefix

Fetch one file from a versioned S3 bucket (e.g., the bcfp build
artifacts under `s3://fresh-bc/bcfishpass/`). Returns raw bytes by
default so callers can decode based on file format (CSV via `read.csv`,
JSON via
[`jsonlite::fromJSON`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html),
parquet via `arrow::read_parquet`, etc.) — the helper is deliberately
format-agnostic.

## Usage

``` r
lnk_bucket_get(
  name,
  prefix = "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass",
  to = NULL
)
```

## Arguments

- name:

  File path relative to `prefix`, e.g. `"log.json"` or
  `"csvs/wsg_species_presence.csv"`.

- prefix:

  Bucket prefix as an HTTPS URL. Defaults to NGE's bcfp dump prefix.

- to:

  Optional file path. When supplied, bytes are written there (binary)
  and the path is returned invisibly. When `NULL` (default), raw bytes
  are returned in memory.

## Value

Either a `raw` vector (default) or, when `to` is supplied, the path it
was written to (invisibly).

## Details

Companion function:
[`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)
is sugar for the most common read (`<prefix>/log.json`, the bcfp build
identifier).

Uses [`httr::GET()`](https://httr.r-lib.org/reference/GET.html). Fails
loud ([`stop()`](https://rdrr.io/r/base/stop.html)) on any non-2xx
response with the URL + status code in the message. No retry/back-off —
re-running the workflow is the recovery path.

Public bucket — no AWS auth needed for read. Writes happen via the
upstream `dump-bcfishpass-csvs.yml` workflow (separate; not this
function).

## See also

[`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)

Other bucket:
[`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Read the build identifier directly via the sugar helper.
log <- lnk_bucket_log()
log$model_version

# Or fetch the same file as raw bytes and decode yourself.
bytes <- lnk_bucket_get("log.json")
jsonlite::fromJSON(rawToChar(bytes))

# Pull a CSV and parse with read.csv (no temp file needed).
bytes <- lnk_bucket_get("csvs/wsg_species_presence.csv")
df <- read.csv(text = rawToChar(bytes))
head(df)

# Stream a large file straight to disk.
tmp <- tempfile(fileext = ".csv")
lnk_bucket_get("csvs/user_modelled_crossing_fixes.csv", to = tmp)
file.info(tmp)$size
} # }
```
