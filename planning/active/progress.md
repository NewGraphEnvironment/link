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
