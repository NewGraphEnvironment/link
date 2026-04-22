# Task Plan: lnk_config() config bundle loader (#37)

## Goal

Create a config abstraction so pipeline variants (bcfishpass validation, newgraph defaults, min-spawn, channel-type-first breaking) stop being copy-paste script forks. Each variant = a directory under `inst/extdata/configs/<name>/` bundled with rules YAML, dimensions CSV, parameters, wsg_species_presence, observation_exclusions, and override CSVs. `lnk_config(name_or_path)` loads the bundle into one list object.

Unblocks `_targets.R` (link#38).

## Phase 1: Directory layout + move existing files

- [x] Design `config.yaml` manifest schema (which files go where, required vs optional)
- [x] Create `inst/extdata/configs/bcfishpass/` directory
- [x] Move existing bcfishpass files into it (rules, dimensions, parameters_fresh, wsg_species, observation_exclusions, overrides)
- [x] Write `inst/extdata/configs/bcfishpass/config.yaml` manifest
- [x] Write `inst/extdata/configs/bcfishpass/README.md` describing the variant
- [x] Verify no broken references — grep for old paths across the repo (R scripts, data-raw, CLAUDE.md)

## Phase 2: Loader function

- [ ] Write `R/lnk_config.R` — the loader, returns `lnk_config` S3 list
- [ ] Implement manifest validation (missing files, wrong keys, bad CSVs)
- [ ] Define the return list slot names and types
- [ ] Runnable example showing inspection of the loaded object

## Phase 3: Tests

- [ ] Unit tests: identifier validation, missing manifest, missing referenced file, invalid yaml, missing column in a CSV
- [ ] Integration tests: load `"bcfishpass"` via name, via path, return shape checks
- [ ] Full test suite green

## Phase 4: Seed default variant

- [ ] Create `inst/extdata/configs/default/` initially as a clone of bcfishpass
- [ ] README describing the intent (newgraph-defaults variant — real departures tracked in #19, #20, #21)
- [ ] Loader works on both

## Phase 5: Wire into compare script

- [ ] Update `data-raw/compare_bcfishpass.R` to call `lnk_config("bcfishpass")` instead of hardcoded paths
- [ ] Run BULK (or subset) to verify identical output
- [ ] Commit verification log under `data-raw/logs/`

## Phase 6: Docs + release

- [ ] Roxygen examples
- [ ] pkgdown reference entry (`_pkgdown.yml`)
- [ ] NEWS.md entry
- [ ] Bump to 0.2.0
- [ ] `/code-check` on staged diff before each commit
- [ ] PR with SRED tag (NewGraphEnvironment/sred-2025-2026#24) — Fixes #37

## Versions at start

- fresh: 0.14.0 (just merged — adds frs_barriers_minimal)
- link: main (0.1.0, target 0.2.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
