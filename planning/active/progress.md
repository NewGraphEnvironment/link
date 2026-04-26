# Progress — v0.10.0 spawn edge_types tightening

## Session 2026-04-24

- Created branch `10-spawn-edge-types-explicit` off `main` (post v0.9.0 merge)
- PWF baseline: `task_plan.md`, `findings.md`, `progress.md` written
- Plan revised from "add new `spawn_edge_types_explicit` column" to
  "switch default config to existing `edge_types = "explicit"` mode" —
  much simpler, achieves the same end state, infrastructure already exists
- Verified bcfishpass config already uses `explicit`; default config uses
  `categories`. Switching the default's `data-raw/build_rules.R` call is
  the entire code change.
- Next: Phase 2 — flip `data-raw/build_rules.R` to `edge_types = "explicit"`
  for both default YAMLs, regenerate, verify diff.
