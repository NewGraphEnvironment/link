# Task Plan — link#65: lnk_config manifest/data split + crate dispatch

**Issue:** [#65](https://github.com/NewGraphEnvironment/link/issues/65)
**Branch:** `65-config-manifest-data-split`
**Target version:** v0.18.0
**SRED:** Relates to NewGraphEnvironment/sred-2025-2026#28

## Phase 1: Foundation
- [ ] Add `crate (>= 0.0.1)` to `DESCRIPTION` Imports
- [ ] Verify crate is locally installable + `crt_ingest` callable from R session
- [ ] Capture pre-refactor baseline: rollup checksum on one WSG (single-WSG pre-flight) for parity comparison
- [ ] Commit baseline PWF (this file + findings + progress)

## Phase 2: Config schema redesign
- [ ] Draft new `inst/extdata/configs/default/config.yaml` schema — `files:` map with per-entry `{path, source?, canonical_schema?}` entries
- [ ] Mirror schema to `inst/extdata/configs/bcfishpass/config.yaml`
- [ ] Decide `extends:` resolution semantics (recursive? one level? merge rules)
- [ ] Document schema in a single source-of-truth (likely the function docstring of `lnk_config`)

## Phase 3: lnk_config() slim-down (manifest-only)
- [ ] Rewrite `R/lnk_config.R` to return manifest-only object (paths, provenance, `cfg$files` entries)
- [ ] Remove `read.csv()` calls from `lnk_config()`
- [ ] Add `extends:` resolver
- [ ] Update `print.lnk_config()` to reflect manifest-only state
- [ ] Add tests: manifest loads without parsing data; extends merge works; missing/malformed configs fail loud

## Phase 4: lnk_load_overrides() — new exported function
- [ ] Implement `R/lnk_load_overrides.R` — takes `cfg`, returns named list of canonical tibbles
- [ ] Route entries with `source:` + `canonical_schema:` through `crate::crt_ingest()`
- [ ] Fall through to `read.csv()` for entries without `canonical_schema:`
- [ ] roxygen docs + runnable example (use bundled bcfishpass config)
- [ ] Add tests: dispatches via crate for registered entries; falls through for unregistered; mis-shape input fails loud

## Phase 5: Pipeline phase migration
For each phase that reads `cfg$overrides$X` or `cfg$habitat_classification`:
- [ ] `R/lnk_pipeline_load.R` — adopt `loaded` arg, replace `cfg$overrides$X`
- [ ] `R/lnk_pipeline_prepare.R` — adopt `loaded` arg, replace 4 reference points
- [ ] `R/lnk_pipeline_break.R` — adopt `loaded` arg
- [ ] `R/lnk_pipeline_classify.R` — adopt `loaded` arg
- [ ] `R/lnk_pipeline_connect.R` — adopt `loaded` arg (if it reads any data CSVs)
- [ ] `R/lnk_pipeline_species.R` — adopt `loaded` arg (wsg_species)
- [ ] `R/lnk_stamp.R` — confirm manifest-only access, no data needed
- [ ] `R/lnk_config_verify.R` — confirm manifest-only access (already provenance-driven)
- [ ] Update `data-raw/_targets.R` to call `lnk_load_overrides()` once and thread `loaded` through phases

## Phase 6: Tests + lints
- [ ] Update `tests/testthat/test-lnk_config.R` for manifest-only contract
- [ ] Update tests that mock `cfg$overrides$X` to mock `loaded$X` instead
- [ ] `devtools::test()` clean
- [ ] `lintr::lint_package()` clean

## Phase 7: End-to-end validation
- [ ] Pre-flight: single-WSG `tar_make()` on smallest WSG, confirm rollup matches pre-refactor baseline
- [ ] Full `tar_make()` on 5 WSGs × 2 configs — bit-identical rollup is the merge gate
- [ ] Reproducibility: second `tar_make()` immediately after first — bit-identical (no new non-determinism introduced)
- [ ] Stamp env versions in pipeline log

## Phase 8: Vignette + docs
- [ ] Verify `vignettes/habitat-bcfishpass.Rmd` still renders against new API
- [ ] Update CLAUDE.md if any architecture description references old API surface
- [ ] Update README example if it shows `lnk_config()` returning data frames

## Phase 9: Release
- [ ] DESCRIPTION version bump 0.17.0 → 0.18.0
- [ ] NEWS.md entry — describe the manifest/data split + crate integration in user-facing terms
- [ ] `/code-check` on staged diff before final commit
- [ ] PR with `Fixes #65` + `Relates to NewGraphEnvironment/sred-2025-2026#28`
- [ ] After merge: pull, nuke local branch, archive PWF, tag v0.18.0
