# Package index

## Configs

Load a pipeline config bundle (rules, parameters, overrides)

- [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  : Load a Pipeline Config Bundle
- [`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md)
  : Verify Config Bundle File Checksums and Shape

## Run stamps

Capture provenance + software versions + DB snapshots for run-to-run
drift attribution

- [`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
  : Capture a Pipeline Run Stamp
- [`lnk_stamp_finish()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp_finish.md)
  : Finalize an in-progress run stamp

## Pipeline phases

Composable per-AOI habitat classification building blocks. Call in order
for a full run.

- [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  : Segment the Stream Network at Configured Break Positions
- [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
  : Classify Stream Segments into Habitat per Species
- [`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
  : Apply Rearing-Spawning and Waterbody Connectivity
- [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md)
  : Load Crossings and Apply Crossing-Level Overrides
- [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  : Prepare the Network and Barrier Inputs for a Pipeline Run
- [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  : Set Up the Working Schema for a Pipeline Run
- [`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)
  : Resolve the Species Set for an AOI

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
