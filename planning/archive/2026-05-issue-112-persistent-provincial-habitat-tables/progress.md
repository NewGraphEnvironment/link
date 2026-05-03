# Progress — Persistent province-wide habitat tables (#112)

## Session 2026-05-03

- Archived #103 PWF (CABD dams, v0.24.0 shipped) to `planning/archive/2026-05-issue-103-ingest-cabd-dams/`.
- Created branch `112-persistent-provincial-habitat-tables` off main.
- Scaffolded PWF baseline from issue #112.
- Issue body had been rewritten + tightened pre-init (wide-per-species, dropped backwards-compat, dropped `tables = NULL` override path, dropped effort/SRED noise).
- Ran Plan agent against the initial PWF — found 21 planning issues. Rewrote `task_plan.md` to address all of them.
- Key changes from the rewrite:
  - **Inventory of every `fresh.streams` literal** (12+ sites across `lnk_pipeline_prepare/break/classify/connect`, `compare_bcfishpass_wsg.R`) — Phase 2 now lists each file/line. Original plan listed only 4 files; would have left the pipeline half-renamed.
  - **Phase 0: capture baselines on main BEFORE branching** — required for Phase 5+ "byte-for-byte" acceptance.
  - **Locked decisions table at the top** — schema value for both bundles (`fresh`), `lnk_persist_init` lives in `lnk_pipeline_setup`, species from `lnk_pipeline_species`, explicit DDL specs (column types + PKs + indexes).
  - **Phase 1 atomic land** — config knob + helper + DDL helper + validator together (no half-state where the validator hard-errors on configs missing the field).
  - **`lnk_persist_init` lives in `lnk_pipeline_setup`** — every entry point gets persistence wired for free, not just compare_bcfishpass_wsg.
  - **Long→wide pivot SELECT explicit** — drops `species_code` from per-species INSERT (avoids blind `SELECT *`).
  - **Phase 4 names data-raw/run_nge.R** — pick A (refactor) or B (scope-out + document).
  - **Phase 8 backup before consolidation** — `pg_dump` of M4's pre-consolidation state as rollback safety. Fixed `pg_restore --on-conflict=update` (doesn't exist) → use `--data-only` with prior DELETE-WHERE keys.
  - **Test-update + roxygen sweep** as their own phase — original plan said "tests pass" but `test-lnk_pipeline_prepare.R:258` and `test-lnk_pipeline_classify.R:50-51` have literal-string assertions that would fail.
- Next: read task_plan.md Phase 0, capture pre-rename baselines on main before checking out the branch for Phase 1.

## Session 2026-05-03 (cont.) — Phase 0 + Phase 1 landed

Phase 0:
- Committed `data-raw/logs/provincial_parity/*.rds` (232 WSGs, link 0.25.1, ~120KB) on the branch as the persistent baseline. Re-deciding from the original task plan: skip the explicit baseline_pre_112/ directory — the existing 232-WSG provincial_parity dump from 2026-05-03 already covers the full province at the right code version. Phase 5+ verifications will diff against `data-raw/logs/provincial_parity/<wsg>.rds`.

Phase 1:
- `pipeline.schema: fresh` added to both bundles' `config.yaml` (with explanatory comment).
- `.lnk_table_names(cfg)` + `.lnk_working_schema(aoi)` helpers added to `R/utils.R`.
- `R/lnk_persist_init.R` — DDL helper driven by `cols_streams` + `cols_habitat` named-vector abstractions. Single source of truth for schema shape (will be reused in `lnk_pipeline_persist` Phase 2). Mirrors bcfp's `bcfishpass.streams` (24 cols) + `bcfishpass.habitat_linear_<sp>` (extended with link's `accessible` / `lake_rearing` / `wetland_rearing` booleans).
- Tests: 28 new PASS in `test-lnk_persist_init.R`. Full suite: 696 PASS / 0 FAIL.
- Reinstalled package; verified both bundles read `cfg$pipeline$schema = "fresh"` correctly.

Next: Phase 2 — rewire all 12+ `fresh.streams` / `fresh.streams_habitat` / `fresh.streams_breaks` literals across `lnk_pipeline_prepare/break/classify/connect` + `compare_bcfishpass_wsg.R` to write to `working_<aoi>.*`. Add `lnk_pipeline_persist()` that pivots long → wide using `cols_habitat` for the SELECT projection. Wire `lnk_persist_init` into `lnk_pipeline_setup`.

## Session 2026-05-03 (cont. cont.) — Phase 2 + 3 + 5 landed

Phase 2 (rewire + persist helper):
- Replaced all `fresh.streams` / `fresh.streams_habitat` / `fresh.streams_breaks` literals across `lnk_pipeline_prepare/break/classify/connect` + `compare_bcfishpass_wsg.R` with `paste0(schema, ".streams")` style — schema arg already equals `working_<aoi>` per existing convention.
- `R/lnk_pipeline_persist.R` — DELETE-WHERE-WSG + INSERT for streams + per-species streams_habitat_<sp>. Long→wide pivot: per-species INSERT filters `working_<aoi>.streams_habitat WHERE species_code = '<sp>'` and projects `cols_habitat` (drops species_code). Idempotent via DELETE keys.
- Decided AGAINST wiring lnk_persist_init into lnk_pipeline_setup (would pollute its 3-arg interface). compare_bcfishpass_wsg.R orchestrator calls both lnk_persist_init + lnk_pipeline_persist directly after lnk_pipeline_connect. Idempotent CREATE TABLE IF NOT EXISTS makes per-WSG init safe.

Phase 3 (test fixes):
- `test-lnk_pipeline_prepare.R:258` literal `"CREATE TABLE fresh.streams"` → `"CREATE TABLE w_bulk.streams"`.
- `test-lnk_pipeline_classify.R:50-51` literal `"fresh.streams_breaks"` → `"w_bulk.streams_breaks"`.
- 4 new tests in `test-lnk_pipeline_persist.R` — SQL emission shape, DELETE+INSERT pair counts, long→wide pivot, custom schema arg.

Phase 1 fixes from real-world test:
- `cols_streams` initially had bcfp-aspirational columns (`segmented_stream_id`, `mad_m3s`, `upstream_area_ha`, `stream_order_max`) that don't exist in `working_<aoi>.streams`. Aligned to actual 21-col shape.
- `geom geometry(MultiLineString, 3005)` failed at INSERT — FWA streams have Z dimension. Fixed to `MultiLineStringZ`. Then failed M dimension. Fixed to `MultiLineStringZM` (XYZM — X, Y, elevation, measure).

Phase 5 verification (LRDO end-to-end):
- Wall: ~120s (similar to pre-rename 120-160s).
- `fresh.streams` LRDO rows: 20,473 — matches `working_lrdo.streams` exactly.
- All 5 active species (CM/CO/PK/SK/ST) — `fresh.streams_habitat_<sp>` rows = 20,473 each, match working filtered-by-species.
- LRDO SK rollup re-derived from persistent JOIN matches baseline byte-for-byte (spawning=14.58 km, rearing=211.13 km, lake_rearing=4,808.66 ha). Phase 5 PASS.

Tests: 710 PASS / 0 FAIL. Reinstalled package, verified end-to-end.

Next: Phase 4 (`data-raw/run_nge.R` decision: refactor or scope-out) → Phase 6 (trifecta 15-WSG verification — does cross-host clobber happen? does the 232-RDS baseline still match?).
