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

Plus the new wiring:

- [ ] `R/lnk_pipeline_persist.R` — `lnk_pipeline_persist(conn, aoi, cfg, species)`:
  - `DELETE FROM <schema>.streams WHERE watershed_group_code = '<aoi>'; INSERT INTO <schema>.streams SELECT … FROM working_<aoi>.streams;`
  - For each `sp` in `species`: `DELETE … WHERE wsg=<aoi>; INSERT INTO <schema>.streams_habitat_<sp> SELECT id_segment, watershed_group_code, accessible, spawning, rearing, lake_rearing, wetland_rearing FROM working_<aoi>.streams_habitat WHERE species_code = '<sp>'`
- [ ] `R/lnk_pipeline_setup.R` — call `lnk_persist_init(conn, cfg, species)` after creating the per-AOI working schema. Species resolved via `lnk_pipeline_species(cfg, loaded, aoi)`.
- [ ] `data-raw/compare_bcfishpass_wsg.R` — call `lnk_pipeline_persist()` after the `lnk_pipeline_connect()` call, before computing the per-WSG rollup tibble.

## Phase 3: Update tests + roxygen examples

- [ ] `tests/testthat/test-lnk_pipeline_prepare.R` line ~258 — literal `"CREATE TABLE fresh.streams"` → parameterize via test fixture cfg with known schema; assert dynamic table name.
- [ ] `tests/testthat/test-lnk_pipeline_classify.R` line 50-51 — same pattern, `"fresh.streams_breaks"` → dynamic.
- [ ] Add tests for `lnk_pipeline_persist` SQL emission shape (mocked DBI):
  - One DELETE+INSERT pair for `<schema>.streams`
  - N DELETE+INSERT pairs for `<schema>.streams_habitat_<sp>` (N = species count)
  - SELECT clauses on the per-species INSERT drop `species_code`
- [ ] Roxygen example sweep — `R/lnk_aggregate.R`, `R/lnk_barrier_overrides.R`, `R/lnk_pipeline_*` examples that say `fresh.streams` / `fresh.streams_habitat` → update or note as illustrative.
- [ ] `devtools::test()` clean
- [ ] `lintr::lint_package()` clean

## Phase 4: data-raw/run_nge.R — update or scope-out

`data-raw/run_nge.R:170-203` has its own `DROP+CREATE` against `fresh.streams` and rollup queries. Two options:

- [ ] **Option A (in-scope, recommended)**: refactor to use the new working-schema pattern + `lnk_pipeline_persist`. ~1h.
- [ ] **Option B (out-of-scope, deliberate)**: leave as legacy, document at top of file that it doesn't write to persistent `fresh.streams`. Will silently break if someone runs it post-rename.

Pick A unless run_nge is genuinely abandoned. Confirm with user before phase exits.

## Phase 5: Single-WSG verification (LRDO)

- [ ] `Rscript data-raw/compare_bcfishpass_wsg.R` invocation for LRDO post-merge of Phases 0-4
- [ ] Assertions:
  - `working_lrdo.streams` rowcount > 0 and equals `<schema>.streams` rowcount filtered to LRDO
  - For each species in LRDO's set: `working_lrdo.streams_habitat WHERE species_code = '<sp>'` rowcount equals `<schema>.streams_habitat_<sp>` rowcount filtered to LRDO
  - Rollup tibble matches `data-raw/logs/baseline_pre_112/LRDO_baseline.rds` byte-for-byte (allowing fp tolerance 1e-9)
- [ ] Also re-run a non-overlapping WSG (e.g. ADMS) — confirm running LRDO didn't clobber ADMS's persisted rows in `<schema>.streams`

## Phase 6: Trifecta 15-WSG verification

- [ ] `bash data-raw/trifecta_15wsg.sh`
- [ ] Each host accumulates locally — sanity-query a known WSG on each (M4: BULK, M1: BABL, cypher: HARR)
- [ ] No cross-host clobber (M4's `<schema>.streams` only has M4-bucket WSGs; same for M1, cypher)
- [ ] All 15 rollup tibbles match the corresponding 2026-05-03 trifecta-15 baseline (`data-raw/logs/202605030429-202605030437_trifecta15_*_bcfishpass_*.rds`)

## Phase 7: Provincial re-run

- [ ] `bash data-raw/trifecta_provincial.sh`
- [ ] Wall ~2-3h trifecta
- [ ] Each host: 78/77/77 WSGs persisted in its local `<schema>.streams` + 8 `<schema>.streams_habitat_<sp>` tables
- [ ] Per-host acceptance: `SELECT count(*), count(DISTINCT watershed_group_code) FROM <schema>.streams` matches expected per-bucket totals

## Phase 8: Multi-host consolidation onto M4

- [ ] **First**: `pg_dump --schema=fresh -Fc -f /tmp/m4_fresh_pre_consolidate_<TS>.dump` on M4 (rollback safety net — if consolidation corrupts state, restore from this)
- [ ] On M1 + cypher: `pg_dump --schema=fresh -Fc -f /tmp/<host>_fresh.dump`
- [ ] scp dumps to M4
- [ ] On M4: for each remote dump, `pg_restore --data-only --no-owner --schema=fresh /tmp/<host>_fresh.dump` — leverages the per-WSG DELETE-WHERE keys (idempotent if some WSGs already present)
- [ ] Verify: `SELECT count(DISTINCT watershed_group_code) FROM <schema>.streams` = 232

## Phase 9: Sanity-query final state

- [ ] LRDO check: `SELECT count(*) FROM <schema>.streams_habitat_sk WHERE watershed_group_code = 'LRDO' AND lake_rearing` matches the LRDO drilldown's 7 lakes (114+73+50+19+36+14+20 segments ≈ link's 4,808 ha)
- [ ] SETN check: anadromous spawning rows match link's prior +98% over bcfp
- [ ] Total `<schema>.streams` row count ≈ 5M (sanity-check against bcfp's `bcfishpass.streams` count)
- [ ] No row in `<schema>.streams_habitat_<sp>` lacks a matching `<schema>.streams` row (referential integrity)

## Phase 10: Ship

- [ ] NEWS.md entry — 0.26.0 minor (new persistence capability)
- [ ] DESCRIPTION version 0.25.1 → 0.26.0
- [ ] `/code-check` on staged diff — 3 rounds clean
- [ ] PR with `Fixes #112` + `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] `/gh-pr-merge` after review
- [ ] `/planning-archive` after merge
