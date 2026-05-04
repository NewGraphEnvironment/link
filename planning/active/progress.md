# Progress — DB hygiene: drop working schemas after persist; drop worker schemas after consolidation (#118)

## Session 2026-05-04

- Plan-mode exploration of `R/lnk_pipeline_persist.R`, `data-raw/compare_bcfishpass_wsg.R`, `data-raw/consolidate_schema.R`, and existing persist tests. Phases approved by user.
- Decision: orchestrator-level cleanup (compare_bcfishpass_wsg + consolidate_schema), not in-package. Keeps `lnk_pipeline_persist` scoped to one job; rollup query continues to read working schema in long-form.
- Created branch `118-db-hygiene-drop-working-schemas-after-pe` off main (post v0.28.0).
- Scaffolded PWF baseline.
- Next: Phase 1 — add `cleanup_working = TRUE` parameter to `compare_bcfishpass_wsg()`, drop schema after rollup, ADMS smoke.
