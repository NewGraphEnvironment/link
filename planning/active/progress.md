# Progress — lnk_pipeline_crossings: missing PSCIS↔modelled 100m-instream auto-snap layer (#154)

## Session 2026-05-11

- Plan-mode exploration — phases approved by user
- Two parallel Explore agents:
  - link pipeline_crossings flow, integration surface, lnk_crossings_union contracts
  - bcfp 04_pscis SQL fragments extraction (verbatim name_score CASE, width_order_score CASE, weighted_distance, filter)
- Confirmed: fresh v0.31.0 shipped (frs_candidates_pick + frs_point_match composable for byte-identical bcfp parity)
- Confirmed: `frs_point_match` NOT used in this composition — modelled_xing_dist_instream is computed inline in the candidates table because `weighted_distance` (per-PSCIS scoring tiebreak) depends on it. Order matters for byte-identical.
- Created branch `154-lnk-pipeline-crossings-missing-pscis-mod` off main (v0.33.0)
- Scaffolded PWF baseline with approved phases
- Plan file: `/Users/airvine/.claude/plans/snuggly-fluttering-hopper.md`
- Next: start Phase 1 — pin DESCRIPTION + write `R/lnk_pipeline_pscis_build.R`

## Session 2026-05-11 (Phase 1.5)

- Diagnosed BULK/WILL drift after initial Phase 1 commit (`93083da`).
- Identified three additional bcfp-parity gaps (see findings.md):
  1. `crossing_fixes.structure` filter missing in modelled branch of `.lnk_crossings_union`
  2. DBSCAN 5m + UNIQUE(blk,drm) dedup missing in `.lnk_pipeline_pscis_build`
  3. xref-precedence: bcfp excludes xref-mapped from snap path then inserts via xref-driven branches
- Implemented all three. Phase A results jumped to ≥99% on ADMS/BULK/WILL (all species).
- Next: code-check, commit Phase 1.5, then Phase 2 (tests).

## Session 2026-05-11 (Phase 2)

- Rewrote `test-lnk_pipeline_crossings.R` to mock `.lnk_pipeline_pscis_build` instead of `lnk_points_snap`; verifies snap_tolerance clamp to >= 150 (bcfp parity).
- Rewrote stale xref-presence tests in `test-lnk_crossings_union.R` to probe for `<schema>.crossing_fixes` (Phase 1.5 added a structure-filter that gates on its presence).
- Added `test-lnk_pipeline_pscis_build.R` covering: 5-step SQL composition (each step's key markers), xref-staging branch (loaded vs DB-only), Step 5 skip when xref absent, argument validation.
- Full suite: 962 PASS / 0 FAIL.

## Session 2026-05-11 (Phase 3)

- Phase A re-run executed during Phase 1.5 (post-fix v7 log already on disk).
- Updated `research/bcfp_compare_mapping_code.md` Status section: replaced "ready to ship" framing with shipped numbers; added Phase A post-link#154 sub-section preserving the 2026-05-10 baseline for history.
- Acceptance bar met: ≥99% on every in-WSG species across ADMS, BULK, WILL, PARS. PARS BT 60% deferred to link#152.
