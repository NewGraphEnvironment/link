# Run the link pipeline end-to-end for one watershed group

Modelling-only umbrella: chains the `lnk_pipeline_*` phases and the
persist write-out into a single call. Produces per-WSG segment data in
the persistent province-wide tables (`<persist_schema>.streams`,
`streams_habitat_<sp>` per species, `barriers`).

## Usage

``` r
lnk_pipeline_run(
  conn,
  aoi,
  cfg,
  loaded,
  schema = paste0("working_", tolower(aoi)),
  dams = TRUE,
  cleanup_working = TRUE,
  mapping_code = FALSE
)
```

## Arguments

- conn:

  DBI connection to the local pipeline database (typically localhost
  fwapg).

- aoi:

  Watershed group code (e.g. `"ADMS"`). Validated against
  `^[A-Z]{3,5}$`.

- cfg:

  An `lnk_config` object (from
  [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)).

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).

- schema:

  Working schema name. Default `paste0("working_", tolower(aoi))`.
  Per-WSG staging tables live here; dropped on exit when
  `cleanup_working = TRUE`.

- dams:

  Logical. When `TRUE` (default), pass `conn` as `conn_tunnel` to
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  so the CABD dams step runs from local `cabd.dams`. Pass `FALSE` to
  skip dams entirely.

- cleanup_working:

  Logical. When `TRUE` (default), drop the `<schema>` working schema at
  the end. Pass `FALSE` for interactive debug / manual inspection.

- mapping_code:

  Logical. When `TRUE`, additionally runs the tunnel-free mapping_code
  build phase (10b above) — produces `<persist_schema>.streams_access`
  and `<persist_schema>.streams_mapping_code` for the WSG, consumed
  downstream by `data-raw/build_species_views.R --bcfp` (QGIS bcfp-
  shape symbology). Default `FALSE`. Methodology shift from pre-#187
  compare_wsg: access uses link's own per-species barriers (via
  `blocks_species` predicate on `<schema>.barriers`), not bcfp's
  tunnel-staged tables.

## Value

`conn`, invisibly. Side effects are the writes into
`<persist_schema>.streams`, `streams_habitat_<sp>`, and `barriers`.

## Details

This is the **modelling boundary** — the link package's deliverable.
Comparison against bcfishpass (or any future reference) lives in
[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
which reads the persisted state. The split lets re-running the pipeline
and re-running the comparison happen independently; an orchestrator
loop's resume check can probe PG state via `link:::.lnk_wsg_persisted()`
rather than the comparison RDS artifact.

### Phase order

1.  [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
    — create per-WSG working schema.

2.  [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md)
    — crossings + modelled fixes + PSCIS status.

3.  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
    — falls, definite + control, habitat confirms, gradient barriers,
    natural barriers, barrier overrides, per-model minimal reduction,
    base segments. Passes `conn` as `conn_tunnel` when `dams = TRUE` so
    CABD dams flow through.

4.  [`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md)
    — match PSCIS to modelled crossings.

5.  [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
    — observations, gradient minimal, definite, habitat endpoints,
    crossings — in config-defined order.

6.  [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
    — assemble `streams_breaks` and run `frs_habitat_classify()`.

7.  [`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
    — per-species cluster + connected_waterbody.

8.  [`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)
    — resolve the active species set for this AOI (cfg\$species ∩
    wsg_species_presence). Empty set is an error.

9.  [`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md)
    — create persistent target tables if absent.

10. [`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md)
    — unify per-source barriers into a single working-schema table
    (always; promotes the mapping_code-only flag in
    [`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md)
    to canonical PG state). 10b. *Optional* mapping_code phase — gated
    by `mapping_code = TRUE`. Runs between barriers_unify and persist:
    [`lnk_barriers_views()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_views.md)
    over working `<schema>.barriers` (tunnel- free, link-canonical
    per-species views),
    [`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
    (writes working `streams_access`),
    [`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md)
    (writes working `streams_mapping_code`). Persist phase copies both
    to `<persist_schema>`. See link#187.

11. [`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)
    — copy per-WSG streams + per-species habitat + barriers (+ optional
    streams_access + streams_mapping_code) into `<persist_schema>`
    (idempotent DELETE-WHERE-WSG + INSERT).

## See also

[`lnk_compare_rollup()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_rollup.md),
[`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)

Other pipeline:
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md),
[`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md),
[`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md),
[`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md),
[`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md),
[`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md),
[`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md),
[`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md),
[`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md),
[`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)

# Model one WSG end-to-end (~70s)
lnk_pipeline_run(conn = conn, aoi = "ADMS",
                 cfg = cfg, loaded = loaded)

# Verify PG state
DBI::dbGetQuery(conn,
  "SELECT count(*) FROM fresh.streams WHERE watershed_group_code = 'ADMS'")
} # }
```
