# Progress — Decouple bcfp compare from link pipeline run (#168)

## Session 2026-05-14

- Plan-mode exploration — phases approved by user
- Function-name decision: `lnk_compare_rollup` (over `lnk_compare_one` from the issue body)
- Captured family-shape follow-ups (`lnk_compare_mapping_code`, `lnk_compare_wsg` → `lnk_compare_run` rename, persist family) in plan Out-of-scope
- Created branch `168-decouple-pipeline-compare` off main
- Scaffolded PWF baseline (`task_plan.md`, `findings.md`, `progress.md`) with 8 approved phases
- Next: Phase 1 — write `R/lnk_pipeline_run.R` + tests
