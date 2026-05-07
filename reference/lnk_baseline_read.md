# Read the run-tracking baseline ledger

Loads the per-run baseline CSV (each row stamps which upstream build a
particular comparison or sync ran against) into a tibble and validates
the column shape matches `cols_baseline`.

## Usage

``` r
lnk_baseline_read(path = "data-raw/logs/bcfp_baselines.csv")
```

## Arguments

- path:

  Path to the ledger CSV. Defaults to `data-raw/logs/bcfp_baselines.csv`
  relative to the working directory.

## Value

A tibble with one row per recorded run. Columns: `run_started_pdt`,
`host`, `run_label`, `link_schema`, `bcfp_model_run_id`,
`bcfp_model_version`, `bcfp_date_completed`, `notes`. All character.
`bcfp_model_run_id` may be empty for workflow-generated rows that lacked
DB-tunnel access (Path 2).

## Details

Companion:
[`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md)
writes rows; this reads them.

Fails loud if the file's column header doesn't match `cols_baseline`.
Schema migrations to the ledger should update `cols_baseline` in
`R/lnk_baseline_read.R` and migrate the CSV in lockstep.

## See also

[`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md)

Other baseline:
[`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md)

## Examples

``` r
if (FALSE) { # \dontrun{
baseline <- lnk_baseline_read()
tail(baseline)

# Filter to csv-sync-generated rows.
subset(baseline, grepl("^csv-sync-", run_label))
} # }
```
