# Package index

## Thresholds

Configurable scoring defaults

- [`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md)
  : Load configurable severity scoring thresholds

## Database

Connection and utilities

- [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)
  : Connect to FWA PostgreSQL database

## Loading

Load and validate CSV data into database

- [`lnk_load()`](https://newgraphenvironment.github.io/link/reference/lnk_load.md)
  : Load override CSVs into a database table

## Overrides

Validate and apply correction data

- [`lnk_override()`](https://newgraphenvironment.github.io/link/reference/lnk_override.md)
  : Validate and apply overrides to a table

## Barrier Overrides

Build species-specific barrier skip lists from observations and habitat
confirmations

- [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  : Build barrier override list from evidence sources

## Rules

Build habitat rules YAML from dimensions CSV

- [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  : Build habitat eligibility rules YAML from dimensions CSV

## Matching

Link crossing records across data systems

- [`lnk_match()`](https://newgraphenvironment.github.io/link/reference/lnk_match.md)
  : Match crossing records across data systems

## Scoring

Severity classification and custom scoring

- [`lnk_score()`](https://newgraphenvironment.github.io/link/reference/lnk_score.md)
  : Score crossings

## Bridge

Produce fresh-compatible break source tables

- [`lnk_source()`](https://newgraphenvironment.github.io/link/reference/lnk_source.md)
  : Produce a fresh-compatible break source list

## Habitat

Per-crossing upstream habitat rollup

- [`lnk_aggregate()`](https://newgraphenvironment.github.io/link/reference/lnk_aggregate.md)
  : Compute upstream habitat per crossing
