# Progress

## Session 2026-04-22
- Archived prior PWF (bcfishpass comparison — all 4 WSGs within 5%, shipped fresh 0.13.5–0.13.8)
- fresh#160 shipped: `frs_barriers_minimal()` extracts non-minimal removal into fresh 0.14.0 (merged)
- Filed link#37 (lnk_config) + link#38 (_targets.R pipeline); closed link#36 (targets supersedes CSV DAG)
- Starting link#37: config bundle loader
- Phase 1 done: relocated files under `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv, parameters_fresh.csv, overrides/), wrote config.yaml manifest + README, updated refs in R/ scripts, data-raw/, CLAUDE.md
- Next: Phase 2 — build `lnk_config()` loader + validation
