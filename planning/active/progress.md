# Progress

## Session 2026-04-23 — #46 kickoff

- PR #49 merged as link 0.7.0 (squash `5cbd75d`). Tag `v0.7.0` pushed.
- Archived #48 PWF under `planning/archive/2026-04-23-user-barriers-definite-bypass/`.
- Branched `46-manifest-driven-probes` off main.
- Scope: replace two `information_schema.tables` probes with direct `cfg$...` checks. Pure refactor, no behavior change, rollup must be bit-identical to post-#48 (`50908d234e2131fc0842dc3ab653ae78`).
- Next: Phase 1 code — add `cfg` to `.lnk_pipeline_prep_gradient()` signature + manifest check, replace probe in `.lnk_pipeline_prep_overrides()` with manifest check.
