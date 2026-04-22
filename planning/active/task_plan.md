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

- [x] Write `R/lnk_config.R` — the loader, returns `lnk_config` S3 list
- [x] Implement manifest validation (missing files, wrong keys, bad CSVs)
- [x] Define the return list slot names and types
- [x] Runnable example showing inspection of the loaded object
- [x] Add `yaml` to DESCRIPTION Imports
- [x] Move `%||%` helper into `R/utils.R`

## Phase 3: Tests

- [x] Unit tests: identifier validation, missing manifest, missing referenced file, missing required keys, missing required files entries
- [x] Integration tests: load `"bcfishpass"` via name, via path, return shape checks, print method
- [x] Full test suite green (146 / 146 passing)

## Phase 4: Seed default variant (DEFERRED)

Deferred — the `default` variant belongs in its own PR where real departures from bcfishpass are added (intermittent streams, saner spawn gradient min, expanded lake rearing). Tracked in #19, #20, #21. An empty clone adds no value.

## Phase 5: Wire into compare script

- [x] Update `data-raw/compare_bcfishpass.R` to call `lnk_config("bcfishpass")` instead of hardcoded paths
- [x] Parse-check passes
- [ ] Run BULK end-to-end to verify byte-identical output (deferred — sanity check only; no structural changes, just path source)

## Phase 6: Docs + release

- [x] Roxygen examples (runnable + `\dontrun{}` for pipeline wiring)
- [x] pkgdown reference entry (`_pkgdown.yml`)
- [x] NEWS.md entry
- [x] Bump to 0.2.0
- [x] `/code-check` on staged diff — one real issue found (name-shadowing foot-gun), fixed + regression test added
- [ ] PR with SRED tag (NewGraphEnvironment/sred-2025-2026#24) — Fixes #37

## Versions at start

- fresh: 0.14.0 (just merged — adds frs_barriers_minimal)
- link: main (0.1.0, target 0.2.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
