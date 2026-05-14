# Build crossings + barriers\_\* tables from primitives

Composes the lean primitives-build for one AOI:

## Usage

``` r
lnk_pipeline_crossings(
  conn,
  aoi,
  cfg,
  loaded,
  schema,
  snap_tolerance = 100,
  pscis_table = "whse_fish.pscis_assessment_svw",
  modelled_table = "fresh.modelled_stream_crossings",
  dams_table = paste0(schema, ".dams")
)
```

## Arguments

- conn:

  A DBI connection.

- aoi:

  Watershed group code, e.g. `"ADMS"`.

- cfg:

  An `lnk_config` object. Currently unused; reserved for future
  config-driven knobs (snap tolerance, edge-type exclusions).

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Currently unused directly (overrides already staged by
  [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md));
  kept in the signature for pipeline consistency.

- schema:

  Working schema name (e.g. `"working_adms"`). Must be pre-created via
  [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md).

- snap_tolerance:

  Maximum PSCIS snap distance in metres. Default `100` (matches bcfp).

- pscis_table:

  Source table for PSCIS assessments. Default
  `"whse_fish.pscis_assessment_svw"` — the canonical BCDC view.

- modelled_table:

  Source table for modelled stream crossings. Default
  `"fresh.modelled_stream_crossings"` — populated by
  `data-raw/snapshot_bcfp.sh` (link#137). Province-wide; the AOI filter
  is applied during the union.

- dams_table:

  Source table for CABD dams. Default `paste0(schema, ".dams")` —
  produced per-AOI by
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md).

## Value

`invisible(conn)` for piping.

## Details

1.  [`lnk_inputs_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_inputs_verify.md)
    — required source tables present (PSCIS, dams,
    modelled_stream_crossings already loaded by
    `data-raw/snapshot_bcfp.sh`).

2.  [`lnk_points_snap()`](https://newgraphenvironment.github.io/link/reference/lnk_points_snap.md)
    — snap PSCIS assessments to FWA via lateral KNN.

3.  `.lnk_crossings_union()` — UNION ALL of PSCIS + CABD + modelled
    sources into `<schema>.crossings` (lean column set).

4.  `.lnk_crossings_apply_overrides()` — apply user_pscis_barrier_status

    - user_modelled_crossing_fixes from staging tables loaded by
      [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md).

5.  [`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md)
    — emit `<schema>.crossings_lookup` + four `<schema>.barriers_*`
    tables (filtered SELECTs).

Outputs feed `lnk_pipeline_access(barrier_sources = list(...))`.

Required pre-loaded tables (verified by
[`lnk_inputs_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_inputs_verify.md)
up-front):

- `whse_fish.pscis_assessment_svw` — BCDC PSCIS via Python
  `bcdata bc2pg`.

- `<schema>.modelled_stream_crossings` — bchamp gpkg via curl + ogr2ogr.

- `<schema>.dams` — produced by
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  from CABD.

All three are loaded by `data-raw/snapshot_bcfp.sh` (link#137) +
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
for the `dams` step.

Output tables:

- `<schema>.crossings` — lean union (id + source + statuses + network
  position + geom).

- `<schema>.crossings_lookup` — slim id + statuses projection.

- `<schema>.barriers_anthropogenic`, `<schema>.barriers_pscis`,
  `<schema>.barriers_dams`, `<schema>.barriers_remediations` — filtered
  SELECTs ready for `lnk_pipeline_access(barrier_sources = list(...))`.

## See also

[`lnk_inputs_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_inputs_verify.md),
[`lnk_points_snap()`](https://newgraphenvironment.github.io/link/reference/lnk_points_snap.md),
[`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md),
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)

Other pipeline:
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md),
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("default")
loaded <- lnk_load_overrides(cfg)

lnk_pipeline_setup(conn, schema = "working_adms")
lnk_pipeline_load(conn, "ADMS", cfg, loaded, "working_adms")
lnk_pipeline_prepare(conn, "ADMS", cfg, loaded, "working_adms",
                     conn_tunnel = conn)  # cabd.dams loaded locally per #137
lnk_pipeline_crossings(conn, "ADMS", cfg, loaded, "working_adms")

# Inspect.
DBI::dbReadTable(conn, c("working_adms", "crossings_lookup"))
DBI::dbReadTable(conn, c("working_adms", "barriers_anthropogenic"))
} # }
```
