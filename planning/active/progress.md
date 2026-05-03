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
