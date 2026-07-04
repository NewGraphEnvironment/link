# Build per-segment per-species access from schema tables (portable)

Schema-aware portable wrapper around
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
— the access twin of
[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md).
Builds the per-species `barriers_<sp>_access` + per-source views
internally (via
[`lnk_barriers_views()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_views.md))
over `table_barriers`, then computes the wide `streams_access` shape for
`aoi` and writes it to `table_to`.

## Usage

``` r
lnk_access(
  conn,
  cfg,
  aoi,
  table_streams,
  table_barriers,
  table_to,
  merge = FALSE,
  presence = NULL,
  species = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to the local pipeline DB.

- cfg:

  An `lnk_config` object.

- aoi:

  Character. Watershed group code (e.g. `"PARS"`).

- table_streams:

  Character. Schema-qualified `streams` table (the segments).

- table_barriers:

  Character. Schema-qualified unified `barriers` table. The per-species
  `_access` + source `_unified` views are built over it internally via
  [`lnk_barriers_views()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_views.md).

- table_to:

  Character. Schema-qualified destination `streams_access` table. With
  `merge = TRUE` it must already exist (rows for `aoi` are UPDATEd in
  place).

- merge:

  Logical. `FALSE` (default) overwrites `table_to`. `TRUE` surgically
  UPDATEs `table_to`'s `aoi` rows (recompute; see Merge mode).

- presence:

  An `lnk_presence` object or `NULL`. Per-species presence for `aoi`;
  pass-through to
  [`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md).

- species:

  Character vector of species codes. Default `cfg$species`.

## Value

`conn` invisibly.

## Details

Works against working-schema tables (mid-pipeline) or persist-schema
tables (ad-hoc / post-consolidate recompute) without modification — the
caller passes explicit `table_<role>` names. The caller passes ONE
`table_barriers` (the unified `barriers` table); the per-species access
set and the source-typed views are derived from it internally, so no
pre-built `barriers_per_sp` list is needed (that stays the lower-level
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
surface).

## Merge (recompute) mode

`merge = TRUE` is the **post-consolidate recompute** (link#205). A WSG's
accessibility depends on barriers *downstream*, possibly in another WSG
(the provincial-accumulation property, RUNBOOK.md §5); when WSGs are
modelled on separate hosts each sees only its own barriers, so the
per-host `streams_access` can be wrong cross-WSG. Once all barriers are
consolidated, `merge = TRUE` re-settles ONLY the cross-WSG columns
(`has_barriers_<sp>_dnstr`,
`has_barriers_{anthropogenic,pscis,dams}_dnstr`, `dam_dnstr_ind`)
against the complete `table_barriers`, reusing the already-persisted
`streams` + `streams_habitat` — far cheaper than a full
[`lnk_pipeline_run()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_run.md)
(which re-derives streams + habitat). It UPDATEs the existing `table_to`
rows for `aoi` and **preserves** the within-WSG columns the recompute
does not touch:

- `remediated_dnstr_ind` (and `has_barriers_remediations_dnstr`) —
  depend on the working-schema `crossings`/remediations, correct from
  the prior compute and within-WSG in practice.

- the observed-upstream distinction in `access_<sp>`: set to `0` when
  newly blocked, else kept at `2` where the prior compute had an
  observation, else `1`.

`observations`/`crossings` are intentionally skipped (`NULL`): they only
drive the access 1-vs-2 code + `remediated_dnstr_ind` (both preserved
above); mapping_code's `accessible = !has_barriers_<sp>_dnstr` is
independent of them.

`merge = FALSE` (default) overwrites `table_to` via
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
— first-compute, intended for a working / scratch table (it drops +
recreates the target as a flat `id_segment`-keyed table, so do NOT point
it at a persist table; use `merge = TRUE` for persist).

## See also

[`lnk_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_mapping_code.md),
[`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md),
[`lnk_barriers_views()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_views.md)

Other compare:
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
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
pres <- lnk_presence(loaded$wsg_species_presence, "PARS")

# Post-consolidate recompute against persist (cheap; cross-WSG correct):
lnk_access(
  conn, cfg, aoi = "PARS",
  table_streams  = "fresh.streams",
  table_barriers = "fresh.barriers",
  table_to       = "fresh.streams_access",
  merge          = TRUE, presence = pres)
lnk_mapping_code(
  conn,
  table_access  = "fresh.streams_access",
  table_habitat = "fresh.streams_habitat_long_vw",
  table_streams = "fresh.streams",
  aoi           = "PARS",
  table_to      = "fresh.streams_mapping_code",
  presence      = pres)
} # }
```
