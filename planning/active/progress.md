# Progress — lnk_habitat_validate() scores mad watershed groups as if they were cw (#299)

## Session 2026-10-02

- Plan-mode exploration — phases approved by user (labels kept + `model`/`mad_m3s` columns; new `no_mad_threshold` reason)
- Created branch `299-lnk-habitat-validate-scores-mad-watersh` off main
- Scaffolded PWF baseline from issue #299 with approved phases
- Next: start Phase 1

- Phase 1: `.lnk_habitat_method_read()` + `.lnk_wsg_model()` (fresh's `.frs_habitat_models()` via getFromNamespace); classify routed through them. 232 tests pass across config/classify/preflight.
- Code-check Phase 1: round 1 Clean (`review-p1-round1.md`). Rounds 2-3 deliberately folded into the Phase 2-3 review, which reviews the branch diff including this one.
