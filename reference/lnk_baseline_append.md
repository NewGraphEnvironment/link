# Append a row to the run-tracking baseline ledger

Records that a particular run (csv-sync, parity comparison, etc.) ran
against a specific upstream build. Constructs row from the
[`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)
result + caller-supplied `run_label` / `notes`. Stamps `run_started_pdt`
(Pacific) and `host` (`Sys.info()[["nodename"]]`) automatically.

## Usage

``` r
lnk_baseline_append(
  log,
  run_label,
  link_schema = "n/a",
  notes = "",
  path = "data-raw/logs/bcfp_baselines.csv"
)
```

## Arguments

- log:

  A list with at minimum `model_version` and `date_completed`. Optional
  `head_sha` (full or short). The shape returned by
  [`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)
  qualifies; hand-built lists also work.

- run_label:

  A string identifying the run, e.g. `"csv-sync-20260507"`,
  `"provincial_default_extrabreaks"`.

- link_schema:

  The persistent target schema for the run, when applicable. Defaults to
  `"n/a"` for runs that don't write a pipeline schema (csv-sync, etc.).

- notes:

  Free-form notes column. Useful for short-sha references or any per-run
  context worth recording.

- path:

  Path to the ledger CSV. Defaults to
  `data-raw/logs/bcfp_baselines.csv`. Created with the canonical header
  if it does not yet exist.

## Value

The path the row was appended to, invisibly.

## Details

Validates ledger column shape on append: fails loud if the CSV header
doesn't match the expected `cols_baseline` shape (drift in the ledger
file is signaled, not silently corrupted).

`bcfp_model_run_id` is populated from `log$model_run_id` if present,
otherwise empty. The Path-2 (no DB tunnel) workflow doesn't have access
to `bcfishpass.log.model_run_id`; the SHA in `log$model_version` /
`log$head_sha` still uniquely identifies the upstream build.

## See also

[`lnk_baseline_read()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_read.md),
[`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)

Other baseline:
[`lnk_baseline_read()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_read.md)

## Examples

``` r
if (FALSE) { # \dontrun{
log <- lnk_bucket_log()
tmp <- withr::local_tempfile(fileext = ".csv")
lnk_baseline_append(log,
                    run_label = "csv-sync-20260507",
                    notes = paste0("auto-append; head_sha=",
                                   substr(log$head_sha, 1, 7)),
                    path = tmp)
lnk_baseline_read(tmp)
} # }
```
