# Task: lnk_pipeline_crossings: missing PSCIS↔modelled 100m-instream auto-snap layer (#154)

`lnk_pipeline_crossings` v0.32.0 carries the PSCIS↔modelled crossing linkage **only from the xref CSV** (`pscis_modelledcrossings_streams_xref`). It's missing bcfp's automatic 100m-instream snap layer that produces the bulk of PSCIS↔modelled linkages.

Wires the 3-step fresh primitive composition (`frs_point_snap` + `frs_candidates_pick` + bcfp-shape SQL) into `lnk_pipeline_crossings` as a new private helper `.lnk_pipeline_pscis_build`. Reproduces bcfp's `02_pscis_streams_150m.sql` + `04_pscis.sql` byte-identically. See `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md` for the full algorithm + critical-files table.

## Phase 1: scaffold + DESCRIPTION + write `.lnk_pipeline_pscis_build`

- [x] DESCRIPTION: pin `Remotes: NewGraphEnvironment/fresh@v0.31.0` and bump Suggests `fresh (>= 0.31.0)`.
- [x] Write `R/lnk_pipeline_pscis_build.R` (new private helper, 5 steps).
- [x] Update `R/lnk_pipeline_crossings.R` — replace `lnk_points_snap` call with `.lnk_pipeline_pscis_build`.
- [x] Update `R/lnk_crossings_union.R` — PSCIS branch reads `<schema>.pscis`; modelled-branch xref-exclusion reads `<schema>.pscis.modelled_crossing_id`.
- [x] Extended `lnk_points_snap` with `num_features` arg (backward-compatible).
- [x] **Bug fix in `lnk_points_snap`**: the previous `downstream_route_measure = ST_LineLocatePoint * ST_Length` formula computed position WITHIN the segment, not absolute drm on the blue line. Added segment offset `+ s.downstream_route_measure` and `s.length_metre` instead of `ST_Length(s.geom)`, with `GREATEST/LEAST/FLOOR/CEIL` clamping per bcfp's pattern. This fix is what made ADMS jump from 15/60 to 60/60 byte-identical for PSCIS-modelled linkage.
- [x] `devtools::document()` regenerated.
- [x] `lintr::lint` clean on all touched files.

## Phase 1.5: BULK/WILL parity follow-on fixes (post-baseline)

Initial Phase 1 results showed ADMS 99-100% but BULK 79-86%, WILL 95-98%. Diagnostic dive revealed three additional bcfp-parity gaps not in the original plan:

- [x] **Modelled-branch `crossing_fixes` filter** in `.lnk_crossings_union`: bcfp drops modelled crossings where `user_modelled_crossing_fixes.structure NOT IN (NULL, 'OBS')` entirely (`load_crossings.sql:634`). Without this filter, 275 NONE-fixed modelled crossings leaked through in BULK, 103 in WILL. Closed WILL gap from 95% → 97-98%.
- [x] **DBSCAN 5m spatial dedup + UNIQUE(blk,drm) dedup** in `.lnk_pipeline_pscis_build`: bcfp's `clusters AS ... ST_ClusterDBSCAN(geom, 5, 1)` + `DISTINCT ON (cid)` step. Implemented as `DELETE … WHERE NOT IN winners` after Step 4b.
- [x] **xref-precedence restructure** in `.lnk_pipeline_pscis_build`: bcfp excludes xref-mapped `stream_crossing_id`s from the snap path entirely, then inserts them via xref-driven INSERT (referenced_modelled_xing + referenced_streams branches). xref entries with stale `modelled_crossing_id` (no longer in `modelled_stream_crossings`) silently drop via INNER JOIN — that's the bcfp parity behavior we now match. **This was the dominant BULK gap**: 88 xref-mapped PSCIS leaked through snap and we kept them. Closed BULK to 99.17-99.78%.

**Phase A results post-fixes:** ADMS 99.0-100%, BULK 99.17-99.78%, WILL 98.85-99.93%, PARS 100% (except BT 60.64%, cross-WSG dam_dnstr — link#152).

## Phase 2: tests

- [x] New `tests/testthat/test-lnk_pipeline_pscis_build.R`:
  - Mocked tests for the SQL composition (each of Steps 1-5).
  - Live test against bcfp tunnel ADMS: produce `<schema>.pscis`, diff vs `bcfishpass.pscis.modelled_crossing_id` for ADMS → expect 60/60 or better.
- [x] Update `tests/testthat/test-lnk_pipeline_crossings.R`:
  - Replace the `lnk_points_snap` expectation with `.lnk_pipeline_pscis_build`.
  - Keep the end-to-end smoke test on ADMS — should still hold or improve.
- [x] Keep `tests/testthat/test-lnk_points_snap.R` as-is — `lnk_points_snap` stays exported for other use cases.

## Phase 3: live Phase A mapping_code parity re-run

- [x] Re-run `data-raw/compare_bcfp_mapping_code.R --wsgs=ADMS,BULK,WILL` (and PARS for completeness).
- [x] Acceptance: ≥99% on all species in ADMS, BULK, WILL — incl. spawn-only species (cm, pk).
- [x] PARS BT may stay at ~56% (cross-WSG dam_dnstr, link#152 deferred). Documented as expected.
- [x] Update `research/bcfp_compare_mapping_code.md` Status section with the new numbers.

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
