# Progress

## Session 2026-04-22
- Archived prior PWF (bcfishpass comparison — all 4 WSGs within 5%, shipped fresh 0.13.5–0.13.8)
- fresh#160 shipped: `frs_barriers_minimal()` extracts non-minimal removal into fresh 0.14.0 (merged)
- Filed link#37 (lnk_config) + link#38 (_targets.R pipeline); closed link#36 (targets supersedes CSV DAG)
- Starting link#37: config bundle loader
- Phase 1 done: relocated files under `inst/extdata/configs/bcfishpass/` (rules.yaml, dimensions.csv, parameters_fresh.csv, overrides/), wrote config.yaml manifest + README, updated refs in R/ scripts, data-raw/, CLAUDE.md
- Phase 2/3 done: `lnk_config()` loader with validation, S3 print method, 9 tests (identifier, missing manifest, missing keys, missing files, custom path, bcfishpass bundle, print, override missing). All 146 link tests passing, lint clean. Added `yaml` to Imports, moved `%||%` to utils.R. pkgdown reference updated, NEWS entry, bumped to 0.2.0.
- Next: Phase 5 — update compare_bcfishpass.R to use lnk_config() instead of hardcoded paths (Phase 4 "default" bundle deferred — real departures live in #19/#20/#21)
