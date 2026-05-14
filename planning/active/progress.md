# Progress — Decouple bcfp compare from link pipeline run (#168)

## Session 2026-05-14

- Plan-mode exploration — phases approved by user
- Function-name decision: `lnk_compare_rollup` (over `lnk_compare_one` from the issue body)
- Captured family-shape follow-ups (`lnk_compare_mapping_code`, `lnk_compare_wsg` → `lnk_compare_run` rename, persist family) in plan Out-of-scope
- Created branch `168-decouple-pipeline-compare` off main
- Scaffolded PWF baseline (`task_plan.md`, `findings.md`, `progress.md`) with 8 approved phases (commit `9a7d246`)
- **Phase 1 done.** Added `R/lnk_pipeline_run.R` + `tests/testthat/test-lnk_pipeline_run.R`. 16 tests PASS, `/code-check` clean (round 1). Commit `d4e046f`.
- **Phase 2 done.** Added `R/lnk_compare_rollup.R` + tests. Reuses `.lnk_compare_wsg_rollup_reference` + `.lnk_compare_wsg_assemble_rollup` from existing file. Link-side query rewritten as per-species `UNION ALL` over wide `streams_habitat_<sp>` tables. Species auto-discovered from PG via `information_schema` probe. 15 new tests PASS, full suite 1164 PASS / 0 FAIL. `/code-check` round 1 surfaced one fragility (species-suffix interpolation in probe query) — fixed via `grepl("^[a-z]+$", sp_candidates)` filter; round 2 clean. Bit-identical-rollup live-DB test deferred to Phase 7 smoke matrix.
- **Phase 3 done.** Added `.lnk_wsg_persisted(conn, cfg, aoi)` to `R/utils.R` and 6 new test_that blocks in `tests/testthat/test-utils.R`. Two-stage probe: information_schema (early-exit) then LIMIT 1 row check. 48 tests PASS in test-utils.R. `/code-check` clean.
- Next: Phase 4 — refactor `R/lnk_compare_wsg.R` to call `lnk_pipeline_run() + lnk_compare_rollup()` for the rollup-only path; preserve mapping_code branch as bundled flow.
