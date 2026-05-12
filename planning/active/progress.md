# Progress — lnk_compare_wsg + provincial parity annotated CSV (#162)

## Session 2026-05-12

- Plan-mode exploration — phases approved by user.
- Created branch `162-lnk-compare-wsg-annotated-csv` off main.
- Scaffolded PWF baseline from #162 with approved phases.
- Driving motivation: zero rows ≥2% divergence end up "unexplained" — every divergence either maps to a known class (A/B/C/D/measurement asymmetry/intentional) or is flagged for investigation. Single CSV ties together rollup + mapping_code lenses + taxonomy.
- Next: start Phase 1 — `R/lnk_compare_wsg.R` rollup-only path.
