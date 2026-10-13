# Progress — Record source-artifact identity for the DB primitives (#265)

## Session 2026-10-12

- Plan-mode exploration — phases approved by user (#270 separate; log_input carriage; kind = object/api/derived)
- Created branch `265-record-source-artifact-identity-for-the` off main
- Scaffolded PWF baseline from issue #265 with approved phases
- Next: start Phase 1

- Phases 1-2: the dictionary gains `kind` / `url` (12 primitives). New `R/lnk_artifact.R`: DDL, `.lnk_artifact_head()` (never errors), `lnk_artifact_record()` (URL guard against the dictionary; a probe never overwrites a loader row), `lnk_artifact_probe()`, `lnk_artifact_read()`. `test-lnk_artifact.R`: 55 pass, with a live DB test of the probe/loader rule. Mutation: removing the WHERE guard fails 2 tests; restored.
