# Task: Unified `<persist_schema>.barriers` (province-wide) with `blocks_species` predicate (#152)

`lnk_pipeline_access()` currently consumes bcfp-shape per-species barriers tables (`barriers_bt`, `barriers_ch_cm_co_pk_sk`, ...). Phase A bcfp parity (post-link#154) sits at ≥99% on all in-WSG species **except PARS BT (60.64%)** — PARS drains through dams in *other* WSGs (PCEA/UPCE) and per-WSG `WHERE watershed_group_code = 'PARS'` barrier scoping can't see them. This blocks any regional run (Skeena: KISP/BABL through Williston, etc.). The compare script also stages bcfp's per-species barriers from the tunnel as a self-sufficiency workaround.

Replace per-WSG-scoped + per-species-materialized barriers tables with one province-wide `<persist_schema>.barriers` table carrying a `blocks_species text[]` predicate column. Per-WSG runs DELETE/INSERT their slice into the unified table; `lnk_pipeline_access` filters via `WHERE 'bt' = ANY(blocks_species)`. Cross-WSG dnstr "just works" because `fresh::frs_network_features` walks FWA topology and doesn't care which WSG a barrier lives in.

Full algorithm + critical-files table in `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md`.

## Phase 1: schema + persist DDL

- [x] Add `cols_barriers` vector at top of `R/lnk_persist_init.R` (alongside `cols_streams` / `cols_habitat`).
- [x] Extend `lnk_persist_init()` to `CREATE TABLE IF NOT EXISTS <schema>.barriers` with `cols_barriers` + indexes (GIN on `blocks_species`, btree on `(watershed_group_code, barrier_source)`, btree on `(blue_line_key, downstream_route_measure)`, GIST on `geom`).
- [x] Update `test-lnk_persist_init.R` — assert `<schema>.barriers` CREATE TABLE statement is issued.

## Phase 2: `lnk_barriers_unify`

- [x] Write `R/lnk_barriers_unify.R` — new exported function. Signature: `lnk_barriers_unify(conn, aoi, cfg, loaded, schema = paste0("working_", tolower(aoi)))`. 5-source UNION ALL building per-WSG `<schema>.barriers` staging:
  - Anthropogenic (PSCIS/CABD/MODELLED with `barrier_status IN ('BARRIER','POTENTIAL')`)
  - Remediations (PASSABLE remediations — `blocks_species = ARRAY[]`)
  - Gradient (per-class; `blocks_species` derived from `parameters_fresh$access_gradient_max`)
  - Falls (natural, all species)
  - Subsurface_flow (natural, all species, opt-in)
- [x] `devtools::document()` regenerate man.
- [x] Write `tests/testthat/test-lnk_barriers_unify.R` — mocked SQL composition + `blocks_species` derivation.
- [x] `lintr::lint` clean.

## Phase 3: persistence + `lnk_pipeline_persist` extension

- [x] Extend `lnk_pipeline_persist()` to also persist `<schema>.barriers` to `<persist_schema>.barriers` (DELETE WHERE watershed_group_code = aoi; INSERT). Driven by `cols_barriers`.
- [x] Update `test-lnk_pipeline_persist.R` — assert barriers DELETE/INSERT is issued.

## Phase 4: `lnk_pipeline_access` consumes unified table

- [ ] Add `barriers_unified` arg to `lnk_pipeline_access()`. When supplied, build subquery-based `features` references for per-species loop (`WHERE <sp> = ANY(blocks_species)`) and source-typed loop (`WHERE barrier_source = '<src>'`). Cache by filter signature.
- [ ] When `barriers_unified = NULL`, existing `barriers_per_sp` + `barrier_sources` paths run unchanged (backward compat).
- [ ] Update `test-lnk_pipeline_access.R` — coverage for the unified-barriers code path.

## Phase 5: orchestrator wiring + compare scripts

- [ ] Wire `lnk_barriers_unify` into `data-raw/compare_bcfishpass_wsg.R` after `lnk_pipeline_crossings`. Call `lnk_persist_init` + extended `lnk_pipeline_persist` to write to persist schema.
- [ ] Update `data-raw/compare_bcfp_mapping_code.R` — replace bcfp-tunnel barriers staging (lines 122–147) with `barriers_unified = paste0(tn$schema, ".barriers")`.

## Phase 6: Phase A re-run + acceptance

- [ ] Live Phase A re-run: `data-raw/compare_bcfp_mapping_code.R --wsgs=ADMS,BULK,WILL,PARS`. PARS BT must hit ≥99% from local-only inputs (cross-WSG validation). Other WSGs maintain ≥99%.
- [ ] Update `research/bcfp_compare_mapping_code.md` Status section: PARS BT closure noted, Skeena unblocked.

## Phase 7: release

- [ ] DESCRIPTION 0.34.0 → 0.35.0 (minor — new export, schema additions, no breaking changes).
- [ ] NEWS.md 0.35.0 entry: unified barriers shape, PARS BT closure, new `lnk_barriers_unify` export.
- [ ] `devtools::check()`: 0 errors / pre-existing notes only.
- [ ] `/planning-archive` + `/gh-pr-push` to open PR closing #152.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
