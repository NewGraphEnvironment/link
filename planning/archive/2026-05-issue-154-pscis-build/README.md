## Outcome

`lnk_pipeline_crossings()` now reproduces bcfp's PSCIS-to-modelled auto-snap layer byte-identically via a new private helper `.lnk_pipeline_pscis_build` (composes `lnk_points_snap(num_features = 5L)` + `fresh::frs_candidates_pick` + bcfp-shape scoring/dedup SQL). Phase A mapping_code parity jumped: BULK ~80% → ~99.5%, WILL ~86% → ~99.7%, ADMS held at 99-100%, PARS BT 60% deferred to link#152 (cross-WSG `dam_dnstr`).

Three Phase 1.5 follow-on fixes were uncovered during diagnostic dive and shipped alongside the headline change: (1) modelled-branch `crossing_fixes.structure NOT IN (NULL,'OBS')` filter in `.lnk_crossings_union` (bcfp parity with `load_crossings.sql:634`); (2) DBSCAN 5m + UNIQUE(blk,drm) spatial dedup after `frs_candidates_pick`; (3) xref-precedence restructure where xref-mapped stream_crossing_ids are excluded from the snap path and inserted via a two-branch UNION ALL mirroring bcfp's `referenced_modelled_xing` + `referenced_streams` CTEs — this was the dominant BULK gap (88 xref-mapped PSCIS leaking through snap). Also a one-line bug fix in `lnk_points_snap`'s `downstream_route_measure` formula (was computing within-segment position; now adds segment offset and clamps with `GREATEST/LEAST/FLOOR/CEIL` per bcfp).

Closed by: Release v0.34.0 (commit 93a97c2) / PR #TBD
