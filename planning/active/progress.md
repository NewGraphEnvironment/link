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
