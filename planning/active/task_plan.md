# Task: lnk_scenario_export(): publish habitat per config as Parquet + manifest + fwapg load (wet#7 pattern) (#308)

**If done:** habitat flags for every link config (`default`, `default_tuned`, `bcfishpass`) and build are published as keyed tables that anyone can load into fwapg and join in SQL, with a manifest recording which build produced them. **If never:** every consumer hand-joins persist tables, re-solves the `(id_segment, watershed_group_code)` fan-out (#203) and the `mad_m3s`-not-persisted gap, and cannot tell which build a habitat number came from.

## Decisions taken (2026-10-14)

- **Discharge:** export the discharge the run actually used, `.lnk_discharge_sql(wsg, fill = isTRUE(log.discharge_fill))`, so `*_ratio_mad` agrees with the flags. The manifest records the table and its `provenance.source_artifact` identity. Moving the pipeline onto wet's `discharge.fwa_v1_segment_monthly` becomes a follow-up issue, because it moves outputs.
- **Scope:** the functions, the provenance tree, and a BUILD/PUBLISH script. Running PUBLISH needs your separate go-ahead.
  - **Deferred to filed follow-ups:** desktop GeoPackage, crate registration, webmap.
  - **Column spec location:** the column spec stays in link for now, in crate's YAML shape (`canonical: cols:`), so moving it into crate later is a copy. It is checked with `crate::crt_schema_read()` + `crt_schema_validate()`.
- **Provenance gate (recommended; open for your call at approval):**
  - **Refused:** a group with no log row for the config. Without that row there is no `config_hash`, and so no logged thresholds to compute ratios from. That is identity, not provenance maturity.
  - **Allowed:** a NULL `run_uid`. Its provenance is keyed `run_id=<run_id>` instead of `run_uid=<uid>`, and the manifest says so.
  - **Bundle files:** they are written only when the current bundle's hash equals the logged `config_hash`. Otherwise the manifest records `bundle: null` with the reason (drift). This is recorded, not refused.
  - **Effect:** the machinery is testable today on KOTL/LARL/SLOC/DUNC/PINE (`fresh_default`) and the 39 logged `fresh` groups. Tightening to "run_uid required" later is a one-line gate at PUBLISH.

## Phase 1: Column contract and the per-part row query

- [x] `inst/extdata/schemas/habitat_fwa_v1_segment.yaml` in crate's shape, with columns as the issue lists them. Ratios are defined as follows:
  - `spawning_ratio_{cw,mad,gradient}` and `rearing_ratio_{cw,mad,gradient}`: size ÷ the stage's `*_min`, and gradient ÷ `*_gradient_max`.
  - `accessible_ratio_gradient`: gradient ÷ `access_gradient_max`.
  - No ratios for lake or wetland rearing (area-only).
  - A ratio is NULL when its threshold is NA or 0.
- [x] `.lnk_export_rows(conn, schema, wsg, sp, log_row)` (new `R/lnk_scenario_export.R`). It runs one SQL query:
  - `streams` LEFT JOIN `streams_habitat_<sp>` on the full key `(id_segment, watershed_group_code)`; an absent species gives FALSE.
  - LEFT JOIN `.lnk_discharge_sql()` on `linear_feature_id`.
  - Thresholds from `<schema>.log_parameters_habitat_thresholds` and `log_parameters_fresh` at the log row's `config_hash`, which are the values the run used, cast from text.
- [x] Tests (`skip_if_no_db()`, a throwaway fixture schema; pattern from `tests/testthat/setup.R`):
  - two groups sharing an `id_segment` do not fan out;
  - an absent species gives FALSE in every row;
  - the ratio arithmetic is correct, and a NULL threshold gives a NULL ratio;
  - the row count equals the `streams` count.

## Phase 2: `lnk_scenario_export()` + manifest

- [x] `lnk_scenario_export(conn, configs = c(default = "fresh_default"), root, wsgs = NULL, species = NULL)` (exported).
  - **Guards:**
    - each WSG's latest log row matches the config, or the export refuses;
    - several schemas for one config pass `.lnk_hvb_check_segmentation()` (`R/lnk_habitat_validate_band.R:251`);
    - the habitat key set equals the streams key set.
  - **Write:** each part `segment/config=<c>/species=<sp>/part-<code>.parquet`, where `code` is the first segment of `wscode_outlet` and `drainage` is the region, both from `inst/extdata/wsg_regions.csv`. Each part is written through duckdb (Suggests, `requireNamespace`-guarded): sorted by `watershed_group_code, blue_line_key, downstream_route_measure`, zstd, written to `.tmp` and then renamed.
  - **Provenance tree:** `provenance/run_uid=<uid>|run_id=<id>/{log,log_input,log_parameters_habitat_thresholds,source_artifact}.parquet`, plus `config/<config_hash>/` bundle files when the hash matches.
- [x] `.lnk_manifest_write()`, in wet's shape:
  - top level: `manifest_version`, `id = "habitat/fwa/v1"`, `built`, `provenance{link_version, link_sha}`, `datasets[{dataset, schema}]`;
  - `configs[{config, schema_persist, runs[log rows as read], config_hashes, discharge{table, fill, source_artifact}, bundle}]`;
  - `parts[{key, dataset, config, species, code, drainage, rows, bytes, md5}]`.

  Written with `jsonlite::write_json(auto_unbox, digits = NA, null/na = "null")` to a temp file and renamed into place. md5 via `tools::md5sum()`.
- [x] Tests:
  - an unlogged group is refused;
  - a segmentation mismatch is refused;
  - manifest md5s and row counts round-trip against the files;
  - a NULL `run_uid` is keyed by `run_id`.

## Phase 3: `lnk_catalog()` + `lnk_db_load()`

- [ ] `lnk_catalog(manifest)` (exported).
  - It accepts a local path, `https://` (httr, as `lnk_bucket_get()` does), or `s3://`, the latter through the credentialed `aws s3 cp` via `system2()` with its status checked, because the bucket is private.
  - It returns one row per part. `href` resolves relative to the manifest. The hive fields are parsed from the key, as in wet's `wet_part_parse()`.
  - It carries the `configs` provenance as an attribute.
- [ ] `lnk_db_load(conn, catalog, configs = NULL, cache_dir = tools::R_user_dir("link", "cache"))` (exported).
  - Fetch: each part is fetched to `<dest>.part`, its size and md5 checked against the manifest, then renamed. A cached part is reused while its md5 matches.
  - Load: in one transaction, create `habitat.fwa_v1_segment` (`config` and `species` prepended), refuse a column mismatch, `DELETE` the configs being loaded, `dbAppendTable` in chunks read by duckdb, and check row counts.
  - Then, on create: PK `(config, species, blue_line_key, downstream_route_measure)`, an index on `blue_line_key`, `ANALYZE`, and `COMMENT ON TABLE` naming the manifest and the build.
- [ ] Tests:
  - an md5 mismatch is refused and the earlier rows survive;
  - an `s3://` fetch calls `aws` (mocked);
  - export → catalog → load round-trips on the fixture;
  - a mid-load failure rolls back.

## Phase 4: BUILD/PUBLISH script + pilot build

- [ ] `data-raw/habitat_publish.R` in wet's two modes:
  - **BUILD:** runs `lnk_scenario_export()` to a local root, then verifies it.
  - **PUBLISH (`LNK_PUBLISH=1`):** refuses unless the local tree verifies. It then uploads each part with `aws s3api put-object --content-md5`, puts the manifest last with `no-cache`, and deletes keys the manifest no longer names. The target is `s3://fresh-bc/habitat/fwa/v1/` under the bucket's private default.
- [ ] Pilot BUILD (local only): `default` on its 5 logged groups and `bcfishpass` on a few logged ones, then `lnk_db_load()` into local fwapg. Two checks:
  - against a direct persist query, per-config km of spawning and rearing match;
  - no duplicate keys.

  Logs go to `data-raw/logs/habitat_export_308/`.

## Phase 5: Docs and follow-ups

- [ ] RUNBOOK section on the export, catalog and load; `NEWS.md`; `duckdb` in Suggests; runnable `@examples` built on a temp tree.
- [ ] File follow-ups:
  - pipeline discharge from wet;
  - desktop GeoPackage;
  - crate registration of the schema;
  - PUBLISH gate on `run_uid`, together with versioning/versionId (rtj#263);
  - webmap PMTiles.

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()`, `devtools::document()`, `devtools::check()`
- [ ] `/code-check branch` clean (three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

