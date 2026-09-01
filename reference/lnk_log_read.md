# Read the run-provenance log from a persist schema

Answers "which config produced this network, and when" without
hand-written SQL. One row per
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
call; by default only the most recent run per watershed group.

## Usage

``` r
lnk_log_read(
  conn,
  cfg,
  aoi = NULL,
  latest = TRUE,
  run_uid = NULL,
  phase = c("model", "recompute")
)
```

## Arguments

- conn:

  DBI connection to the pipeline database.

- cfg:

  An `lnk_config` object — supplies the persist schema.

- aoi:

  Optional watershed group code to filter to.

- latest:

  Logical. When `TRUE` (default), return only the newest run per
  watershed group. `FALSE` returns the full history. **Ignored when
  `run_uid` is supplied** — see below.

- run_uid:

  Optional dispatch identifier (link#262). One dispatch of
  `data-raw/study_area_run.sh` stamps the same `run_uid` on every host
  and every watershed group, so this is what answers "everything from
  that run" without a time window. Supplying it forces `latest = FALSE`:
  the question is "every row of this run", and `DISTINCT ON` would
  silently drop a WSG that was re-run within the same dispatch.

- phase:

  Which log to read. `"model"` (default) reads `<schema>.log`, one row
  per
  [`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
  call. `"recompute"` reads `<schema>.log_recompute`, one row per
  `wsg_recompute_one.R` invocation — the post-consolidate pass that
  rewrites `streams_access` and `streams_mapping_code`, which is the
  output that ships.

## Value

A tibble, newest first.

## Details

A watershed group present in `<persist_schema>.streams` but absent here
was modelled before provenance logging existed (link#127) — absence
means pre-provenance vintage, not an error. Rows are never backfilled,
because the config and code state that produced them is not recoverable
and a synthetic row would be fabricated provenance.

## See also

Other compare:
[`lnk_access()`](https://newgraphenvironment.github.io/link/reference/lnk_access.md),
[`lnk_compare_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_mapping_code.md),
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md),
[`lnk_rollup_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_rollup_wsg.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg  <- lnk_config("default")

# What produced the current PINE network?
lnk_log_read(conn, cfg, aoi = "PINE")

# Every run, newest first.
lnk_log_read(conn, cfg, latest = FALSE)

# Everything from one dispatch, across every host — no time window.
lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1")

# Was each of those WSGs also recomputed?
lnk_log_read(conn, cfg, run_uid = "20260901T184455-3f9ac1",
             phase = "recompute")
} # }
```
