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
- Phase 2a alone was insufficient — CH/CO/SK/ST on ADMS/BABL still drifted -15 to -22pp. Investigation traced the residual to my ctrl_filter also blocking the habitat-path INSERT in lnk_barrier_overrides. bcfishpass's `hab_upstr` CTE has no control join — habitat is higher-trust and bypasses the filter.
- Phase 2b (6f3bc46) — removed ctrl_where/ctrl_filter from habitat INSERT; flipped the "control applies to habitat" test to assert absence; docstring notes habitat bypass. 279 PASS.
- Post-Phase-2b rollup exactly matches pre-fix baseline on all 4 parity WSGs. Investigation showed all 6 TRUE control rows on ADMS/BULK/BABL are rescued by observation threshold or habitat path — filter correctly wired but inactive on these WSGs.
- Phase 2c: province-wide hunt for TRUE control rows with ≥ threshold obs AND zero habitat upstream produced CAMB (11 obs), DEAD (6), LFRA (16 but too large), SALM (7). Picked DEAD — single TRUE control row at FALLS (356361749, 45743) with exactly 6 CH-group obs and zero habitat. Added DEAD to `data-raw/_targets.R`, incremental tar_make builds only comparison_DEAD + rollup (42s).
- DEAD rollup: all species within 3% of bcfishpass reference. Direct inspection of `working_dead.barrier_overrides` at (356361749, 45743): BT only, confirming per-species gate (BT bypass + CH/CM/CO/PK/SK/ST blocked). Commit fb8a0db.
- Log files committed (1c683e3): 20260423_01_phase2, _02_phase2a, _03_phase2b, _04_repro, _05_dead, _06_repro_dead.
- 5-WSG rebuild reproducibility confirmed: two consecutive `tar_destroy + tar_make` produce rollup digest `210c3f8254c47ac88573a80d96a2701e`, 46 rows, identical.
- Phase 4 (f52dcbc): NEWS 0.6.0, DESCRIPTION 0.5.0→0.6.0, research doc (DEAD table + key-fixes row + three-part-fix subsection + DAG update), vignette (5-WSG narrative + pivot column), bcfishpass config README updated, vignette artifacts regenerated.
- Follow-up filed: #46 (migrate `.lnk_pipeline_prep_gradient()` + `.lnk_pipeline_prep_overrides()` probes to manifest-driven gating).
- Branch pushed. PR #47 opened. SRED tag `Relates to NewGraphEnvironment/sred-2025-2026#24` in body.
- Flagged in PR: commit 22ac1dd ("comms(→link): M1 verified as R-worker host") landed on this branch from a parallel session's branch-landing policy; orthogonal to #44 scope.
