# Progress: Recompute: test existence instead of building natural-barrier arrays, and walk each barrier set once (#394)

## Session 2026-10-28

- Plan-mode exploration; phases approved by user (fold #409 in; lever 2 measured before it is built)
- Created branch `394-recompute-test-existence-instead-of-buil` off main
- Scaffolded PWF baseline from issue #394 with approved phases
- Next: start Phase 1
- Phase 1: pinned fresh v0.47.0, preflight asserts `frs_network_features(result)`, wrote measure.R
- Phase 2: lever 1 in `lnk_pipeline_access()`, four mocked tests; mutating the mode to all-`ids` fails three of them and to all-`exists` fails three (one shared). Tests run on fresh 0.47.0 from a scratch library.
- Plan review delivered (`review-plan.md`); round 1 stopped at 03:12 for the collision it found, measure.R moved to its own scoped table, model_digest.R written for #409's per-table check. Round 1 relaunched 03:15 UTC.
- Lever-2 gate, 2026-10-29 04:08 UTC (SALR, CHWK, LFRA at `exists`; SETN still running): repeated species walks are 55.0 % of walk seconds (CHWK 0.575, LFRA 0.571, SALR 0). Gate passed, lever 2 committed. Mutations of it (keys ignored, one key for all, `concat_ws` instead of record text, no admissibility scope, no `watershed_group_code`) each turn a named test red.
