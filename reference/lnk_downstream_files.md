# Which export files a one-group run needs from the groups downstream of it

A group's access is classified by walking downstream through the
barriers and barrier overrides that every other group persisted. On a
machine that holds only some groups, those rows come from the habitat
export: this lists, for a target group, every group whose rows its walk
can read (the export's dependency map, which errs wide) and the
per-group parts holding them.

## Usage

``` r
lnk_downstream_files(
  manifest,
  wsg,
  config,
  cache_dir = tools::R_user_dir("link", "cache")
)
```

## Arguments

- manifest:

  Path or URL (`s3://`, `https://`) of an export's `manifest.json`.

- wsg:

  The target watershed group.

- config:

  The config whose parts to list, as the export names it.

- cache_dir:

  Where the downloaded dependency map is kept.

## Value

A data frame, one row per dependency and table (one row for a dependency
with nothing to fetch): `target`, `config`, `wsg`, `class`, `reason`,
`table`, `key`, `href`, `rows`, `bytes`, `md5`, `run_id`, `config_hash`,
`link_version`, `link_sha`, `fwa_url`.

## Details

Each dependency is one of:

- `exported`: its `barriers` and `barrier_overrides` parts are listed,
  with the build they came from;

- `skipped`: the export asked for it and had no finished build of the
  config; its rows are not available, and
  [`lnk_downstream_load()`](https://newgraphenvironment.github.io/link/reference/lnk_downstream_load.md)
  refuses unless told to go on without them;

- `not_held`: the export took every group its schemas held and this one
  was not among them, so the provincial walk read no rows of it either;

- `not_exported`: the export named its groups and left this one out.

The target's own rows are not listed: its run writes them. `fwa_url`
names the dependency's FWA stream object, which a machine needs loaded
for the downstream check
([`lnk_wsg_downstream_check()`](https://newgraphenvironment.github.io/link/reference/lnk_wsg_downstream_check.md))
and for the target's own gradient search, which runs along whole lines.

## See also

Other export:
[`lnk_catalog()`](https://newgraphenvironment.github.io/link/reference/lnk_catalog.md),
[`lnk_db_load()`](https://newgraphenvironment.github.io/link/reference/lnk_db_load.md),
[`lnk_downstream_load()`](https://newgraphenvironment.github.io/link/reference/lnk_downstream_load.md),
[`lnk_scenario_export()`](https://newgraphenvironment.github.io/link/reference/lnk_scenario_export.md)

## Examples

``` r
if (FALSE) { # \dontrun{
f <- lnk_downstream_files("s3://fresh-bc/habitat/fwa/v1/manifest.json",
                          wsg = "PARS", config = "default")
f[, c("wsg", "class", "table", "rows")]
} # }
```
