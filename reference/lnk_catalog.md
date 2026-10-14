# Read a habitat export's manifest

The manifest written by
[`lnk_scenario_export()`](https://newgraphenvironment.github.io/link/reference/lnk_scenario_export.md)
is the only index of a published tree: the bucket is not listable, so
readers go through it. Each part's Hive fields (`config`, `species`,
`code`) come from its key, the one place they are written, and its
`href` resolves relative to the manifest.

## Usage

``` r
lnk_catalog(manifest)
```

## Arguments

- manifest:

  Path or URL of `manifest.json`.

## Value

A data frame, one row per part: `dataset`, `config`, `species`, `code`,
`drainage`, `wsgs`, `key`, `href`, `rows`, `bytes`, `md5`. Attributes:
`manifest` (where it was read), `id`, `built`, `provenance`, `configs`
(per config: the log rows of each build, config hashes, discharge,
bundles) and `files` (the provenance and bundle files).

## Details

`manifest` may be a local path, an `https://` URL (an anonymous read,
for a public prefix) or an `s3://` URL. An `s3://` read goes through the
`aws` command line with the caller's credentials, which a private prefix
needs: `habitat/` is staged private (link#308).

## See also

Other export:
[`lnk_db_load()`](https://newgraphenvironment.github.io/link/reference/lnk_db_load.md),
[`lnk_scenario_export()`](https://newgraphenvironment.github.io/link/reference/lnk_scenario_export.md)

## Examples

``` r
if (FALSE) { # \dontrun{
cat <- lnk_catalog("s3://fresh-bc/habitat/fwa/v1/manifest.json")
table(cat$config, cat$species)

# which builds produced the default config's parts?
runs <- attr(cat, "configs")[[1]]$runs
vapply(runs, function(r) r$run_id, character(1))
} # }
```
