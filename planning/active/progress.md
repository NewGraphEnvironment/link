# Progress — Gradient classes: derive from parameters_fresh, optional override arg (#45)

## Session 2026-05-03

- Plan-mode exploration via Explore subagent — full surface-area mapping of both hardcodes, downstream label coupling, test scaffolding, integration points. Phases approved by user.
- Created branch `45-gradient-classes-derive-from-parameters` off main
- Scaffolded PWF baseline from issue #45 with approved phases
- Phase 1 complete — `classes` override threaded through `lnk_pipeline_prepare()` → `.lnk_pipeline_prep_gradient()` and `.lnk_pipeline_prep_minimal()`. `models` list replaced with per-species derivation from `loaded$parameters_fresh$access_gradient_max`. New helpers `.lnk_classes_bcfp` (default vector) + `.lnk_resolve_classes()` (caller → cfg → default fallback). 5 new tests + 2 existing tests updated. Code-check 2 rounds: round 1 caught 3 fragile issues (empty species → empty table fallback; defensive `sp_amax[1L]` for R 4.3+ length-1 `||` enforcement; identifier validation on species codes); round 2 clean.
- Next: Phase 2 — config knob `cfg$pipeline$gradient_classes` documented in bundle config.yaml files
