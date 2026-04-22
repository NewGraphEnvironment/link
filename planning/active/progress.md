# Progress

## Session 2026-04-22

- Archived lnk_config PWF (shipped as link 0.2.0 via PR #39)
- Starting link#38: `_targets.R` pipeline
- Dependencies cleared: fresh 0.14.0 (frs_barriers_minimal) and link 0.2.0 (lnk_config) are on main
- rtj data parity on M4 + M1 confirmed; R install on M1 (Phase 3) still pending but not blocking — single-host first
- Issue #38 updated with package-vs-pipeline split (helpers in `R/`, `_targets.R` + comparison in `data-raw/`)
- PR 1 Phase 1.1 done: `lnk_pipeline_setup()` (originally `lnk_habitat_setup_schema`, renamed before building more). Mocked tests for SQL shape + identifier validation (8 passing). Live DB test intentionally skipped — CREATE SCHEMA semantics are Postgres's, not ours to test.
- Naming decision: prefix is `lnk_pipeline_*` (not `lnk_habitat_*` — only 1 of 6 phases is actually about habitat). Phase names read as verbs: setup → load → prepare → break → classify → connect.
- Param decision: canonical `(conn, aoi, cfg, schema)`. `aoi` follows fresh convention — accepts a WSG code today; extends to ltree filters, sf polygons, mapsheets later. `setup` is the only outlier: `(conn, schema, overwrite)`.
- PR 1 Phase 1.2 done: `lnk_pipeline_load()` — loads crossings + misc crossings + applies modelled fixes (NONE/OBS → PASSABLE) + PSCIS barrier status overrides. Split into three internal `@noRd` helpers for readability. Cleaner scope than the original "load_inputs" plan: falls, definite barriers, observation exclusions, and habitat classification moved to `prepare` where they're actually consumed. 12 tests (4 input validation + 4 fixes SQL/branching + 1 apply_pscis branching + 3 structure). 169 link tests total.
- Next: `lnk_pipeline_prepare()` — the network prep phase. Loads falls + definite barriers + observation exclusions + habitat classification, runs `frs_break_find` for gradient barriers, builds barrier overrides from obs/habitat evidence via `lnk_barrier_overrides`, reduces with `frs_barriers_minimal` (fresh 0.14.0), loads base segments
