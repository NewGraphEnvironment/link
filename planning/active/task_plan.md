# Task: Persistent province-wide habitat tables (#112)

`fresh.streams` and `fresh.streams_habitat_<sp>` become persistent + accumulating WSG-by-WSG, mirroring bcfp's `bcfishpass.streams` + `bcfishpass.habitat_linear_<sp>` pattern. Per-WSG staging moves to `working_<wsg>` schema. `pipeline.schema` config knob threaded through.

## Phase 1: Parameterize link's table-name choice

- [ ] Add `pipeline.schema` field to both `inst/extdata/configs/{bcfishpass,default}/config.yaml`
- [ ] Add `.lnk_table_names(cfg)` private helper in `R/utils.R` (or new `R/lnk_table_names.R`) — returns named list with `streams` + `streams_habitat(sp)` constructors
- [ ] Validate cfg contract — add `cfg$pipeline$schema` non-empty check in `lnk_config()` schema validation; error clearly when missing
- [ ] Tests for `.lnk_table_names()` — both bundles, plus a fake cfg with custom schema

## Phase 2: Rewire pipeline phases to write to `working_<wsg>` schema

- [ ] `lnk_pipeline_prepare.R` — change `fresh.streams` → `working_<aoi>.streams` (uses `schema` arg already threaded)
- [ ] `lnk_pipeline_break.R` — change `frs_break_apply(table = "fresh.streams")` → `working_<aoi>.streams`
- [ ] `lnk_pipeline_classify.R` — change `frs_habitat_classify(table = "fresh.streams", to = "fresh.streams_habitat")` → `working_<aoi>.streams` / `working_<aoi>.streams_habitat`
- [ ] `data-raw/compare_bcfishpass_wsg.R` — top-of-run `DROP TABLE` block targets `working_<aoi>.*` (idempotent re-run)
- [ ] Existing tests pass — mock SQL emission should resolve to new working_<aoi> names

## Phase 3: Persist helpers

- [ ] `R/lnk_persist_init.R` — idempotent `CREATE TABLE IF NOT EXISTS <schema>.streams`, `<schema>.streams_habitat_<sp>` (one per species in cfg$species). DDL matches the working table shape.
- [ ] `R/lnk_pipeline_persist.R` — `lnk_pipeline_persist(conn, aoi, cfg, species)`:
   - DELETE-WHERE-WSG + INSERT for `<schema>.streams` from `working_<aoi>.streams`
   - For each species: DELETE-WHERE-WSG + INSERT for `<schema>.streams_habitat_<sp>` from `working_<aoi>.streams_habitat WHERE species_code = '<sp>'`
- [ ] Wire `lnk_persist_init` + `lnk_pipeline_persist` into `compare_bcfishpass_wsg.R` (init at top of script, persist at end of pipeline)
- [ ] Mocked unit tests for SQL emission shape (NULL conn_tunnel-style — no real DB)

## Phase 4: Single-WSG verification

- [ ] LRDO end-to-end: `compare_bcfishpass_wsg("LRDO", lnk_config("bcfishpass"))`
- [ ] Confirm `fresh.streams` populated for LRDO (segment count matches `working_lrdo.streams`)
- [ ] Confirm `fresh.streams_habitat_sk` populated (segment count matches `working_lrdo.streams_habitat WHERE species_code = 'SK'`)
- [ ] Confirm rollup tibble matches PRE-rename baseline byte-for-byte (the rollup math doesn't change)

## Phase 5: Trifecta 15-WSG verification

- [ ] Re-run `data-raw/trifecta_15wsg.sh`
- [ ] Each host accumulates locally — sanity-query a known WSG on each
- [ ] No cross-host clobber (M1 + cypher don't touch M4's `fresh.streams`)

## Phase 6: Provincial re-run

- [ ] `data-raw/trifecta_provincial.sh` — same orchestrator, now persists per-WSG
- [ ] ~2-3h compute on trifecta
- [ ] Each host has 78/77/77 WSGs in its local `fresh.streams` + 8 `fresh.streams_habitat_<sp>` tables

## Phase 7: Multi-host consolidation

- [ ] `data-raw/consolidate_provincial.sh` (new)
- [ ] `pg_dump --schema=fresh --table=streams --table=streams_habitat_*` from M1 + cypher
- [ ] `pg_restore --data-only` on M4 (idempotent — DELETE-WHERE-WSG keys handle re-runs)
- [ ] M4's `fresh.streams` has 232 WSGs × ~5M segments

## Phase 8: Sanity + ship

- [ ] Sanity-query: SETN + LRDO on master M4 match the prior rollup tibbles within fp precision
- [ ] `devtools::test()` clean
- [ ] `lintr::lint_package()` clean
- [ ] `/code-check` on staged diff — 3 rounds clean
- [ ] NEWS.md entry, DESCRIPTION bump (likely 0.26.0 — minor, new persist capability)
- [ ] PR with `Fixes #112` + `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] `/planning-archive` after merge
