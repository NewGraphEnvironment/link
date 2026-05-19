# Task: mapping_code build decoupled from tunnel — persist streams_access + lnk_pipeline_run phase + rename with_mapping_code → mapping_code (#187)

## Problem

`<schema>.streams_mapping_code` build is currently bundled inside `lnk_compare_wsg(with_mapping_code = TRUE)` which also runs `.lnk_compare_wsg_mapping_code_diff()` over the tunnel. Build is tunnel-independent; coupling is structural. Result: operators who want QGIS bcfp-shape symbology via `streams_<sp>_bcfp_vw` must keep tunnel up. Also `streams_mapping_code` lands in working schema (`working_<aoi>`), not persist — QGIS-needed location.

Design principle: expose `lnk_mapping_code()` as portable exported function with explicit `table_<role>` args; pipeline_run + compare_wsg both call it. Persist both `streams_access` (enables ad-hoc rebuild) and `streams_mapping_code` (QGIS consumer). Bundle a rename sweep (`with_mapping_code` → `mapping_code`, `<role>_species` → `species_<role>`) for v0.40.0 BC bump.

## Phase 1 — Schema additions to lnk_persist_init

- [ ] Define `cols_streams_access` named vector at top of `R/lnk_persist_init.R`. Mirror `bcfishpass.streams_access` columns (consult `R/lnk_pipeline_access.R` for the actual emitted shape).
- [ ] Define `cols_streams_mapping_code` named vector: `id_segment` (PK), `watershed_group_code`, one `mapping_code_<sp>` text per species in union of resident + anadromous defaults.
- [ ] Add CREATE TABLE IF NOT EXISTS blocks for both in `lnk_persist_init` function body.
- [ ] Add CREATE OR REPLACE VIEW for `streams_habitat_long_vw` (UNION ALL across per-species tables — generated dynamically from `species` arg).
- [ ] DDL drift validation: extend `.lnk_validate_persist_table` calls to the two new tables.
- [ ] Index on `watershed_group_code` for both new tables.
- [ ] `/code-check` clean.
- [ ] Commit: `lnk_persist_init: add streams_access + streams_mapping_code persist tables + long-form habitat view`.

## Phase 2 — lnk_pipeline_persist writes for new tables

- [ ] Add `streams_access` DELETE-WHERE-WSG + INSERT block in `lnk_pipeline_persist` (gated by presence of working `<schema>.streams_access`).
- [ ] Same pattern for `streams_mapping_code`.
- [ ] Column projection driven by `cols_streams_access` / `cols_streams_mapping_code`.
- [ ] `/code-check` clean.
- [ ] Commit: `lnk_pipeline_persist: write streams_access + streams_mapping_code per-WSG`.

## Phase 3 — New exported function `lnk_mapping_code()`

- [ ] Create `R/lnk_mapping_code.R`:
  ```r
  lnk_mapping_code(conn, table_access, table_habitat, table_streams, aoi,
                   table_to = NULL, presence = NULL,
                   species_resident = c("bt","wct"),
                   species_anadromous = c("ch","cm","co","pk","sk","st"),
                   species_spawn_only = c("cm","pk"))
  ```
- [ ] Function body: query `table_access`, query `table_habitat` (long form), pivot wide; query `table_streams.feature_code`; resolve `presence` (from arg or derive); call `lnk_pipeline_mapping_code()` with assembled inputs; write to `table_to` if provided; return tibble invisibly.
- [ ] `@export` + roxygen docstring with `@examples` showing both working-schema and persist-schema usage.
- [ ] `/code-check` clean.
- [ ] Commit: `Add lnk_mapping_code() — portable schema-aware build entry point`.

## Phase 4 — `mapping_code` phase in lnk_pipeline_run

- [ ] Add `mapping_code = FALSE` param to `lnk_pipeline_run()`.
- [ ] After phase 8 (species), before phase 9 (persist_init), when `mapping_code = TRUE`:
  - Call `lnk_pipeline_access` (mirrors current usage in lnk_compare_wsg.R:559).
  - Call `lnk_mapping_code()` (the new portable function) against working schema tables.
