# Create working-schema views over `<persist_schema>.barriers`

Emits per-species + per-source views in the working schema that filter
the unified province-wide `<persist_schema>.barriers` table (link#152).
Each view exposes the bcfp-shape `<table>_id` column
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
expects (`barriers_bt_id`, `barriers_dams_id`, ...) so the existing
`barriers_per_sp` + `barrier_sources` consumer code paths run unchanged.

## Usage

``` r
lnk_barriers_views(
  conn,
  schema,
  cfg,
  species = c("BT", "CH", "CM", "CO", "PK", "SK", "ST", "WCT"),
  barriers_table = NULL
)
```

## Arguments

- conn:

  A DBI connection.

- schema:

  Working schema name where the views are created.

- cfg:

  An `lnk_config` object (resolves `cfg$pipeline$schema` for the
  underlying persist-schema reference).

- species:

  Character vector of species codes the views should cover. Default
  `c("BT","CH","CM","CO","PK","SK","ST","WCT")`.

- barriers_table:

  Character or `NULL`. Source barriers table the views read from.
  Default `NULL` → uses `<persist_schema>.barriers` from `cfg` (the
  original behaviour). Pass a working-schema name (e.g.
  `paste0(schema, ".barriers")`) to build the views over a per-WSG
  working table — used by
  [`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)'s
  mapping_code phase, which runs BEFORE the per-WSG persist write so
  persist barriers may not yet hold current data. Tunnel-free /
  link-canonical either way (the underlying table has `blocks_species`
  from
  [`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md)).

## Value

`invisible(conn)`. Side effect: drops + recreates two views per species
(`_unified` + `_access`) + three source-typed views in `schema`.

## Details

The views point at the province-wide table — cross-WSG dnstr walks
resolve correctly because
[`fresh::frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.html)
walks FWA topology and reads from the view (which is the unified table).
Fixes the PARS BT 60% defect (PARS drains through dams in PCEA / UPCE
WSGs) and unblocks any regional run.

Per-species views (two per species `bt`, `ch`, `cm`, `co`, `pk`, `sk`,
`st`, `wct`):

- `<schema>.barriers_<sp>_unified` — filtered by
  `'<SP>' = ANY(blocks_species)` (ALL barrier families incl dams).
  `_unified` suffix avoids name collision with the per-WSG
  `<schema>.barriers_<sp>` tables that `.lnk_pipeline_prep_minimal`
  builds for the break-time path.

- `<schema>.barriers_<sp>_access` — the per-species **accessibility**
  set that drives `accessible` in mapping_code (link#200). Reproduces
  bcfp `barriers_<sp>`: NATURAL barriers only
  (`barrier_source IN ('GRADIENT','FALLS','SUBSURFACE_FLOW')` — the
  gradient-at-species-threshold is already encoded in `blocks_species`)
  MINUS the observation/habitat override (anti-join
  `barrier_overrides`), ∪ all `USER_DEFINITE` (override-exempt).
  Dams/PSCIS/modelled are excluded — they annotate token2 via the
  per-source views, never block access. Same feature shape
  (`barriers_<sp>_access_id` + ltrees + geom) so
  [`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
  /
  [`fresh::frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.html)
  consume it unchanged. See `RUNBOOK.md` §5.

Per-source views (matching the bcfp source-typed tables consumed by the
`barrier_sources` arg of `lnk_pipeline_access`):

- `<schema>.barriers_anthropogenic_unified` —
  `barrier_source IN ('PSCIS','CABD','MODELLED')`.

- `<schema>.barriers_pscis_unified` — `barrier_source = 'PSCIS'`.

- `<schema>.barriers_dams_unified` — `barrier_source = 'CABD'`.

(Remediations stay sourced from `<schema>.barriers_remediations` built
by
[`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md)
— they're consumed by the `remediated_dnstr_ind` path which joins to
`<schema>.crossings` directly, not via the unified barriers table.)

Views are dropped + recreated on each call (`CREATE OR REPLACE VIEW`) so
reruns are safe. The underlying `<persist_schema>.barriers` table must
exist — typically initialized by
[`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md)
and populated by
[`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md) +
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)
for all WSGs in the regional scope.

## See also

[`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md),
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md)

Other barriers:
[`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md),
[`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)

# ... lnk_persist_init + lnk_pipeline_* + lnk_barriers_unify +
#     lnk_pipeline_persist all already run for all WSGs ...

lnk_barriers_views(conn, schema = "working_pars", cfg = cfg)

lnk_pipeline_access(
  conn,
  segments        = "working_pars.streams",
  aoi             = "PARS",
  barriers_per_sp = setNames(
    paste0("working_pars.barriers_", c("bt","ch","cm","co","pk","sk","st","wct"), "_unified"),
    c("bt","ch","cm","co","pk","sk","st","wct")),
  barrier_sources = list(
    anthropogenic = "working_pars.barriers_anthropogenic_unified",
    pscis         = "working_pars.barriers_pscis_unified",
    dams          = "working_pars.barriers_dams_unified",
    remediations  = "working_pars.barriers_remediations"))
} # }
```
