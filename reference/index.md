# Package index

## Thresholds

Configurable scoring defaults

- [`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md)
  : Load configurable severity scoring thresholds

## Database

Connection and utilities

- [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)
  : Connect to FWA PostgreSQL database

## Overrides

Load, validate, and apply correction data

- [`lnk_override_apply()`](https://newgraphenvironment.github.io/link/reference/lnk_override_apply.md)
  : Apply overrides to a crossings table
- [`lnk_override_load()`](https://newgraphenvironment.github.io/link/reference/lnk_override_load.md)
  : Load override CSVs into a database table
- [`lnk_override_validate()`](https://newgraphenvironment.github.io/link/reference/lnk_override_validate.md)
  : Validate override referential integrity

## Matching

Link crossing records across data systems

- [`lnk_match_moti()`](https://newgraphenvironment.github.io/link/reference/lnk_match_moti.md)
  : Match MOTI culverts to crossings
- [`lnk_match_pscis()`](https://newgraphenvironment.github.io/link/reference/lnk_match_pscis.md)
  : Match PSCIS assessments to modelled crossings
- [`lnk_match_sources()`](https://newgraphenvironment.github.io/link/reference/lnk_match_sources.md)
  : Match crossing records across multiple data systems

## Scoring

Severity classification and custom scoring

- [`lnk_score_custom()`](https://newgraphenvironment.github.io/link/reference/lnk_score_custom.md)
  : Apply user-defined scoring rules
- [`lnk_score_severity()`](https://newgraphenvironment.github.io/link/reference/lnk_score_severity.md)
  : Classify crossings by biological impact severity

## Bridge

Produce fresh-compatible break source tables

- [`lnk_break_source()`](https://newgraphenvironment.github.io/link/reference/lnk_break_source.md)
  : Produce a fresh-compatible break source list

## Habitat

Per-crossing upstream habitat rollup

- [`lnk_habitat_upstream()`](https://newgraphenvironment.github.io/link/reference/lnk_habitat_upstream.md)
  : Compute upstream habitat per crossing