- [ ] Resolve `species_<role>` pass-through args from `cfg` if defined, else use function defaults.
- [ ] `/code-check` clean.
- [ ] Commit: `lnk_pipeline_run: add mapping_code phase via lnk_mapping_code()`.

## Phase 5 — Refactor lnk_compare_wsg

- [ ] Remove the inline mapping_code build (`R/lnk_compare_wsg.R:540-616`).
- [ ] Pass `mapping_code = mapping_code` to the `lnk_pipeline_run` call inside `lnk_compare_wsg`.
- [ ] Keep `.lnk_compare_wsg_mapping_code_diff` (tunnel-bound) — refactor to read from `<persist_schema>.streams_mapping_code` instead of working schema.
- [ ] Remove `pipeline_cleanup <- if (isTRUE(with_mapping_code)) FALSE else cleanup_working` special-case at `lnk_compare_wsg.R:164`.
- [ ] `/code-check` clean.
- [ ] Commit: `lnk_compare_wsg: consume mapping_code from persist (not inline build)`.

## Phase 6 — Rename sweep

- [ ] R API `with_mapping_code` → `mapping_code`: `lnk_compare_wsg` (deprecation shim).
- [ ] R API `<role>_species` → `species_<role>`: `lnk_pipeline_mapping_code`'s three params (deprecation shim).
- [ ] CLI flag `--with-mapping-code` → `--mapping-code` in: `wsgs_run_pipeline.sh`, `wsgs_dispatch.sh`, `wsgs_run_host.R`, `wsgs_run_m4_offline.sh`, `trifecta_smoke.sh`. Accept both; old emits stderr warning.
- [ ] Update `data-raw/README.md` flag tables + examples.
- [ ] Update all R-side docstrings + `@param` lines referencing old names.
- [ ] `/code-check` clean.
- [ ] Commit: `Rename with_mapping_code → mapping_code, <role>_species → species_<role> (deprecation shims)`.

## Phase 7 — Smoke test

- [ ] **Tunnel-down build** (headline acceptance):
  ```bash
  bash data-raw/wsgs_run_m4_offline.sh --wsgs=PARS --config=default \
    --schema=fresh_default --force --mapping-code
  ```
  Verify: `fresh_default.streams_access` + `fresh_default.streams_mapping_code` populated for PARS.
- [ ] **Standalone `lnk_mapping_code` against persist** (the portability claim) — tunnel down, rebuild `streams_mapping_code` for PARS from existing persist state. Verify idempotent.
- [ ] **bcfp view**: `Rscript data-raw/build_species_views.R fresh_default PARS --bcfp` → `streams_<sp>_bcfp_vw` views created. Confirm in QGIS.
- [ ] **Parity check** (tunnel up): `lnk_compare_wsg(aoi = "PARS", ..., mapping_code = TRUE)` → byte-identical `streams_mapping_code` rows vs the tunnel-down run.
- [ ] **Deprecation warnings**: old names trigger `.Deprecated()` / stderr; functionality unchanged.
- [ ] `devtools::test()` all pass.
- [ ] `devtools::check()` — no new warnings vs v0.39.1 baseline.

## Phase 8 — Release v0.40.0

- [ ] `DESCRIPTION`: `Version: 0.39.1 → 0.40.0`, `Date: <today>`.
- [ ] `NEWS.md` v0.40.0 entry covering all phases + deprecation notices + link to #189 follow-up.
- [ ] `CLAUDE.md` branch ref `v0.39.1 → v0.40.0`.
- [ ] Commit `Release v0.40.0`.
- [ ] `/planning-archive` slug `mapping-code-decouple-rename`.
- [ ] `/gh-pr-push` opens PR.
- [ ] `/gh-pr-merge` after CI green.

## Validation

- [ ] `devtools::test()` passes throughout
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope (filed)

- **link#189** — Data-drive species residence categorization from `dimensions.csv`. Unblocks custom species mixes (sea-run cutthroat, Dolly Varden) without monkey-patching function defaults.
- **link#175** — `lnk_compare_mapping_code` as own family member (unblocked by this PR's tunnel decouple).
- **link#176** — `lnk_compare_wsg` → `lnk_compare_run` family rename.
