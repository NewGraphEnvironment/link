# Emit slim crossings_lookup + per-source barriers\_\* tables

Given a `<schema>.crossings` table (bcfp-shaped — produced upstream by
[`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md)
or by loading a bcfp-format external dump) plus optional
`<schema>.dams`, emits five derived tables via filtered SELECTs:

## Usage

``` r
lnk_barriers_emit(conn, schema)
```

## Arguments

- conn:

  A DBI connection.

- schema:

  Working schema name (already-existing). Must contain
  `<schema>.crossings`. Optionally contains `<schema>.dams`; if absent,
  `barriers_dams` is created empty.

## Value

`invisible(NULL)`. Side effect: drops + recreates the five tables in
`schema`.

## Details

- `<schema>.crossings_lookup` (slim id + status projection)

- `<schema>.barriers_anthropogenic` (all barrier-status crossings)

- `<schema>.barriers_pscis` (PSCIS-sourced barrier-status crossings)

- `<schema>.barriers_dams` (dam-sourced barrier-status crossings)

- `<schema>.barriers_remediations` (anthropogenic UNION
  REMEDIATED-PASSABLE)

Output column shapes match what
`lnk_pipeline_access(barrier_sources = list(...))` consumes —
`aggregated_crossings_id` plus the network-position columns
(`linear_feature_id`, `blue_line_key`, `downstream_route_measure`,
`wscode_ltree`, `localcode_ltree`).

Mostly bcfp-shape-specific — it relies on column names/values from
bcfp's `crossings` shape (`barrier_status`, `crossing_source`,
`pscis_status`). Lives in link as the emit step of the new
[`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md)
phase; may move to a future `pac` package once that's scaffolded.

Filters mirror
`bcfishpass/model/01_access/sql/{barriers_anthropogenic,barriers_pscis,barriers_dams,remediations_barriers}.sql`:

- `barrier_status IN ('BARRIER', 'POTENTIAL')` for anthropogenic-style
  tables.

- `blue_line_key = watershed_key` (excludes side-channel features).

- `barriers_remediations` = `barriers_anthropogenic` UNION crossings
  WHERE `pscis_status = 'REMEDIATED' AND barrier_status = 'PASSABLE'`
  (bcfp-intended logic per the v0.30.2 fix; see
  `smnorris/bcfishpass#891`).

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
lnk_pipeline_setup(conn, schema = "working_adms")
# ... lnk_pipeline_crossings(...) populates working_adms.crossings ...
lnk_barriers_emit(conn, schema = "working_adms")
DBI::dbReadTable(conn, c("working_adms", "crossings_lookup"))
} # }
```
