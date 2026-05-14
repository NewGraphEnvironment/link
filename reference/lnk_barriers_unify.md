# Unify per-WSG barrier sources into the working-schema `<schema>.barriers`

Consolidates four barrier families from the per-WSG working schema
(`<schema>.crossings`, `<schema>.gradient_barriers_raw`,
`<schema>.falls`, `<schema>.barriers_subsurfaceflow`) into one
`<schema>.barriers` table matching the cols_barriers shape used by the
persistent province-wide `<persist_schema>.barriers`. Each row carries a
pre-computed `blocks_species text[]` predicate that
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
queries via `WHERE 'BT' = ANY(blocks_species)`.

## Usage

``` r
lnk_barriers_unify(
  conn,
  aoi,
  cfg,
  loaded,
  schema = paste0("working_", tolower(aoi)),
  species = NULL
)
```

## Arguments

- conn:

  A DBI connection.

- aoi:

  Watershed group code, e.g. `"PARS"`.

- cfg:

  An `lnk_config` object.

- loaded:

  Named list from
  [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md).
  Must include `loaded$parameters_fresh` (used to derive gradient-class
  `blocks_species`).

- schema:

  Working schema name (per-WSG staging). Default
  `paste0("working_", tolower(aoi))`.

- species:

  Character vector of species codes whose access thresholds drive the
  gradient `blocks_species` derivation. Default
  `unique(loaded$parameters_fresh$species_code)`. Pass a subset (e.g.
  the 8 bcfp species) to control which species the gradient
  blocks_species column references.

## Value

`invisible(conn)`. Side effect: drops + recreates `<schema>.barriers`.

## Details

Per-WSG output is persisted to the province-wide table by
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)
using the same idempotent DELETE-WHERE-WSG + INSERT pattern already used
for `streams` and `streams_habitat_<sp>`. Cross-WSG `dam_dnstr_ind`
resolves correctly because
[`fresh::frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.html)
walks FWA topology and doesn't care which WSG a barrier physically lives
in — fixes the PARS BT 60% defect (PARS drains through dams in PCEA/UPCE
WSGs) and unblocks any regional run.

Source families + `blocks_species` semantics:

- **Anthropogenic**
  (`barrier_source IN ('PSCIS','CABD','MODELLED_CROSSINGS')`, from
  `<schema>.crossings WHERE barrier_status IN ('BARRIER','POTENTIAL')`):
  blocks all 8 species. `crossing_source` is mapped through verbatim,
  keeping the `MODELLED_CROSSINGS` value (vs. lossy normalization to
  `MODELLED`).

- **Gradient** (`barrier_source = 'GRADIENT'`, from
  `<schema>.gradient_barriers_raw`): blocks species whose
  `access_gradient_max <= gradient_class / 100`. Derived per row from
  `loaded$parameters_fresh`.

- **Falls** (`barrier_source = 'FALLS'`, from `<schema>.falls`): blocks
  all 8 species.

- **Subsurface_flow** (`barrier_source = 'SUBSURFACE_FLOW'`, from
  `<schema>.barriers_subsurfaceflow`): blocks all 8 species. Opt-in
  (only built when `cfg$pipeline$break_order` includes
  `"subsurfaceflow"`).

Remediations (PASSABLE remediation crossings) are intentionally NOT in
this table. They're consumed via `<schema>.barriers_remediations`
(emitted by
[`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md))
for the `remediated_dnstr_ind` sequence-aware logic in
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
which joins to `<schema>.crossings` directly.

`id_barrier` is namespaced per source family so rows stay unique inside
a WSG without coordinating sequence IDs across sources. Mirrors the
offset trick `.lnk_crossings_union` uses for modelled crossings.

Required pre-existing tables in `schema`:

- `<schema>.crossings` (from
  [`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md)).

- `<schema>.gradient_barriers_raw` (from
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)).

- `<schema>.falls` (from
  [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)).

Optional:

- `<schema>.barriers_subsurfaceflow` (only when the config opts in).

## See also

[`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md),
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md),
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)

Other barriers:
[`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md),
[`lnk_barriers_views()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_views.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)

lnk_pipeline_setup(conn, schema = "working_pars")
lnk_pipeline_load(conn, "PARS", cfg, loaded, "working_pars")
lnk_pipeline_prepare(conn, "PARS", cfg, loaded, "working_pars",
                     conn_tunnel = conn)
lnk_pipeline_crossings(conn, "PARS", cfg, loaded, "working_pars")
lnk_barriers_unify(conn, aoi = "PARS", cfg = cfg, loaded = loaded,
                   schema = "working_pars")

DBI::dbReadTable(conn, c("working_pars", "barriers"))
} # }
```
