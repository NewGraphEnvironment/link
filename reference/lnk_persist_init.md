# Initialize persistent province-wide habitat tables

Creates `<schema>.streams` and `<schema>.streams_habitat_<sp>` (one per
species) with `IF NOT EXISTS`. Idempotent — safe to call before every
per-WSG run, and safe under concurrent first-time provisioning (multiple
workers can race; only one CREATE wins).

## Usage

``` r
lnk_persist_init(conn, cfg, species)
```

## Arguments

- conn:

  DBI connection.

- cfg:

  An `lnk_config` object with `cfg$pipeline$schema` set.

- species:

  Character vector of species codes (uppercased) to create
  `streams_habitat_<sp>` tables for. Typically derived via
  [`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)
  or `unique(loaded$parameters_fresh$species_code)`.

## Value

`conn` invisibly.

## Details

Per-WSG data accumulates into these tables via
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)
after each run. Queryable cross-WSG for cartography, intrinsic potential
maps, and per-crossing upstream rollups.

Column shape mirrors bcfp's `bcfishpass.streams` +
`bcfishpass.habitat_linear_<sp>` for familiarity. Driven by the
`cols_streams` / `cols_habitat` vectors at the top of this file — single
source of truth shared with
[`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md).

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- lnk_db_conn()
cfg <- lnk_config("bcfishpass")
loaded <- lnk_load_overrides(cfg)
species <- unique(loaded$parameters_fresh$species_code)
lnk_persist_init(conn, cfg, species)
} # }
```
