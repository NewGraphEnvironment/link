# Task Plan — link#65: lnk_config manifest/data split + crate dispatch

**Issue:** [#65](https://github.com/NewGraphEnvironment/link/issues/65)
**Branch:** `65-config-manifest-data-split`
**Target version:** v0.18.0
**SRED:** Relates to an internal issue

## Phase 1: Foundation
- [x] Add `crate (>= 0.0.0.9000)` to `DESCRIPTION` Imports + tibble + tools
- [x] Verify crate is locally installable + `crt_ingest` callable from R session
- [x] Capture pre-refactor baseline (full 5-WSG × 2-config tar_make, 18m45s, sha256 a82de9...)
- [x] Commit baseline PWF (this file + findings + progress)

## Phase 2: Config schema redesign
- [x] Draft new `inst/extdata/configs/default/config.yaml` schema — `files:` map with per-entry `{path, source?, canonical_schema?}` entries
- [x] Mirror schema to `inst/extdata/configs/bcfishpass/config.yaml`
- [x] Decide `extends:` resolution semantics: recursive, shallow merge of files/pipeline/provenance, child overrides parent same-key
- [x] Document schema in `lnk_config()` docstring + `findings.md`

## Phase 3: lnk_config() slim-down (manifest-only)
- [x] Rewrite `R/lnk_config.R` to return manifest-only object (paths, provenance, `cfg$files` entries)
- [x] Remove `read.csv()` calls from `lnk_config()`
- [x] Add `extends:` resolver with circular-chain detection
- [x] Update `print.lnk_config()` to reflect manifest-only state
- [x] Add tests: manifest loads without parsing data; extends merge works; missing/malformed configs fail loud

## Phase 4: lnk_load_overrides() — new exported function
- [x] Implement `R/lnk_load_overrides.R` — takes `cfg`, returns named list of canonical tibbles
- [x] Route entries with `canonical_schema:` through `crate::crt_ingest()`
- [x] Fall through to `read.csv()` for entries without `canonical_schema:`
- [x] roxygen docs + runnable example
- [x] Add tests: dispatches via crate for registered entries; falls through for unregistered; mis-shape input fails loud

## Phase 5: Pipeline phase migration
- [x] `R/lnk_pipeline_load.R` — adopted `loaded` arg, replaced `cfg$overrides$X`
- [x] `R/lnk_pipeline_prepare.R` — adopted `loaded` arg, replaced 4 reference points
- [x] `R/lnk_pipeline_break.R` — adopted `loaded` arg
- [x] `R/lnk_pipeline_classify.R` — adopted `loaded` arg
- [x] `R/lnk_pipeline_connect.R` — adopted `loaded` arg
- [x] `R/lnk_pipeline_species.R` — adopted `loaded` arg
- [x] `R/lnk_stamp.R` — already manifest-only, no migration needed
- [x] `R/lnk_config_verify.R` — already manifest-only, no migration needed
- [x] Update `data-raw/compare_bcfishpass_wsg.R` to call `lnk_load_overrides()` once and thread `loaded`

## Phase 6: Tests + lints
- [x] Update `tests/testthat/test-lnk_config.R` for manifest-only contract + extends tests
- [x] Update pipeline tests to mock `loaded$X` instead of `cfg$overrides$X`
- [x] Update `test-lnk_stamp.R` and `test-lnk_config_verify.R` tempdir fixtures
- [x] `devtools::test()` — 608 passing, 0 failing (1 pre-existing sf warning unrelated)
- [x] `lintr::lint_package()` — only style/indentation lints (per repo convention)

## Phase 6.5: Crate type-cast (sibling repo, not link's PR)
- [x] Discovered crate's handler doesn't enforce schema-declared types (readr returns numeric for integer columns, breaking fwa_upstream signature dispatch)
- [x] (Aborted) hand-coded helper in handler — flagged by user as scab; superseded
- [x] (Aborted) standalone `apply_canonical_types`/`schema_apply` on local crate branch `65-schema-driven-types` (commit `6764fd9`, never pushed) — flagged by user as both jumping ahead AND violating naming convention
- [x] crate session re-implemented properly as Convention C `crt_schema_*` family + shipped v0.0.2 via crate#5 closing crate#4
- [x] link consumes v0.0.2; abandoned local branch deleted; comms thread acknowledged process slip (commit `cbada27`)

## Phase 7: End-to-end validation
- [x] Full `tar_make()` on 5 WSGs × 2 configs — digest `a82de9...` ✓ (run 1, crate 0.0.0.9000 with Claude's schema_apply)
- [x] Re-run on crate v0.0.2 (Convention C: `crt_schema_validate` + `crt_schema_apply`) — digest `a82de9...` ✓ (run 2)
- [x] Confirmed bit-identical against v0.17.0 baseline

## Phase 8: Vignette + docs
- [ ] Verify `vignettes/habitat-bcfishpass.Rmd` still renders against new API
- [x] Update CLAUDE.md to reflect new architecture (lnk_config manifest-only, lnk_load_overrides, loaded threading)
- [ ] Skim README — no edits needed unless it shows old data-frame API (uses lnk_load + frs_habitat, not affected)

## Phase 9: Release
- [x] DESCRIPTION version bump 0.17.0 → 0.18.0
- [x] DESCRIPTION crate dep bumped to `>= 0.0.2`
- [x] NEWS.md entry — describe the manifest/data split + crate integration in user-facing terms
- [x] `/code-check` on staged diff (round 1 clean; flagged pre-existing observation_exclusions column-name issue unrelated to this PR)
- [ ] Commit refactor + push
- [ ] Open PR with `Fixes #65` + `Relates to an internal issue`
- [ ] After merge: pull, nuke local branch, archive PWF, tag v0.18.0
