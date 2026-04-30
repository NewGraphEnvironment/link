# Capture a Pipeline Run Stamp

Returns a structured snapshot of every input that influences a
habitat-classification run: config-bundle provenance with current
checksums, software versions and git SHAs, optional database snapshot
counts, plus AOI and timestamps. The stamp is the artifact that makes
pipeline drift attributable — diff two stamps to localize "what changed"
between two runs.

## Usage

``` r
lnk_stamp(
  cfg,
  conn = NULL,
  aoi = NULL,
  db_snapshot = TRUE,
  start_time = Sys.time()
)
```

## Arguments

- cfg:

  An `lnk_config` object from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md).

- conn:

  Optional
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  for local fwapg. When non-`NULL` and `db_snapshot = TRUE`, populates
  the `db` slot with row counts from `bcfishobs.observations` and
  `whse_basemapping.fwa_stream_networks_sp`. When `NULL`, `db` is
  `NULL`.

- aoi:

  Optional character. Watershed group code or arbitrary AOI identifier.
  Recorded verbatim in `stamp$run$aoi`.

- db_snapshot:

  Logical. When `FALSE`, skips DB row-count queries even if `conn` is
  provided. Default `TRUE`.

- start_time:

  A [`base::Sys.time()`](https://rdrr.io/r/base/Sys.time.html) value.
  Default [`Sys.time()`](https://rdrr.io/r/base/Sys.time.html) captured
  at the call. Override only when reconstructing a stamp from a known
  start.

## Value

An `lnk_stamp` S3 list with these slots:

- `config_name` — `cfg$name`

- `config_dir` — `cfg$dir`

- `provenance` — output of
  [`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md)
  called on `cfg` at stamp time (carries observed checksums + drift
  status)

- `software` — list of versions + git SHAs for `link`, `fresh`, plus
  `R.version.string`

- `db` — list of DB snapshot counts, or `NULL`

- `run` — list with `aoi`, `start_time`, `end_time` (initially `NULL` —
  set by
  [`lnk_stamp_finish()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp_finish.md))

- `result` — the result tibble or `NULL` (set by
  [`lnk_stamp_finish()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp_finish.md))

## Details

Workflow:

    stamp <- lnk_stamp(cfg, conn, aoi = "ADMS")
    # ... run pipeline ...
    stamp <- lnk_stamp_finish(stamp, result = comparison_tibble)
    message(format(stamp, "markdown"))

The markdown rendering is one of multiple output formats; covers the
report-appendix scope of [issue
\#24](https://github.com/NewGraphEnvironment/link/issues/24).

## See also

Other stamp:
[`lnk_stamp_finish()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp_finish.md)

## Examples

``` r
cfg <- lnk_config("bcfishpass")
stamp <- lnk_stamp(cfg, aoi = "ADMS")
stamp
#> <lnk_stamp> bcfishpass
#>   aoi:        ADMS
#>   started:    2026-04-30 12:39:47 UTC
#>   link:       0.18.1
#>   fresh:      0.24.1
#>   provenance: 12 files (0 byte, 0 shape drifted)
format(stamp, "markdown")
#> [1] "## Run stamp — bcfishpass\n\n- AOI: `ADMS`\n- Started: 2026-04-30 12:39:47 UTC\n\n### Software\n- link: 0.18.1 (sha NA)\n- fresh: 0.24.1 (sha NA)\n- R: R version 4.6.0 (2026-04-24)\n\n### Config provenance (12 files, 0 byte / 0 shape drifted)\n\n| file | byte drift | shape drift |\n|---|---|---|\n| `rules.yaml` | no | no |\n| `dimensions.csv` | no | no |\n| `parameters_fresh.csv` | no | no |\n| `overrides/user_habitat_classification.csv` | no | no |\n| `overrides/observation_exclusions.csv` | no | no |\n| `overrides/wsg_species_presence.csv` | no | no |\n| `overrides/user_modelled_crossing_fixes.csv` | no | no |\n| `overrides/user_pscis_barrier_status.csv` | no | no |\n| `overrides/pscis_modelledcrossings_streams_xref.csv` | no | no |\n| `overrides/user_barriers_definite.csv` | no | no |\n| `overrides/user_barriers_definite_control.csv` | no | no |\n| `overrides/user_crossings_misc.csv` | no | no |"

if (FALSE) { # \dontrun{
# Full workflow with DB and a result
conn <- lnk_db_conn()
stamp <- lnk_stamp(cfg, conn, aoi = "ADMS")
result <- compare_bcfishpass_wsg(wsg = "ADMS", config = cfg)
stamp <- lnk_stamp_finish(stamp, result = result)
writeLines(format(stamp, "markdown"), "stamp.md")
} # }
```
