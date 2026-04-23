# Progress

## Session 2026-04-23

- Archived `2026-04-23-targets-pipeline/` — link#38 closed via PRs #41/#42/#43. Three consecutive `tar_make()` runs produced bit-identical rollups. All species within 5% of bcfishpass reference on all four WSGs.
- Branched `44-barriers-definite-control` off main.
- Plan approved. PWF initialized for #44.
- Pre-flight complete: identified the `ctrl_filter` bug in `lnk_barrier_overrides` (all rows block, not just `barrier_ind = TRUE`), and confirmed `.lnk_pipeline_prep_overrides` doesn't pass `control`. Same PR fixes both — filter semantics + missing pass-through.
- Next: Phase 1 — fix `R/lnk_barrier_overrides.R` `ctrl_filter` and add `tests/testthat/test-lnk_barrier_overrides.R`.
- Phase 1 committed (d1a7109) — `NOT EXISTS` control filter, 11 tests, 269 PASS.
- Phase 2 committed (53bedbd) — manifest-gated `control` pass-through in `.lnk_pipeline_prep_overrides`, fixed asymmetric load_aux (schema-valid empty table), 271 PASS.
- Post-Phase-2 `tar_make()` (log: `data-raw/logs/20260423_01_tar_make_post_44.txt`) showed 11–22pp drift AWAY from bcfishpass on ADMS/BABL; BULK/ELKR unchanged. Root cause: bcfishpass applies control filter only in CH/CM/CO/PK/SK and ST models (not BT/WCT/CT/DV/RB). My implementation applied it across all species in the `params` loop.
- Phase 2a: new `observation_control_apply` column in `parameters_fresh.csv` (TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT; NA for CT/DV/RB), per-species NOT EXISTS gate in `lnk_barrier_overrides()`, three new tests. 279 PASS. Amendment pushed to issue #44 documenting the species-scoped approach and biological rationale.
- Next: Phase 3 — `pak::local_install()`, `tar_make()`, compare rollup to bcfishpass; expected direction — BT/WCT/ST on ADMS/BABL recover to near pre-fix, CH/CM/CO/PK/SK slightly closer to bcfishpass.
