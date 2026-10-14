# Findings — lnk_scenario_export() (#308)

## Issue context

**If done:** habitat flags for every link config (`default`, `default_tuned`, `bcfishpass`) and build are published as keyed tables that anyone can load into fwapg and join in SQL, with a manifest recording which build produced them. **If never:** every consumer hand-joins persist tables, re-solves the `(id_segment, watershed_group_code)` fan-out (#203) and the `mad_m3s`-not-persisted gap, and cannot tell which build a habitat number came from.

**Revised 2026-10-12.** The first version of this issue proposed one wide GeoPackage stream layer per WSG. It now follows the pattern settled in NewGraphEnvironment/wet#7 for per-segment discharge: Parquet on S3, a manifest, and a load into fwapg. No STAC: these are attribute rows keyed to FWA positions, not spatial assets with a footprint of their own, and the geometry is already in fwapg. The GeoPackage stays as an optional desktop export built from the same tables.

## Dataset and layout

Dataset ID `habitat/fwa/v1/segment`, named the way wet#7 names its datasets (`<variable>/<network>/<version>/<unit>`):

```
s3://fresh-bc/habitat/fwa/v1/
  manifest.json
  segment/config=<config>/species=<sp>/part-<code>.parquet
```

- **Hive keys:** `config` (the link config name), `species`. The build is not a key: data are overwritten in place within a schema version, as in wet#7, and the manifest names the build.
- **`part-<code>`:** one FWA top-level drainage, as in wet#7, labelled in the manifest. Rows sorted by `watershed_group_code`, so a one-group read prunes on row-group statistics.
- **Long form, no geometry.** One row per segment × config × species; flags are columns.

## Key: FWA position, not `linear_feature_id` and not `id_segment`

link's segments are FWA segments split at break points, and the break points differ by config, so `linear_feature_id` (wet's key) is not unique and `id_segment` is numbered per group (#203). The key is `(blue_line_key, downstream_route_measure, upstream_route_measure)`. A consumer cuts a segment's line from the FWA blue line at those measures, so no link geometry is published.

## Columns

`blue_line_key, downstream_route_measure, upstream_route_measure, linear_feature_id, watershed_group_code, stream_order, edge_type, length_metre, gradient, channel_width, channel_width_source, mad_m3s, mad_m3s_source`, then per stage `accessible, spawning, rearing, lake_rearing, wetland_rearing`, and per stage the ratios `<stage>_ratio_cw`, `<stage>_ratio_mad` (size ÷ minimum) and `<stage>_ratio_gradient` (gradient ÷ maximum). A species with no habitat in a group yields FALSE, never a missing column. Column types and meanings registered and conformed before writing, as wet#7 does with crate.

## Manifest

Per part: dataset, config, species, code, drainage, href, rows, bytes, md5. Per config: link's log row as read (`config_name`, `config_hash`, `run_uid`, `link_sha`, `fwapg_sha`, bundle, model, fill), and the discharge input (below). No `s3:ListBucket`: readers go through the manifest.

## Discharge comes from wet

`mad_m3s` today comes through `.lnk_discharge_sql()` per each scenario's applied fill. Once NewGraphEnvironment/wet#7 loads `discharge.fwa_v1_segment_monthly` into fwapg, link reads it from there (`month = 0`, `pick`), and the manifest records the discharge dataset ID and the md5s of the wet parts it used. Habitat → discharge provenance is then one chain of manifests.

## Pieces

- **`lnk_scenario_export()`:** builds the tree and manifest from the persist tables for a set of configs and WSGs. First asserts that the scenario schemas compared within one config share segmentation, using the variants harness's `streams` digest, and refuses on a mismatch (the #226 vignette trap). Across configs the segmentation may differ, which the position key handles.
- **`lnk_catalog()`:** reads `manifest.json`, one row per part, with build provenance.
- **`lnk_db_load()`:** downloads parts, checks each md5 against the manifest, writes `habitat.fwa_v1_segment` in fwapg.
- **Desktop export (optional):** the same rows joined to FWA geometry, written to a GeoPackage per WSG, with a `scenarios` layer from the manifest.

## Consumers

- **NewGraphEnvironment/floodplains#123:** whole-network floodplains are keyed by `blue_line_key` and the FWA version and carry no link output. Habitat is joined afterwards by FWA position, for whichever config the consumer picks. floodplains records the `run_uid` and part md5s it joined against, so a new build never blocks a join and "is this the build we joined?" is a lookup.
- fresh, through the fwapg table.

## Tests

Segmentation-mismatch refusal; full-key joins (no fan-out across groups); a species with no habitat yields FALSE; manifest md5 round trip; `lnk_db_load()` refuses a part whose md5 does not match.

## Staged private first (operator, 2026-10-14)

- **No public read and no versioning on `habitat/` yet.** The tunings are still moving the outputs (#284, #300, #307, #310, #319), and how habitat ties to the floodplain items (NewGraphEnvironment/floodplains#123) is still being explored. The tree goes to `s3://fresh-bc/habitat/fwa/v1/` under the bucket's private default.
  - So `lnk_catalog()` and `lnk_db_load()` must read through credentials (an `s3://` path), not only anonymously over `https://` as wet does.
- **Opening it later is small:** one entry in fresh-bc's `public_read_prefixes` and a tofu apply, as `discharge/` was opened (NewGraphEnvironment/rtj#390). Have NewGraphEnvironment/rtj#168's budget and anomaly alerts in place first. Anonymous downloads are billed to us at about $0.09/GB once the account's 100 GB/month free tier is used, and it was used in May 2026 (rtj#168).
- **History:** data are overwritten in place, and fresh-bc versioning is `Suspended`, so a superseded build cannot be fetched again. That is acceptable while exploring. Versioning is bucket-wide (NewGraphEnvironment/rtj#263). When it is on and `habitat/` should keep history:
  - the manifest records each part's `versionId`;
  - `habitat/` gets a keep-the-last-N rule.

  Decide this before the first build that a published floodplain item pins.

## Provenance published beside the data

The run's evidence is written once and never overwritten:

```
habitat/fwa/v1/provenance/run_uid=<run_uid>/
  log.parquet
  log_input.parquet                           (with artifact_* from #265)
  log_parameters_habitat_thresholds.parquet
  source_artifact.parquet                     (provenance.source_artifact rows for the hosts the run used)
habitat/fwa/v1/config/<config_hash>/          (the bundle files config_hash was computed over)
```

The manifest's per-config entry names its `run_uid`s and `config_hash`. A consumer, such as the provenance table in NewGraphEnvironment/floodplains#52, records those plus the part md5s, and the `versionId`s once versioning exists. Everything else resolves from the bucket.

## Webmap (later, not the first cut)

PMTiles built from the published rows and FWA lines cut at the measures (tippecanoe), regenerated per build at a fixed key. Publication is NewGraphEnvironment/rtj#182; a browser reader also needs NewGraphEnvironment/rtj#392's CORS fix. Open question: one tileset per config, or one per config × species.


Relates to #305, #307, #203, #226, NewGraphEnvironment/wet#7, NewGraphEnvironment/floodplains#123.



## Exploration (2026-10-14, plan mode)

- **wet#7 pattern** (PRs #62/#63; `research/discharge_publish.md` in wet):
  - manifest writer `wet_manifest_write()` in `R/wet_catalog.R:163`;
  - catalog `wet_catalog()` at `:55`, key parser `wet_part_parse()` at `:132`;
  - loader `wet_db_load()` in `R/wet_db_load.R:46`, one transaction, `dbAppendTable` in 1e6 chunks read by duckdb;
  - md5 via `tools::md5sum()`; upload by `aws s3api put-object --content-md5`, manifest last with no-cache;
  - fixtures written by duckdb `COPY ... (FORMAT parquet)`.
- **Persist shape:**
  - habitat is one table per species, `streams_habitat_<sp>`, keyed `(id_segment, watershed_group_code)`.
  - A species not active in a WSG has **no rows**. An active species with no habitat has dense FALSE rows.
  - `streams` has no `mad_m3s`.
- **Log state in local fwapg** (2026-10-14):
  - `fresh_default.log` has 5 rows (DUNC, KOTL, LARL, PINE, SLOC), all with `run_uid` NULL, for 56 groups in `streams`.
  - `fresh.log` has 65 rows across 39 groups, 42 of them with a `run_uid`.
  - There is no `default_tuned` persist schema outside `score300_default_tuned`.
  - There is no `discharge` schema (wet's table is not loaded locally).
- **Neither cw/mad model is logged per WSG.** `discharge_fill` is logged (NULL before #305, which reads as raw). The ratios carry both cw and mad, so no model is needed.
- **The segmentation digest** has an R helper: `.lnk_hvb_check_segmentation()` at `R/lnk_habitat_validate_band.R:251`.
- **Threshold columns:** `log_parameters_habitat_thresholds` is keyed `(config_hash, species_code)` and every column is text.
- **crate:** `crt_schema_read(yaml_path)` + `crt_schema_validate(df, schema)` accept a local YAML. `crt_schema_conform` needs a registry entry.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| duckdb `read_parquet()` on a hive path adds `config`/`species` columns | Read with `hive_partitioning = false` when the hive values come from the manifest (as wet does) |
| Copying a schema's log into another schema reuses `run_id`s, so both write `provenance/run_id=<id>/` | Correct refusal by the write-once guard; fixture uses distinct ids |
| Pilot BUILD: `names attribute [39] must be the same length as the vector [0]` | `fresh.log` predates `discharge_fill` (#305); `.lnk_export_runs()` now adds any `cols_log` column a log lacks as NA |
| `sprintf("%d", <double>)` in verify.R's summary | counts from `sum()` of numerics are double; formatted with `%s` |

## Logged thresholds coverage (2026-10-14)

| schema | config_hash | groups | thresholds rows | parameters_fresh rows |
|---|---|---|---|---|
| fresh_default | 3cfde7bf… (KOTL, SLOC) | 2 | 0 | 13 |
| fresh_default | 44e452e9… (LARL) | 1 | 0 | 13 |
| fresh_default | 7e9dffa4… (DUNC) | 1 | 11 | 13 |
| fresh_default | bf4fccd1… (PINE) | 1 | 0 | 13 |
| fresh | 19e3a056… (39 groups) | 39 | table absent | — |

Today's `default` bundle hashes to `7e9dffa4…`, which is DUNC's, so DUNC's bundle files can be published under `config/<hash>/`; no other logged build's can.

## Pilot (2026-10-14, local fwapg)

- BUILD `default:fresh_default,bcfishpass:fresh`, every finished build: 5 + 39 groups, 22 parts, 9,876,720 rows, 219 MB, 102 provenance/bundle files, about 1 min. All verify against the manifest.
  - Runs: default 1/5 with logged thresholds (DUNC) and 1/5 with a resolvable model (DUNC: cw); bcfishpass 0/39 thresholds, 0/39 model (bundle hash moved since the build), 39/39 with a recompute after the build, 38/39 with a `run_uid`.
- Load + compare (`data-raw/logs/habitat_export_308/verify.R`) against `lnk_rollup_wsg()` per config × species × group (140 rows): spawning km identical everywhere, rearing flag km within 0.01 km (the rollup rounds rearing and connection separately, then adds).
- **G1 measured on real data:** km with `has_barriers_dnstr = FALSE` equals the rollup's `accessible_km` (access 1/2, post-recompute), while the classification-time `accessible` flag runs higher where a barrier in another group arrived later. SETN CH: 1,587.6 km flagged accessible vs 1,497.2 km with no barrier downstream (511 segments). So shipping both columns matters.
- `lnk_rollup_wsg()` is slow on the big `fresh` schema (minutes per group × species), which made the verify run about 75 min; the export itself is not.

## Mutation table (2026-10-14, at `af9225f7`, scratch copy)

Each guard's defect restored in a copy; the count is failing + erroring tests in that guard's file.

| guard restored to the bug | red tests |
|---|---|
| habitat join on `id_segment` only (fan-out, #203) | 12 |
| a group with no log row accepted | 1 |
| a logged species with no habitat rows read as FALSE | 4 |
| write-once accepts any content | 2 |
| part md5 check skipped in `lnk_db_load()` | 3 |
| no staging (parts written in place) | 11 |
| one-element manifest arrays unboxed | 1 |
| carried-forward part's md5 unchecked | 1 |

## Reproducibility (2026-10-14)

The pilot BUILD rerun at `b59f61a5` (18:35Z, per-build provenance layout) into a fresh root gives 22 parts **byte-identical** to the first pilot build (16:30Z, before the code-check rounds). Same database state, duckdb 1.5.2, one writer thread. The provenance tree grew from 102 to 156 files because it is now one directory per build plus one per config hash.
