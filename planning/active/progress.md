# Progress — lnk_pipeline_run: produce streams_access regardless of mapping_code (#218)

## Session 2026-06-08

- Plan-mode exploration — phases approved by user
- Created branch `218-lnk-pipeline-run-produce-streams-access-` off main
- Scaffolded PWF baseline from issue #218 with approved phases
- Verified vignette safety (cached-artifact render; mapping_code=TRUE byte-identical)
- Phase 1 — hoisted `lnk_presence`, `barriers_per_sp`, pre-persist, `lnk_barriers_views`,
  `lnk_pipeline_access` out of the `if (isTRUE(mapping_code))` gate; only `lnk_mapping_code`
  token assembly stays gated. Updated roxygen (phase 10a/10b, `@param mapping_code`) + re-`document()`.
- Phase 2 — rewrote "composes phases in expected order" (new order: …barriers_unify, presence,
  persist, barriers_views, access, persist); added "builds access for both mapping_code values,
  gates lnk_mapping_code" test; added access-path mocks to dams + cleanup tests. 20 PASS in file.
- Phase 1+2 atomic commit `681c7bd` (code + roxygen + Rd + tests + checkbox flips).
- Phase 3 — `/code-check` clean (3 rounds, 0 findings); `buildVignettes` exit 0;
  test-lnk_pipeline_run.R 20 PASS. NEWS 0.43.0 entry + DESCRIPTION bump 0.42.0→0.43.0.
- Next: `/planning-archive` → `/gh-pr-push` (PR body: `Closes #218`, SRED tag).
