# Code-check round 3: #286 staged diff

## Clean

No issues found.

## Mechanism behind the round-2 bug

**Metadata doubling as a selector.** The provenance `source:` field reads as a
description, but `data-raw/sync_bcfishpass_csvs.R` (`is_bcfp_sourced()`, line 121)
uses it as an enrolment key: any entry whose `source` equals the bcfishpass URL joins
the weekly auto-merging sync. So the set of files the sync manages is never declared
anywhere. It is whatever happens to match a string. More generally: several
hand-kept lists (sync targets, input primitives, bundle files, dictionaries, persist
columns) each have to agree with the bundle, and nothing checks that they do. The
cw-only half of the question has the same shape: link code that assumes the size
model without asking the method table.

## Every place that mechanism reaches, and what I found

**Provenance used as a selector**
- `sync_bcfishpass_csvs.R`: the only reader that keys on `source`; it never reads
  `upstream_sha` or `derived_from`. The new entry's `source` does not match, and
  `test-lnk_config.R` pins that.
- `lnk_config_verify.R` reads `checksum` / `shape_checksum` only. All 5 bundles
  verify clean, `default_tuned` included through inheritance.
- `.lnk_config_hash` builds paths from `cfg$files` plus provenance keys. The new
  file is hashed by relative name, and for `default_tuned` as
  `extends:default/...`.
- `regen_provenance.R` uses a fixed one-off list and does not touch this file.

**Lists of bundle files**
- `lnk_load_overrides` loads every `cfg$files` entry: 16 for bcfishpass, 18 for
  default, the new file included (smoke-tested by `audit_configs.R`).
- Nothing reads `loaded$parameters_habitat_method`, so read.csv's default `"NA"` → NA
  there is inert. Classify reads the path with `na.strings = character(0)`.
- `audit_configs.R` ran to completion with "No findings", exit 0, and left the tree
  unchanged.
- `default_tuned` resolves its method table to `configs/default/` (checked).
- `habitat_variants_build.R` variant bundles `extends: default`, so they inherit
  the table.

**Lists of input primitives**
- `.lnk_input_primitives` now holds 12 tables.
- `.lnk_vintage_primitives` filters on `source` not starting with `fwapg/`, so it
  still returns 4 tables.
- `.lnk_log_inputs` iterates the list; no row count is hardcoded in R/, tests,
  `study_area_verify.sql` or shell scripts.
- fwapg `load.sh:154` loads `fwa_stream_networks_discharge` alongside channel width,
  so cypher DBs built the standard way carry it.

**Persist shape**
- `lnk_pipeline_persist` inserts named `cols_streams` columns, never `SELECT *`.
- fresh's break step carries columns dynamically (`frs_break.R:668-677`), so
  `mad_m3s` survives breaking on the working table.
- Working schemas built before this branch and reused by
  `habitat_variants_build.R` lack `mad_m3s`. That is harmless while every group is
  `cw`: fresh only checks for the column when a group resolves to `mad`.

**The bundle copy against upstream**
- The bundle CSV is byte-identical to `smnorris/bcfishpass@1fae4ea`
  `parameters/example_newgraph/parameters_habitat_method.csv` (sha256 `9802bb71…`,
  matching the declared checksum).

**cw-only behaviour applied regardless of the group's model**
- `frs_order_child` bypass: now skipped for a `mad` aoi. The skip decision is
  consistent with fresh:
  - Both use exact, case-sensitive matching.
  - Both treat an unlisted group as `cw`.
  - The working streams table is filtered to `watershed_group_code = aoi`, so
    fresh's per-row model and link's per-aoi model cannot disagree.
- Connectivity: `.frs_run_connectivity` and the cluster helpers contain no
  width or model reference. `.frs_connected_waterbody` adds a width test only when
  `channel_width_min > 0`, and every rules.yaml has `0.0`, so it is inert as the
  RUNBOOK says.
- `lnk_rules_build` river-polygon `channel_width [0, 9999]`: rule-level, and
  fresh ignores it under `mad` (documented).
- Break sources in every bundle are gradient, observation, crossing and habitat
  endpoints. None is width-based.
- `lnk_habitat_validate`: cw-only, accepted, not re-flagged.
- `lnk_pipeline_pscis_build` `downstream_channel_width` is PSCIS field data used
  to match crossings, not the size model.

**Malformed-input paths**
These each fail loud, through fresh's `.frs_habitat_models()` validation or the
`method_csv not found` stop, before the bypass decision runs:
- missing `model` column
- blank model
- whitespace in a value
- duplicate group rows
- BOM header
- `method_csv = NA`
- old fresh with no copy of the table

## Informational, not a link defect

fresh's own shipped `parameters_habitat_method.csv`, which custom bundles fall back
to, lists 187 groups. It lacks `PINE`, which upstream example_newgraph now carries.
Because an unlisted group classifies as `cw`, the fallback behaves identically. The
copy is quoted, so it is not byte-comparable to the bundles. It is worth a fresh-side
refresh some day, and nothing in link depends on it.
