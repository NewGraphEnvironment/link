# Findings — Export persisted barriers and input snapshots per group, so a one-group run reads downstream (#465)

## Issue context

**If we do it:** a one-group model run on any machine can read the persisted barriers of the groups downstream of it from the export, and so classify access as the full provincial run does, without the province being modelled there. **If we never do:** a one-group run on a machine that holds only some groups either refuses (once #464 lands) or, today, classifies access as though nothing downstream blocks.

### Problem

`lnk_pipeline_run()` classifies access from the already-persisted barriers of the groups downstream of the one it models. A machine built for a few groups has none of those. `data-raw/habitat_publish.R` (`lnk_scenario_export()`) already exports persisted runs per config and per group to `s3://fresh-bc/habitat/fwa/v1` with a manifest, but not the barriers a downstream run would read, nor the input snapshots they came from.

The barriers change whenever the provincial run's inputs or config do: CABD dams (read live from the CABD API), PSCIS, modelled crossings and observations, and link's config and overrides. A one-group run that loads today's CABD while reading downstream barriers from an older run can disagree about a dam added or reclassified in between.

### Proposed

1. Add the persisted barriers (`fresh.barriers` and link's persisted CABD barriers) to the export, one file per group per config, in the manifest.
2. Record in the manifest the run they came from: link's commit, the config hash, and each input's snapshot (date and checksum); export those input snapshots for the groups too.
3. Republish with every provincial run, not on a clock.
4. A helper that, given a target group, lists the groups on its downstream path (the outlets #464 reads) and the export files to fetch for them.

Relates to #464

## Exploration (2026-11-11, plan mode)

- The access walk reads two province-wide persist tables from other groups: `<schema>.barriers` (through `lnk_barriers_views()`) and `<schema>.barrier_overrides` (anti-joined in `barriers_<sp>_access`, `R/lnk_barriers_views.R:162`). CABD dams are `barrier_source = 'CABD'` rows of `barriers`; there is no separate CABD barriers table. The issue names only `barriers`.
- `data-raw/recompute_deps.R` (#374) documents that the outlet closure (`frs_wsg_drainage()`) misses readers in 150 of 241 groups; the line rule is complete by construction and is what the recompute scheduler uses. It reads FWA only, province-wide (~80 s).
- The export already ships each build's `log` (link_sha, config_hash) and `log_input` (row counts, `source_at`, artifact version / ETag) under `provenance/`. Inputs: `.lnk_input_primitives()` (`R/lnk_log.R:230`); CABD and PSCIS are `api` kind (no version handle), modelled crossings and observations are versioned bchamp objects.
- `lnk_catalog()`'s `.lnk_part_parse()` refuses any part key not under `segment/`, so barrier parts cannot go in the manifest's `parts` without breaking catalog and `lnk_db_load()`: a separate top-level array.
- `habitat_publish.R` PUBLISH deletes stale keys only under `segment/`.
- #464 (open) proposes checking that the downstream groups have streams loaded; a one-group machine that loads only exported barriers would then need the dependency groups' FWA too, hence the FWA object URL in the helper's listing.
- `data-raw/pretest_inputs.csv` refuses an unmapped changed file; new `R/` files need rows.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `ORDER BY 1 COLLATE "C"` failed: collations not supported by type integer | Sort in R with `method = "radix"` |
| `linear_feature_id` came back as 3.47e-315: `duckdb_register()` reads `integer64` bits as a double | Write `bigint` as its text form; loader casts back |
