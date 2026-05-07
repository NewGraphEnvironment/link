# Read the build-identifier `log.json` from a bucket prefix

Sugar over
[`lnk_bucket_get()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_get.md)
for the most common read: parse the `log.json` file at the top of a
versioned S3 prefix into a named list.

## Usage

``` r
lnk_bucket_log(
  prefix = "https://fresh-bc.s3.us-west-2.amazonaws.com/bcfishpass"
)
```

## Arguments

- prefix:

  Bucket prefix as an HTTPS URL. Defaults to NGE's bcfp dump prefix.

## Value

A named list with at minimum `model_version`, `date_completed`,
`head_sha`. Function fails loud if any of these required keys are
missing — the contract with the upstream dump workflow.

## Details

For NGE's bcfp dump (default prefix), `log.json` carries the SHA the
tunnel was rebuilt from, the model_version string, and the rebuild
completion timestamp. Downstream consumers (csv-sync, parity drivers)
use these to stamp run inputs and tie comparison rollups to a specific
upstream build.

## See also

[`lnk_bucket_get()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_get.md),
[`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md)

Other bucket:
[`lnk_bucket_get()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_get.md)

## Examples

``` r
if (FALSE) { # \dontrun{
log <- lnk_bucket_log()
log$model_version    # e.g. "v0.7.14-125-g6e9cf1c"
log$date_completed   # e.g. "2026-05-06T04:15:41Z"
substr(log$head_sha, 1, 7)

# Pass to lnk_baseline_append() to stamp a run.
lnk_baseline_append(log, run_label = "csv-sync-20260507",
                    path = tempfile(fileext = ".csv"))
} # }
```
