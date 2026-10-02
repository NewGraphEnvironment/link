# Progress — Thread fresh params_method (per-WSG cw/mad) through lnk_pipeline_classify (#286)

## Session 2026-10-01

- Plan-mode exploration — phases approved by user (method CSV per bundle; mad_m3s working-only; provenance via config_hash only)
- Created branch `286-thread-fresh-params-method-per-wsg-cw-ma` off main
- Scaffolded PWF baseline from issue #286 with approved phases
- Next: start Phase 1
- Phase 1: fresh pin -> v0.36.2 (floor 0.35.0); `lnk_preflight_fresh(required_formals=)` asserts `frs_habitat_classify(params_method)`; vignette script off `frs_db_conn()` (fresh 0.36.0 precedence flip). Code-check round 1 clean; it flagged stale text (validator/test comments citing v0.33.0, CLAUDE.md `frs_db_conn` line, a skip message), fixed in the same commit
