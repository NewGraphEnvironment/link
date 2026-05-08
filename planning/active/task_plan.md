# Task: lnk_pipeline_crossings — build crossings + barriers_* from primitives (#138)

Replace fresh::extdata/crossings.csv + bcfp tunnel barriers_* dependency with a primitives-build from public sources (BCDC PSCIS, CABD public API, bchamp gpkg, override CSVs). All loading is #137 territory; this issue ships the consume-side function + reusable utilities.

## Phase 0: `lnk_inputs_verify()` (exported, generic)

- [x] `R/lnk_inputs_verify.R`. `lnk_inputs_verify(conn, required)` where `required` is character vector of `<schema>.<table>`. Fail-loud listing missing. Single-roundtrip via `unnest($1::text[], $2::text[])` LEFT JOIN information_schema.tables.
- [x] Roxygen + runnable `@examples`.
- [x] Mocked unit test (9 expectations — happy path, missing tables, malformed strings, arg validation).

## Phase 1: `lnk_points_snap()` (exported, generic)

- [x] `R/lnk_points_snap.R`. Bulk lateral-KNN snap (matches bcfp's `load_dams.sql` pattern). One round-trip; scales province-wide.
- [x] Defaults `snap_tolerance = 100`, `exclude_edge_types = 1425L` (subsurface). Callers can override or pull from their config.
- [x] Roxygen + `@examples`.
- [x] Mocked unit tests (17 expectations across 5 tests — default args, vector exclude, opt-out, blue_line_key/stream_order constraints, validation).
- [ ] Manual smoke against ADMS PSCIS (deferred to Phase 2 integration, when we have the snapshot loaded).

## Phase 2: Source-precedence union (LEAN columns, not full bcfp shape)

- [x] `.lnk_crossings_union(conn, schema, aoi)` — port the source-precedence STRUCTURE from `bcfishpass/model/01_access/sql/load_crossings.sql` (PSCIS > CABD > modelled), but only emit the columns `lnk_barriers_emit()` needs:
  - `aggregated_crossings_id` (PK)
  - `crossing_source` ('PSCIS' | 'CABD' | 'MODELLED_CROSSINGS' | 'USER_MISC')
  - `crossing_feature_type` (for `barrier_type`)
  - `barrier_status` ('PASSABLE' | 'BARRIER' | 'POTENTIAL' | ...)
  - `pscis_status` (for remediations filter)
  - `dam_name` (NULL for non-CABD rows; populated for CABD)
  - `linear_feature_id`, `blue_line_key`, `watershed_key`, `downstream_route_measure`
  - `wscode_ltree`, `localcode_ltree`
  - `watershed_group_code`
  - `geom`
- [ ] **SKIP**: road tenure / FTEN / OGC / rail / UTM / structured_name / pscis_assessment_comment / etc. — bcfp's full crossings shape is for many downstream consumers; we only feed barriers_*.
- [ ] ID-space arithmetic per bcfp (PSCIS direct, CABD +1e9, modelled +1.5e9, user_misc +1.2e9).
- [ ] AOI filter (`watershed_group_code = aoi`).
- [ ] Row-count validation: PSCIS_rows + CABD_rows + modelled_rows >= union_rows (precedence dedup reduces).

## Phase 3: Apply user overrides

- [x] `.lnk_crossings_apply_overrides(conn, schema)` — joins `<schema>.pscis_fixes` + `<schema>.crossing_fixes` (already loaded by `lnk_pipeline_load`) into `<schema>.crossings`. Updates `barrier_status`.
- [x] Modelled-row JOIN handles +1e9 ID offset: `c.aggregated_crossings_id = (cf.aggregated_crossings_id::bigint + 1000000000)::text`.
- [x] Mirrors bcfp: `barrier_status = 'PASSABLE' WHEN structure IN ('NONE', 'OBS')` for modelled fixes.
- [x] No-op when fix tables absent (info_schema check up-front).
- [x] 13 mocked test expectations.

## Phase 4: `lnk_barriers_emit()` (exported)

- [x] `R/lnk_barriers_emit.R`. Single SQL transaction emits 5 tables: `crossings_lookup` + 4 `barriers_*`. Filters mirror bcfp's `barriers_anthropogenic.sql` / `barriers_pscis.sql` / `barriers_dams.sql` / `remediations_barriers.sql` (`barrier_status IN ('BARRIER', 'POTENTIAL')` + `blue_line_key = watershed_key` side-channel filter; remediations is anth UNION REMEDIATED-PASSABLE).
- [x] Output column shapes match bcfp barriers_* schemas — `aggregated_crossings_id` + network position + `geom`.
- [x] 22 mocked unit test expectations — verifies all 5 table operations, anthropogenic semantics, PSCIS/CABD branches, remediations UNION, validation.

## Phase 5: `lnk_pipeline_crossings()` umbrella + composition

- [x] `R/lnk_pipeline_crossings.R` (exported). Composes the five steps in order: `lnk_inputs_verify` → `lnk_points_snap` → `.lnk_crossings_union` → `.lnk_crossings_apply_overrides` → `lnk_barriers_emit`.
- [x] `snap_tolerance` arg threaded through to `lnk_points_snap` (default 100 m).
- [x] Roxygen with runnable `@examples`.
- [x] 13 mocked test expectations covering composition order + arg threading.
- [x] Full suite: 902 PASS / 0 FAIL. Lints clean on all new R/ files.

## Phase 6: ADMS live smoke + parity verification (live DB)

- [ ] Run `lnk_pipeline_crossings()` on ADMS against the locally-loaded primitives (PSCIS + CABD + modelled — already loaded earlier today). Verify `<schema>.crossings_lookup` + 4 `barriers_*` tables produced.
- [ ] Wire `<schema>.barriers_*` into `lnk_pipeline_access(barrier_sources = list(...))` and diff `mapping_code_<sp>` vs bcfp tunnel reference. ±5 % per species acceptable.
- [ ] Stamp `data-raw/logs/<TS>_link138_pscis_primitives_ADMS.txt`.

## Phase 7: NEWS + DESCRIPTION + open PR

- [ ] DESCRIPTION 0.31.1 → 0.32.0 (minor — 4 new exports: `lnk_inputs_verify`, `lnk_points_snap`, `lnk_barriers_emit`, `lnk_pipeline_crossings`).
- [ ] NEWS.md 0.32.0 entry.
- [ ] `/code-check` clean.
- [ ] `devtools::test()` + `lintr::lint_package()` + `devtools::check()` clean.
- [ ] Commit, push, open PR closing #138 with SRED tag.
- [ ] `/gh-pr-merge` → tag v0.32.0.
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
