# Progress — lnk_pipeline_crossings (#138)

## Session 2026-05-08

- Plan-mode exploration completed. Naming conventions locked: `lnk_inputs_verify`, `lnk_points_snap`, `lnk_barriers_emit` (verb-last; mirrors `lnk_baseline_*` family).
- Config-driven defaults: `parameters_fresh.csv` will carry `snap_tolerance_default` + `snap_edge_types_exclude` rows.
- Branch `138-lnk-pipeline-crossings-build-slim-fresh-` created off main (4cb2269).
- Confirmed bchamp public artifact comes out of bcfp DB during Tue rebuild (Simon's `model_00_stream_crossings`).
- Confirmed CABD public API URL: `https://cabd-web.azurewebsites.net/cabd-api/features/dams?filter=province_territory_code:eq:bc&filter=use_analysis:eq:true`.
- Next: Phase 0 — `lnk_inputs_verify()` exported helper + tests.
