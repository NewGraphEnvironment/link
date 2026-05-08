# Is this host's baseline already current at the supplied upstream?

Predicate helper for `data-raw/snapshot_bcfp.sh` and any other host-side
snapshot driver. Returns `TRUE` when the most recent ledger row for this
host already stamps the same upstream build that `log` carries — meaning
the local snapshot is already aligned with the bucket and re-running
would just churn.

## Usage

``` r
lnk_baseline_current(
  log,
  host = Sys.info()[["nodename"]],
  path = "data-raw/logs/bcfp_baselines.csv"
)
```

## Arguments

- log:

  A list with at minimum `model_version` (e.g. the return of
  [`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)).

- host:

  Hostname to scope the check by. Defaults to
  `Sys.info()[["nodename"]]`. Pass an explicit value to test other
  hosts' rows.

- path:

  Path to the ledger CSV. Defaults to `data-raw/logs/bcfp_baselines.csv`
  relative to the working directory.

## Value

`TRUE` when the latest row for `host` matches `log$model_version`
(snapshot can be skipped — the host is already current at this upstream
build). `FALSE` otherwise — including when the ledger file is missing,
has no rows for `host`, or has a different model_version on its latest
row for this host.

## Details

Per-host scoping is deliberate. Different hosts (M4, M1, cypher) each
populate their own local Postgres; one host stamping this week's SHA
must not gate the others. The predicate filters the ledger to rows where
`host == <this host>` before checking.

"Latest row for host" means the row with the lexicographically greatest
`run_started_pdt` among rows where `host` matches. The ledger's
`run_started_pdt` is written as `YYYY-MM-DD HH:MM` (PDT/PST), so
lexicographic ordering is also chronological ordering as long as the
format stays stable.

## See also

[`lnk_baseline_read()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_read.md),
[`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md),
[`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)

Other baseline:
[`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md),
[`lnk_baseline_read()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_read.md)

## Examples

``` r
if (FALSE) { # \dontrun{
log <- lnk_bucket_log()

if (lnk_baseline_current(log)) {
  message("This host already snapshotted at ", log$model_version,
          "; skipping.")
  quit(status = 0)
}
# ... otherwise proceed with the snapshot ...
} # }
```
