# Progress — lnk_pipeline_crossings (#138)

## Session 2026-05-08

- Plan-mode exploration completed. Naming conventions locked: `lnk_inputs_verify`, `lnk_points_snap`, `lnk_barriers_emit` (verb-last; mirrors `lnk_baseline_*` family).
- Config-driven defaults: `parameters_fresh.csv` will carry `snap_tolerance_default` + `snap_edge_types_exclude` rows.
- Branch `138-lnk-pipeline-crossings-build-slim-fresh-` created off main (4cb2269).
- Confirmed bchamp public artifact comes out of bcfp DB during Tue rebuild (Simon's `model_00_stream_crossings`).
- Confirmed CABD public API URL: `https://cabd-web.azurewebsites.net/cabd-api/features/dams?filter=province_territory_code:eq:bc&filter=use_analysis:eq:true`.
- Phase 0 done: `lnk_inputs_verify(conn, required)` shipped. 9 mocked test expectations.
- Phase 1 done: `lnk_points_snap(conn, table_in, table_out, ...)` shipped — bulk lateral-KNN snap, defaults 100m / exclude_edge_types=1425L, configurable. 17 test expectations.
- Full suite: 834 PASS / 0 FAIL. Lints clean.
- Next: Phase 2 — port `bcfishpass/model/01_access/sql/load_crossings.sql` source-precedence union to `.lnk_crossings_union()`.
