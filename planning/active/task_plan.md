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

## Phase 2: Source-precedence union

- [ ] `.lnk_crossings_union(conn, schema, aoi)` — port `bcfishpass/model/01_access/sql/load_crossings.sql`. PSCIS > PSCIS-on-modelled > CABD > modelled. `crossing_source` column.
- [ ] ID-space arithmetic per bcfp (PSCIS direct, CABD +1e9, modelled +1.5e9, user_misc +1.2e9).
- [ ] AOI filter.
- [ ] Row-count validation.

## Phase 3: Apply user overrides

- [ ] `.lnk_crossings_apply_overrides(conn, schema)` — joins `<schema>.pscis_fixes` + `<schema>.crossing_fixes` (already loaded by `lnk_pipeline_load`) into `<schema>.crossings`. Updates `barrier_status`.
- [ ] Same row-level effect as existing override path.

## Phase 4: `lnk_barriers_emit()` (exported)

- [ ] `R/lnk_barriers_emit.R`. Emits `<schema>.crossings_lookup` + 4 barriers_* via filtered SELECTs.
- [ ] Output column shapes match `lnk_pipeline_access(barrier_sources = list(...))` consumer.
- [ ] Roxygen + mocked unit test.

## Phase 5: ADMS Surface 2 parity

- [ ] Run `lnk_pipeline_crossings()` on ADMS. Wire output into `lnk_pipeline_access`.
- [ ] Compare `mapping_code_<sp>` vs bcfp tunnel reference. ±5 % per species acceptable.
- [ ] Stamp `data-raw/logs/<TS>_link138_pscis_primitives_ADMS.txt`.

## Phase 6: NEWS + DESCRIPTION + open PR

- [ ] DESCRIPTION 0.31.0 → 0.32.0.
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
