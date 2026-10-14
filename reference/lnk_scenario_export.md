# Publish link's habitat flags per config as Parquet + manifest

Writes a local tree, the layout of `s3://fresh-bc/habitat/fwa/v1/`, from
persisted link runs: one long-form row per stream segment, config and
species, keyed by FWA position, with the flags, the size and gradient
values the run tested, and their ratios to the run's thresholds. A
`manifest.json` names each part's md5 and the log rows of the builds
that produced it;
[`lnk_catalog()`](https://newgraphenvironment.github.io/link/reference/lnk_catalog.md)
reads it and
[`lnk_db_load()`](https://newgraphenvironment.github.io/link/reference/lnk_db_load.md)
loads the parts into PostgreSQL.

## Usage

``` r
lnk_scenario_export(
  conn,
  configs,
  root,
  wsgs = NULL,
  species = NULL,
  shared_segmentation = FALSE,
  replace = FALSE
)
```

## Arguments

- conn:

  A DBI connection to the database holding the persist schemas.

- configs:

  Named character: names are link config names (as logged in
  `<schema>.log.config_name`), values the persist schema holding each. A
  config may name several schemas holding different groups.

- root:

  Directory to write. `segment/` and `manifest.json` are replaced;
  `provenance/` and `config/` accumulate.

- wsgs:

  Watershed groups to export, or `NULL` for every group with a finished
  build of its config (the others are named in a message).

- species:

  Species codes, or `NULL` for every species the config modelled in the
  exported groups.

- shared_segmentation:

  If `TRUE`, stop unless every schema exported holds the same
  segmentation in the groups they share. Set it when the configs are
  variants meant to be compared segment for segment.

- replace:

  An export replaces each config it names. By default it stops if that
  would drop a group or species the root already holds for the config,
  or put an older build of a group in place of a newer one; `TRUE`
  allows it.

## Value

The manifest path, invisibly.

## Details

    <root>/manifest.json
    <root>/segment/config=<config>/species=<sp>/part-<code>.parquet
    <root>/provenance/run_uid=<uid>/run_id=<id>/{log,log_input}.parquet
    <root>/provenance/config_hash=<hex>/log_parameters_*.parquet
    <root>/config/sha256-<hex>/<bundle files>

Rules the export holds to:

- **Key.**
  `(blue_line_key, downstream_route_measure, upstream_route_measure)`.
  Break points differ by config, so neither `linear_feature_id` nor
  link's per-group `id_segment` is a key; cut a segment's line from the
  FWA blue line at its measures.

- **Which groups.** A group is exported only when its latest log row is
  a finished build of the config; there is no other record of the
  thresholds or bundle behind its flags. Provenance is keyed per build;
  a build outside a dispatch (`run_uid` NULL) is kept under
  `provenance/run_id=<run_id>/`.

- **Species.** Every segment has a row for every species the config
  models in the exported groups; a species with no habitat in a group
  reads FALSE.

- **Discharge.** `mad_m3s` is the discharge the run classified on, with
  its logged fill, so `*_ratio_mad` agrees with the flags.

- **Ratios.** Use the thresholds the run logged at its `config_hash`. A
  build that logged none (before link's \#282) has NA ratios for
  spawning and rearing.

- **Bundle files.** Published under `config/` only when today's bundle
  hashes the same as the build; otherwise the manifest records why not.

- **Provenance.** Written once: a provenance file that already exists
  with different bytes stops the export.

## See also

Other export:
[`lnk_catalog()`](https://newgraphenvironment.github.io/link/reference/lnk_catalog.md),
[`lnk_db_load()`](https://newgraphenvironment.github.io/link/reference/lnk_db_load.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn(dbname = "fwapg", host = "localhost", port = 5432L,
                    user = "postgres", password = "postgres")
root <- file.path(tempdir(), "habitat", "fwa", "v1")
lnk_scenario_export(conn, c(default = "fresh_default"), root,
                    wsgs = "DUNC", species = c("BT", "RB"))
cat <- lnk_catalog(file.path(root, "manifest.json"))
cat[, c("config", "species", "code", "rows", "md5")]
} # }
```
