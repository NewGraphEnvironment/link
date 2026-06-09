# Progress — lnk_pipeline_run: produce streams_access regardless of mapping_code (#218)

## Session 2026-06-08

- Plan-mode exploration — phases approved by user
- Created branch `218-lnk-pipeline-run-produce-streams-access-` off main
- Scaffolded PWF baseline from issue #218 with approved phases
- Verified vignette safety (cached-artifact render; mapping_code=TRUE byte-identical)
- Next: start Phase 1 — hoist access out of the mapping_code gate in `R/lnk_pipeline_run.R`
