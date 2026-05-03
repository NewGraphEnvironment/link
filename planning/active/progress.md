# Progress — Persistent province-wide habitat tables (#112)

## Session 2026-05-03

- Archived #103 PWF (CABD dams, v0.24.0 shipped) to `planning/archive/2026-05-issue-103-ingest-cabd-dams/`.
- Created branch `112-persistent-provincial-habitat-tables` off main.
- Scaffolded PWF baseline from issue #112.
- Issue body had been rewritten + tightened pre-init (wide-per-species, dropped backwards-compat, dropped `tables = NULL` override path, dropped effort/SRED noise).
- Next: read task_plan.md Phase 1, start with `pipeline.schema` config knob in both bundles + `.lnk_table_names(cfg)` helper.
