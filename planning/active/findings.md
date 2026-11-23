# Findings — Backlog move 10: Crossings: snapping, and habitat upstream of each crossing (#478)

## Issue context

**If we do it:** points snap by one rule and never to placeholder lines, and each crossing's upstream habitat is summed over its whole network and checked against bcfishpass. **If we never do:** a crossing's upstream habitat misses every tributary.

Move 10 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 14: Snapping

**Why here:** one re-snap, then a re-model of both configs.

#313 (`lnk_points_snap()` can snap to placeholder `999` segments: `<@` rather than `!=`), #314 (wrap or retire it in favour of `fresh::frs_point_snap()`) and #383 (fwapg's tie rule and stream-head fix across the `FWA_LocateAlong` callers, with a sweep and live tests). Touches `R/lnk_points_snap.R`, `R/lnk_pipeline_pscis_build.R`, `R/lnk_barriers_unify.R`, `data-raw/query_habitat_thresholds_obs.R`, tests. Gate: wrap or retire; the tie rule waits on NewGraphEnvironment/fwapg#41 (NewGraphEnvironment/fwapg#45 is the locate twin). One re-snap, then a re-model of both configs.

| issue | title |
|---|---|
| #313 | lnk_points_snap() can snap to placeholder (999.*) stream segments |
| #314 | lnk_points_snap(): wrap or retire in favour of the bulk fresh::frs_point_snap() |
| #383 | lnk_points_snap() and FWA_LocateAlong callers: fwapg's tie rule and stream-head fix, with a sweep and live tests |

## Batch 15: Habitat upstream of each crossing

**Why here:** one live parity against bcfishpass's crossings.

#321 (per-crossing upstream habitat per species on `fresh::frs_aggregate()`, checked against bcfishpass), #232 (link-built crossings against bcfishpass's complete crossings table) and #356 (float length sums depend on row order in the threshold scripts and `lnk_aggregate()`). Touches `R/lnk_aggregate.R`, `data-raw/query_habitat_thresholds_obs.R`, `data-raw/query_habitat_thresholds_mad.R`, a crossings parity script, `research/bcfishpass_parity.md`. No gate. One live parity against bcfishpass's crossings.

| issue | title |
|---|---|
| #321 | Per-crossing upstream habitat per species, checked against bcfishpass, on frs_aggregate() |
| #232 | Confirm link-built crossings match bcfp's complete crossings table (parity) |
| #356 | Floating-point length sums depend on row order (threshold logs, lnk_aggregate) |



## Exploration (2026-11-22)

- fresh v0.55.1 `frs_point_snap()` already orders ties `distance, measure DESC, linear_feature_id` (fresh#266 closed), excludes 999.* and NULL localcodes; `frs_migration_trial()`, `frs_aggregate()` exported.
- Local fwapg `fwa_indexpoint()` args: `point, tolerance, num_features` (pre-fwapg#41). fwapg checkout holds `202610240132__indexpoint_tiebreak.sql`.
- `lnk_points_snap()` ties on lowest `linear_feature_id` (R/lnk_points_snap.R:187); guard `!= 999` at :96.
- `lnk_aggregate()` has no caller in R/ or data-raw/; same-line join at R/lnk_aggregate.R:160-167.
