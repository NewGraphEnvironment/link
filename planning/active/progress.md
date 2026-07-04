# Progress — Extend PARS vignette to demonstrate accessible_km bcfp-equivalence (#226)

## Session 2026-07-04

- Cleared leftover memory-migration + run-logs onto `main` (commits `3846a3d`, `16b41aa`; pushed). Left
  `.claude/settings.local.json` uncommitted — it carries a live bcfp-tunnel password (flagged to user).
- Plan-mode exploration: 3 Explore agents (vignette / data-gen+build / API+numbers) + 1 Plan-agent review.
- Live-verified the PARS·BT roll-up numbers and the `fresh_default` pre-#223 blocker (see findings.md).
- User chose **full faithful regeneration** (re-model the stale grayling schema, not accessible-only).
- Created branch `226-vignette-accessible-km` off main; scaffolded PWF baseline with approved phases.
- Next: Phase 1 — re-model PARS default config into `fresh_default` post-#223 + `merge=TRUE` recompute,
  then the segmentation-match gate.
