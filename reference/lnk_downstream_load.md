# Load the downstream groups' barriers into a persist schema

Puts the `barriers` and `barrier_overrides` rows that
[`lnk_downstream_files()`](https://newgraphenvironment.github.io/link/reference/lnk_downstream_files.md)
lists into the persist schema `cfg` names (`cfg$pipeline$schema`, set as
the run will set it), so a
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
of the target there walks downstream through the rows the provincial
run's walk read. Each part is fetched and checked for size and md5
before the database is touched; every group is then replaced in one
transaction, with each part's row count checked, and recorded in
`<schema>.log_downstream_load`.

## Usage

``` r
lnk_downstream_load(
  conn,
  files,
  cfg,
  replace = FALSE,
  allow_missing = FALSE,
  cache_dir = tools::R_user_dir("link", "cache")
)
```

## Arguments

- conn:

  DBI connection to the target database.

- files:

  The data frame
  [`lnk_downstream_files()`](https://newgraphenvironment.github.io/link/reference/lnk_downstream_files.md)
  returns, for one target and config.

- cfg:

  The `lnk_config` the target will be modelled with, its
  `pipeline$schema` set to the persist schema the run writes.

- replace:

  Replace a dependency group's rows even when this schema built them, or
  holds them from no recorded load.

- allow_missing:

  Load what the export has even when some dependencies' rows are not in
  it.

- cache_dir:

  Where downloaded parts are kept.

## Value

Invisibly, a data frame per dependency loaded: `wsg`, `run_id`,
`barriers`, `barrier_overrides` (rows; NA for a table `files` did not
list), `config_hash`, `config_same`.

## Details

It refuses, before writing, when a dependency's rows are not in the
export (`skipped` or `not_exported`, unless `allow_missing`), and when
the schema holds rows of a dependency group that did not come from an
earlier load: a build of the group here (a finished `<schema>.log` row),
or rows of unknown origin (unless `replace`).

It reports, without refusing, each dependency build whose `config_hash`
differs from `cfg`'s bundle (the rows were built under other rules than
the target will be), and each input whose identity here differs from
what the dependencies were built from: CABD's and PSCIS's content md5,
the observations' and modelled crossings' loader version id (attribute
`inputs_differ` of the result, whose `state` is `differs` or
`not compared`: an input the build recorded no identity for is named,
not passed over). The target's own inputs on this machine still decide
its own barriers and lifts.

## See also

Other export:
[`lnk_catalog()`](https://newgraphenvironment.github.io/link/reference/lnk_catalog.md),
[`lnk_db_load()`](https://newgraphenvironment.github.io/link/reference/lnk_db_load.md),
[`lnk_downstream_files()`](https://newgraphenvironment.github.io/link/reference/lnk_downstream_files.md),
[`lnk_scenario_export()`](https://newgraphenvironment.github.io/link/reference/lnk_scenario_export.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
cfg <- lnk_config("default")
cfg$pipeline$schema <- "fresh_default"
f <- lnk_downstream_files("s3://fresh-bc/habitat/fwa/v1/manifest.json",
                          wsg = "PARS", config = "default")
lnk_downstream_load(conn, f, cfg)
} # }
```
