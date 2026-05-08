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
- Phase 4 done (out of order — easier to ship before the heavier Phase 2 union): `lnk_barriers_emit(conn, schema)` shipped. 22 expectations covering all 5 tables, semantic filters, validation.
- Full suite: 856 PASS / 0 FAIL. Lints clean.
- All three EXPORTED utilities (Phases 0, 1, 4) shipped: `lnk_inputs_verify`, `lnk_points_snap`, `lnk_barriers_emit`. Issue is now purely about composing them via the crossings-specific internal helpers (Phases 2+3) + Phase 5 parity.
- Next: Phase 2 — port the source-precedence STRUCTURE (PSCIS > PSCIS-on-modelled > CABD > modelled) from `bcfishpass/model/01_access/sql/load_crossings.sql`, but emit ONLY the lean column set needed by `lnk_barriers_emit()` (id, source, feature_type, statuses, dam_name, network position + geom). Skip road tenure / FTEN / OGC / rail metadata — those feed bcfp's downstream non-barrier consumers, which we don't reproduce.

## Parked 2026-05-08

- Branch `138-lnk-pipeline-crossings-build-slim-fresh-` pushed with Phases 0+1+4 done. PWF preserved here.
- Switching to #137 (snapshot script) so Phase 5 (parity verification) can validate Phase 2+3 against a real DB once we resume.
- Resume: `git checkout 138-lnk-pipeline-crossings-build-slim-fresh-`.

## Resumed 2026-05-08 (after #137 v0.31.1 ship)

- Branch rebased onto v0.31.1 main.
- Snapshot script run on local fwapg loaded 6 of 7 tables (PSCIS×4 + cabd.dams + fresh.modelled_stream_crossings). Observations parquet failed via Arrow FID-type error → tracked at rtj#66.
- Phase 2 done: `.lnk_crossings_union(conn, schema, aoi)` shipped — lean column union of PSCIS + CABD + modelled with ID-space offsets per bcfp. xref-presence detected via information_schema.
- Phase 3 done: `.lnk_crossings_apply_overrides(conn, schema)` shipped — applies pscis_fixes + crossing_fixes (with +1e9 modelled-ID offset in the JOIN). No-op when fix tables absent.
- Phase 5 done: `lnk_pipeline_crossings(conn, aoi, cfg, loaded, schema, snap_tolerance)` shipped — exported umbrella composing all five steps.
- Full suite: 902 PASS / 0 FAIL. Lints clean.
- Next: Phase 6 (live ADMS smoke against the loaded DB).
