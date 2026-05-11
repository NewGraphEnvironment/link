# Task: lnk_pipeline_crossings: missing PSCIS↔modelled 100m-instream auto-snap layer (#154)

`lnk_pipeline_crossings` v0.32.0 carries the PSCIS↔modelled crossing linkage **only from the xref CSV** (`pscis_modelledcrossings_streams_xref`). It's missing bcfp's automatic 100m-instream snap layer that produces the bulk of PSCIS↔modelled linkages.

Wires the 3-step fresh primitive composition (`frs_point_snap` + `frs_candidates_pick` + bcfp-shape SQL) into `lnk_pipeline_crossings` as a new private helper `.lnk_pipeline_pscis_build`. Reproduces bcfp's `02_pscis_streams_150m.sql` + `04_pscis.sql` byte-identically. See `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md` for the full algorithm + critical-files table.

## Phase 1: scaffold + DESCRIPTION + write `.lnk_pipeline_pscis_build`

- [ ] DESCRIPTION: pin `Remotes: NewGraphEnvironment/fresh@v0.31.0` and bump Suggests `fresh (>= 0.31.0)`. Reinstall fresh from local source if not already on the system.
- [ ] Write `R/lnk_pipeline_pscis_build.R` (new private helper):
  - Signature: `.lnk_pipeline_pscis_build(conn, aoi, schema, snap_num_features = 5L, snap_tolerance = 150L)`
  - Implements Steps 1-5 from the plan (multi-stream snap → enrich + score → b-side dedup UPDATE → frs_candidates_pick → xref overrides).
  - Step 2 SQL embedded verbatim from bcfp (name_score CASE + width_order_score CASE).
  - Returns `invisible(conn)`.
  - Roxygen: `@noRd` (private), `@family pipeline`.
- [ ] Update `R/lnk_pipeline_crossings.R`:
  - Replace `lnk_points_snap(...)` call with `.lnk_pipeline_pscis_build(...)`.
  - Update roxygen: PSCIS branch now uses bcfp-shape snap-pick-match chain.
- [ ] Update `R/lnk_crossings_union.R`:
  - PSCIS branch reads `<schema>.pscis` instead of `<schema>.pscis_assessment_snapped`.
  - Modelled-branch xref-exclusion reads `<schema>.pscis.modelled_crossing_id` instead of the xref staging table directly.
- [ ] `devtools::document()` to regenerate man/ + NAMESPACE
- [ ] `lintr::lint("R/lnk_pipeline_pscis_build.R")` + `R/lnk_pipeline_crossings.R` clean

## Phase 2: tests

- [ ] New `tests/testthat/test-lnk_pipeline_pscis_build.R`:
  - Mocked tests for the SQL composition (each of Steps 1-5).
  - Live test against bcfp tunnel ADMS: produce `<schema>.pscis`, diff vs `bcfishpass.pscis.modelled_crossing_id` for ADMS → expect 60/60 or better.
- [ ] Update `tests/testthat/test-lnk_pipeline_crossings.R`:
  - Replace the `lnk_points_snap` expectation with `.lnk_pipeline_pscis_build`.
  - Keep the end-to-end smoke test on ADMS — should still hold or improve.
- [ ] Keep `tests/testthat/test-lnk_points_snap.R` as-is — `lnk_points_snap` stays exported for other use cases.

## Phase 3: live Phase A mapping_code parity re-run

- [ ] Re-run `data-raw/compare_bcfp_mapping_code.R --wsgs=ADMS,BULK,WILL` (and PARS for completeness).
- [ ] Acceptance: ≥99% on all species in ADMS, BULK, WILL — incl. spawn-only species (cm, pk).
- [ ] PARS BT may stay at ~56% (cross-WSG dam_dnstr, link#152 deferred). Documented as expected.
- [ ] Update `research/bcfp_compare_mapping_code.md` Status section with the new numbers.

## Phase 4: release

- [ ] DESCRIPTION 0.33.0 → 0.34.0 (minor — modifies pipeline behavior, no new exports but user-facing semantics change).
- [ ] NEWS.md 0.34.0 entry covering: 3-step composition with fresh primitives, BULK/WILL parity jump, what changed in `lnk_pipeline_crossings`.
- [ ] `devtools::check()`: 0 errors / pre-existing notes/warnings only.
- [ ] `/planning-archive` + `/gh-pr-push` to open PR closing #154.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
