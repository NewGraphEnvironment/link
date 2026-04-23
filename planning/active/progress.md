# Progress

## Session 2026-04-23

- Archived `2026-04-23-targets-pipeline/` — link#38 closed via PRs #41/#42/#43. Three consecutive `tar_make()` runs produced bit-identical rollups. All species within 5% of bcfishpass reference on all four WSGs.
- Branched `44-barriers-definite-control` off main.
- Plan approved. PWF initialized for #44.
- Pre-flight complete: identified the `ctrl_filter` bug in `lnk_barrier_overrides` (all rows block, not just `barrier_ind = TRUE`), and confirmed `.lnk_pipeline_prep_overrides` doesn't pass `control`. Same PR fixes both — filter semantics + missing pass-through.
- Next: Phase 1 — fix `R/lnk_barrier_overrides.R` `ctrl_filter` and add `tests/testthat/test-lnk_barrier_overrides.R`.
