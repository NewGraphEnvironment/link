# Progress — Gradient classes: derive from parameters_fresh, optional override arg (#45)

## Session 2026-05-03

- Plan-mode exploration via Explore subagent — full surface-area mapping of both hardcodes, downstream label coupling, test scaffolding, integration points. Phases approved by user.
- Created branch `45-gradient-classes-derive-from-parameters` off main
- Scaffolded PWF baseline from issue #45 with approved phases
- Next: start Phase 1 — add `classes = NULL` parameter to `lnk_pipeline_prepare()`, thread through to internal helpers, replace hardcoded `models` list with per-species derivation
