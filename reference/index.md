# Package index

## All functions

- [`lnk_aggregate()`](https://newgraphenvironment.github.io/link/reference/lnk_aggregate.md)
  : Compute upstream habitat per crossing

- [`lnk_barrier_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_barrier_overrides.md)
  : Build barrier override list from evidence sources

- [`lnk_barriers_emit()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_emit.md)
  : Emit slim crossings_lookup + per-source barriers\_\* tables

- [`lnk_barriers_unify()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_unify.md)
  :

  Unify per-WSG barrier sources into the working-schema
  `<schema>.barriers`

- [`lnk_barriers_views()`](https://newgraphenvironment.github.io/link/reference/lnk_barriers_views.md)
  :

  Create working-schema views over `<persist_schema>.barriers`

- [`lnk_baseline_append()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_append.md)
  : Append a row to the run-tracking baseline ledger

- [`lnk_baseline_current()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_current.md)
  : Is this host's baseline already current at the supplied upstream?

- [`lnk_baseline_read()`](https://newgraphenvironment.github.io/link/reference/lnk_baseline_read.md)
  : Read the run-tracking baseline ledger

- [`lnk_bucket_get()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_get.md)
  : Download a single artifact from a public S3 bucket prefix

- [`lnk_bucket_log()`](https://newgraphenvironment.github.io/link/reference/lnk_bucket_log.md)
  :

  Read the build-identifier `log.json` from a bucket prefix

- [`lnk_compare_wsg()`](https://newgraphenvironment.github.io/link/reference/lnk_compare_wsg.md)
  : Compare one watershed group against a reference dataset

- [`lnk_config()`](https://newgraphenvironment.github.io/link/reference/lnk_config.md)
  : Load a Pipeline Config Bundle (Manifest)

- [`lnk_config_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_config_verify.md)
  : Verify Config Bundle File Checksums and Shape

- [`lnk_db_conn()`](https://newgraphenvironment.github.io/link/reference/lnk_db_conn.md)
  : Connect to FWA PostgreSQL database

- [`lnk_inputs_verify()`](https://newgraphenvironment.github.io/link/reference/lnk_inputs_verify.md)
  : Verify that required Postgres tables exist in a connection

- [`lnk_load()`](https://newgraphenvironment.github.io/link/reference/lnk_load.md)
  : Load override CSVs into a database table

- [`lnk_load_overrides()`](https://newgraphenvironment.github.io/link/reference/lnk_load_overrides.md)
  : Materialize the Tabular Data Files Declared in a Config Bundle

- [`lnk_match()`](https://newgraphenvironment.github.io/link/reference/lnk_match.md)
  : Match crossing records across data systems

- [`lnk_override()`](https://newgraphenvironment.github.io/link/reference/lnk_override.md)
  : Validate and apply overrides to a table

- [`lnk_parity_annotate()`](https://newgraphenvironment.github.io/link/reference/lnk_parity_annotate.md)
  : Annotate a parity rollup against the bcfp divergence taxonomy

- [`lnk_persist_init()`](https://newgraphenvironment.github.io/link/reference/lnk_persist_init.md)
  : Initialize persistent province-wide habitat tables

- [`lnk_pipeline_access()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_access.md)
  : Build per-segment access codes + downstream-feature arrays

- [`lnk_pipeline_break()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_break.md)
  : Segment the Stream Network at Configured Break Positions

- [`lnk_pipeline_classify()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_classify.md)
  : Classify Stream Segments into Habitat per Species

- [`lnk_pipeline_connect()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_connect.md)
  : Apply Rearing-Spawning and Waterbody Connectivity

- [`lnk_pipeline_crossings()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_crossings.md)
  : Build crossings + barriers\_\* tables from primitives

- [`lnk_pipeline_load()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_load.md)
  : Load Crossings and Apply Crossing-Level Overrides

- [`lnk_pipeline_mapping_code()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_mapping_code.md)
  : Build per-segment per-species mapping_code strings (bcfp parity)

- [`lnk_pipeline_persist()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_persist.md)
  : Persist per-WSG output into the province-wide habitat tables

- [`lnk_pipeline_prepare()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_prepare.md)
  : Prepare the Network and Barrier Inputs for a Pipeline Run

- [`lnk_pipeline_setup()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_setup.md)
  : Set Up the Working Schema for a Pipeline Run

- [`lnk_pipeline_species()`](https://newgraphenvironment.github.io/link/reference/lnk_pipeline_species.md)
  : Resolve the Species Set for an AOI

- [`lnk_points_snap()`](https://newgraphenvironment.github.io/link/reference/lnk_points_snap.md)
  : Snap a Postgres table of points to the FWA stream network

- [`lnk_presence()`](https://newgraphenvironment.github.io/link/reference/lnk_presence.md)
  : Per-AOI species presence with bcfp species-group expansion

- [`lnk_rules_build()`](https://newgraphenvironment.github.io/link/reference/lnk_rules_build.md)
  : Build habitat eligibility rules YAML from dimensions CSV

- [`lnk_score()`](https://newgraphenvironment.github.io/link/reference/lnk_score.md)
  : Score crossings

- [`lnk_source()`](https://newgraphenvironment.github.io/link/reference/lnk_source.md)
  : Produce a fresh-compatible break source list

- [`lnk_stamp()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp.md)
  : Capture a Pipeline Run Stamp

- [`lnk_stamp_finish()`](https://newgraphenvironment.github.io/link/reference/lnk_stamp_finish.md)
  : Finalize an in-progress run stamp

- [`lnk_thresholds()`](https://newgraphenvironment.github.io/link/reference/lnk_thresholds.md)
  : Load configurable severity scoring thresholds
