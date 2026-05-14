# Progress — Decouple bcfp compare from link pipeline run (#168)

## Session 2026-05-14

- Plan-mode exploration — phases approved by user
- Function-name decision: `lnk_compare_rollup` (over `lnk_compare_one` from the issue body)
- Captured family-shape follow-ups (`lnk_compare_mapping_code`, `lnk_compare_wsg` → `lnk_compare_run` rename, persist family) in plan Out-of-scope
- Created branch `168-decouple-pipeline-compare` off main
- Scaffolded PWF baseline (`task_plan.md`, `findings.md`, `progress.md`) with 8 approved phases (commit `9a7d246`)
- **Phase 1 done.** Added `R/lnk_pipeline_run.R` + `tests/testthat/test-lnk_pipeline_run.R`. 16 tests PASS, `/code-check` clean (round 1).
- Next: Phase 2 — write `R/lnk_compare_rollup.R` + tests, adapt rollup queries to read from `<persist_schema>` wide-per-species tables instead of working-schema long format.
