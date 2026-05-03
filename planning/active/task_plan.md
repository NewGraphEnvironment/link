# Task: Persistent province-wide habitat tables (#112)

`fresh.streams` and `fresh.streams_habitat_<sp>` become persistent + accumulating WSG-by-WSG, mirroring bcfp's `bcfishpass.streams` + `bcfishpass.habitat_linear_<sp>`. Per-WSG staging moves to `working_<wsg>` schema. `pipeline.schema` config knob threaded through.

## Locked design decisions

| | |
|---|---|
| Schema value (both bundles) | `fresh` — runs are sequential today; if/when we run bundles side-by-side later, switch to `fresh_bcfp` + `fresh_default` |
| `lnk_persist_init` call site | `lnk_pipeline_setup()` — every entry point (compare script, run_nge, future scripts) gets it for free |
| Species list source | `lnk_pipeline_species(cfg, loaded, aoi)` UNION'd across the run's WSGs, OR `unique(loaded$parameters_fresh$species_code)`. **Not** `cfg$species` (doesn't exist in either bundle's config.yaml). |
| Long→wide pivot | per-species `INSERT … SELECT id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing FROM working_<aoi>.streams_habitat WHERE species_code = '<sp>'` (drop `species_code` column from SELECT) |
| Consolidation | `pg_dump --schema=fresh -Fc` per host → `pg_restore --data-only --no-owner --schema=fresh` on M4. Idempotent via prior DELETE-WHERE-WSG keyed inserts. (`pg_restore --on-conflict=update` doesn't exist — earlier issue body claim was wrong.) |
| Cross-host clobber risk | Confirmed safe — M4/M1/cypher each have their own local fwapg :5432. Trifecta writes don't share a DB. |

## Phase 0: Capture baseline before any code changes

Required for Phase 5+ acceptance ("rollup tibbles match pre-rename byte-for-byte").

- [x] Phase 0 settled differently: provincial_parity `data-raw/logs/provincial_parity/*.rds` (232 WSGs, link 0.25.1, captured 2026-05-03) IS the baseline — covers far more than the 5 WSGs originally listed. Committed on the issue branch (still survives any PR squash since we'll merge with --squash, all PWF + baseline land together). Path of record: `data-raw/logs/provincial_parity/<wsg>.rds`.

## Phase 1: Add `pipeline.schema` + `.lnk_table_names()` + persist_init DDL helper

Atomic land — config, helper, validator, DDL helper all together, so no half-state where the validator fires on bundles missing the field.

- [x] Add `pipeline.schema: fresh` to both `inst/extdata/configs/{bcfishpass,default}/config.yaml`
- [x] Add `.lnk_table_names(cfg)` private helper in `R/utils.R`. Returns list with `schema`, `streams`, `habitat_for(sp)` constructor. Errors clearly when `cfg$pipeline$schema` is missing/empty.
- [x] Add `.lnk_working_schema(aoi)` helper alongside (returns `working_<wsg>` — used by Phase 2).
- [x] `R/lnk_persist_init.R` — `lnk_persist_init(conn, cfg, species)`. Idempotent CREATE SCHEMA + CREATE TABLE IF NOT EXISTS. DDL driven by `cols_streams` + `cols_habitat` named-vector abstractions (single source of truth shared with `lnk_pipeline_persist`).
- [x] Validation gate is `.lnk_table_names()` itself — errors clearly when `cfg$pipeline$schema` empty. Skipped extending `lnk_config_verify` since it's drift-detection only; entry-point validation is the gatekeeper.
- [x] Tests: 28 PASS — `.lnk_table_names` happy-path + missing-schema errors + `habitat_for` species validation; `.lnk_working_schema` happy-path + invalid input; `lnk_persist_init` mocked SQL emission asserts CREATE SCHEMA + CREATE TABLE for streams + per-species habitat tables + GIST index.
- [x] Full suite: 696 PASS / 0 FAIL — no regressions.

## Phase 2: Rewire pipeline phases to write `working_<aoi>` staging + persist at end

Inventory of every `fresh.streams` / `fresh.streams_habitat` / `fresh.streams_breaks` literal that needs to change:

| File | Lines | Current | New |
|---|---|---|---|
| `R/lnk_pipeline_prepare.R` | 544-548 | `DROP/CREATE fresh.streams + DROP fresh.streams_habitat` | `DROP/CREATE working_<aoi>.streams + DROP working_<aoi>.streams_habitat` |
| `R/lnk_pipeline_prepare.R` | 557, 562 | `frs_col_join("fresh.streams", …)` | `frs_col_join("working_<aoi>.streams", …)` |
| `R/lnk_pipeline_prepare.R` | `.lnk_pipeline_prep_network()` ~444-580 | 8× `"fresh.streams"` literals | All → `working_<aoi>.streams` |
| `R/lnk_pipeline_break.R` | 124-127, 233-244 | `frs_break_apply(table = "fresh.streams")` + index `fresh.streams_id_segment_idx` | `working_<aoi>.streams` + `working_<aoi>.streams_id_segment_idx` |
| `R/lnk_pipeline_classify.R` | 95-97 | `frs_habitat_classify(table = "fresh.streams", to = "fresh.streams_habitat")` | `working_<aoi>.streams` / `working_<aoi>.streams_habitat` |
| `R/lnk_pipeline_classify.R` | 124-127 (overlay) | `bridge = "fresh.streams"`, `to = "fresh.streams_habitat"` | `working_<aoi>.*` |
| `R/lnk_pipeline_classify.R` | 160-161 (frs_order_child) | `table = "fresh.streams"`, `habitat = "fresh.streams_habitat"` | `working_<aoi>.*` |
| `R/lnk_pipeline_classify.R` | 197-199 | `DROP/CREATE fresh.streams_breaks` | `working_<aoi>.streams_breaks` |
| `R/lnk_pipeline_connect.R` | 103-104 | `.frs_run_connectivity(table = "fresh.streams", habitat = "fresh.streams_habitat")` | `working_<aoi>.*` |
| `data-raw/compare_bcfishpass_wsg.R` | 62-64 | `DROP TABLE fresh.streams, fresh.streams_habitat, fresh.streams_breaks CASCADE` | `DROP working_<aoi>.streams, working_<aoi>.streams_habitat, working_<aoi>.streams_breaks` |
| `data-raw/compare_bcfishpass_wsg.R` | ~143, 178-179, 194-195 | rollup queries against `fresh.streams_habitat` | `working_<aoi>.streams_habitat` (long-format, queried before persist) |

All literal-rewires done. Plus new wiring:

- [x] `R/lnk_pipeline_persist.R` — `lnk_pipeline_persist(conn, aoi, cfg, species, schema)` does DELETE-WHERE-WSG + INSERT for streams + per-species streams_habitat_<sp>. Long→wide pivot via `WHERE species_code = '<sp>'` filter; SELECT projection drops species_code.
- [x] Decision: `lnk_persist_init` is called from `compare_bcfishpass_wsg.R` orchestrator (idempotent, safe to call per-WSG), NOT wired into `lnk_pipeline_setup` (would pollute its 3-arg interface).
- [x] `data-raw/compare_bcfishpass_wsg.R` — calls `lnk_persist_init` + `lnk_pipeline_persist` after `lnk_pipeline_connect()`, with species from `lnk_pipeline_species`.
- [x] `cols_streams` aligned to actual `working_<aoi>.streams` shape (21 cols, dropped bcfp-aspirational `segmented_stream_id` / `mad_m3s` / `upstream_area_ha` / `stream_order_max`); `geom geometry(MultiLineStringZM, 3005)` (FWA streams are XYZM, not 2D).

## Phase 3: Update tests + roxygen examples

- [x] `tests/testthat/test-lnk_pipeline_prepare.R` line ~258 — `"CREATE TABLE fresh.streams"` → `"CREATE TABLE w_bulk.streams"` (matches new working-schema staging).
- [x] `tests/testthat/test-lnk_pipeline_classify.R` line 50-51 — `"fresh.streams_breaks"` → `"w_bulk.streams_breaks"`.
- [x] Tests for `lnk_pipeline_persist` SQL emission shape (4 tests in `test-lnk_pipeline_persist.R`):
  - One DELETE+INSERT pair for `<schema>.streams` ✓
  - N DELETE+INSERT pairs for `<schema>.streams_habitat_<sp>` (N = species count) — verified for 3-species case (8 statements total = 2 + 6) ✓
  - SELECT clauses on per-species INSERT drop `species_code` ✓
  - Custom `schema` arg respected ✓
- [x] `devtools::test()` clean — 710 PASS / 0 FAIL.
- [ ] `lintr::lint_package()` clean — defer until phase 4 / 8a.
- [ ] Roxygen example sweep — `R/lnk_aggregate.R`, `R/lnk_barrier_overrides.R`, `R/lnk_pipeline_*` examples that say `fresh.streams` / `fresh.streams_habitat` → update or note as illustrative. Defer to Phase 8a doc-sweep.

## Phase 4: data-raw/run_nge.R — DELETED

- [x] `git rm data-raw/run_nge.R`. Use case ("run pipeline with NGE defaults for any WSG") is exactly what `lnk_config("default")` + `compare_bcfishpass_wsg()` does — with persistence + wide-per-species for free. run_nge.R was a 4-month-old standalone demo that predated the bundle architecture; no external references found in CLAUDE.md, tests, vignettes, or other scripts.

## Phase 5: Single-WSG verification (LRDO)

- [x] LRDO end-to-end (`compare_bcfishpass_wsg("LRDO", lnk_config("bcfishpass"))`) — wall ~120s.
- [x] Assertions verified:
  - `fresh.streams` LRDO row count = `working_lrdo.streams` row count = **20,473** ✓
  - All 5 active species (CM/CO/PK/SK/ST) — persistent `fresh.streams_habitat_<sp>` row count = working long-format filtered count = **20,473 each** ✓
  - LRDO SK rollup re-derived from `fresh.streams` JOIN `fresh.streams_habitat_sk` matches `data-raw/logs/provincial_parity/LRDO.rds` baseline byte-for-byte: spawning=14.58 km, rearing=211.13 km, lake_rearing=4,808.66 ha ✓
- [ ] Re-run a non-overlapping WSG (e.g. ADMS) — confirm running LRDO didn't clobber ADMS's persisted rows. (Deferred to Phase 6 trifecta verification — same test there.)

## Phase 6: Trifecta 15-WSG verification

- [x] `bash data-raw/trifecta_15wsg.sh` — wall 9m28s. All 5/5 ok per host.
- [x] Per-host accumulation: M4 5 WSGs / 133K rows, M1 5 WSGs / 181K rows, cypher 5 WSGs / 105K rows.
- [x] No cross-host clobber. Per-species coverage tracks presence (M1's `streams_habitat_sk` correctly has only 2 of 5 WSGs since BABL/LFRA/ELKR don't have SK).

## Phase 7: Provincial re-run

- [x] `bash data-raw/trifecta_provincial.sh` — wall 2h03m26s. All 3 hosts exit 0.
- [x] First attempt was a 6-second no-op due to resume-safe cache shadowing the Phase 0 baselines. Fixed by moving baselines to `data-raw/logs/baseline_pre_112/` so `run_provincial_parity.R` no longer skips. Surfaces link#110 (cache invalidation gap).
- [x] Per-host accumulator: M4 73 WSGs / 1.66M, M1 70 WSGs / 1.82M, cypher 74 WSGs / 1.85M. Sum: 217 WSGs / 5.3M rows. (15 WSGs are "no species resolved" error stubs — same 15 as the pre-rename baseline; expected.)

## Phase 8: Multi-host consolidation onto M4

- [x] M4 backup: `/tmp/m4_fresh_pre_consolidate_202605031258.dump` (1.3GB, rollback safety net).
- [x] `pg_dump --schema=fresh -Fc` on M1 + cypher via `docker exec fresh-db pg_dump`. Both 1.4GB. SHA-1 verified post-scp.
- [x] `pg_restore --data-only --no-owner --schema=fresh` for M1 + cypher dumps onto M4. No PK conflicts (per-host buckets non-overlapping).

## Phase 9: Sanity-query final state

- [x] **5/5 test WSGs byte-identical to pre-#112 baseline:** LRDO, SETN, ADMS, BULK, HARR all match on SK spawning + rearing + lake_rearing (15 cells, 0 drift).
- [x] Province-wide: `fresh.streams` = **217 WSGs / 5,323,387 rows**.
- [x] Per-species streams_habitat_<sp> coverage tracks `wsg_species_presence`: BT 158 WSGs (4.1M rows), CH 125 (2.9M), CO 100 (2.4M), SK 84 (2.0M), ST 79 (2.0M), PK 60 (1.5M), CM 55 (1.4M), WCT 16 (0.5M).
- [x] LRDO SK matches drilldown finding exactly: 14.58 km spawn / 211.13 km rear / 4,808.66 ha lake_rearing (Whalen + 6 other lakes).

## Phase 10: Ship

- [ ] NEWS.md entry — 0.26.0 minor (new persistence capability)
- [ ] DESCRIPTION version 0.25.1 → 0.26.0
- [ ] `/code-check` on staged diff — 3 rounds clean
- [ ] PR with `Fixes #112` + `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] `/gh-pr-merge` after review
- [ ] `/planning-archive` after merge
