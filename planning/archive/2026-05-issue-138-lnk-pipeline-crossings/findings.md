# Findings — lnk_pipeline_crossings (#138)

## Issue context

Issue #138 in NewGraphEnvironment/link. Title: "lnk_pipeline_crossings: build slim fresh.crossings + barriers_* from PSCIS + CABD + modelled artifact". Phase B of the self-sufficiency roadmap (link#117 + db_newgraph#4 shipped Phase A).

## Architecture

```
                    PSCIS              CABD            bchamp gpkg            override CSVs
                  (BCDC public)      (CABD public)    (objectstore)          (s3://fresh-bc)
                       |                  |                  |                       |
                       v                  v                  v                       v
              [ Python bcdata ]      [ ogr2ogr        [ curl + ogr2ogr ]      [ lnk_pipeline_load ]
                bc2pg                  geojson API ]                            sources from S3
                                                                                  (#117)
                       |                  |                  |                       |
                       +------------------+------------------+-----------------------+
                                          |
                                          v
                     ##  #137 snapshot script loads all primitives ##
                                          |
                                          v
                          [ whse_fish.pscis_*       <schema>.crossing_fixes
                            cabd.dams              <schema>.pscis_fixes
                            <schema>.modelled_stream_crossings ]
                                          |
                                          v
                  [ lnk_pipeline_prepare(conn_tunnel = conn) ] -- builds <schema>.dams
                                          |
                                          v
                  [ lnk_pipeline_crossings(conn, aoi, ...) ]   <-- THIS ISSUE
                                          |
                                          v
                          <schema>.crossings (full, source-precedence)
                          <schema>.crossings_lookup (slim id + status)
                          <schema>.barriers_anthropogenic
                          <schema>.barriers_pscis
                          <schema>.barriers_dams
                          <schema>.barriers_remediations
                                          |
                                          v
                          [ lnk_pipeline_access(barrier_sources = list(...)) ]
                                          |
                                          v
                          mapping_code_<sp> per segment
```

## Existing primitives reused

- `R/lnk_pipeline_prepare.R:742-899` — full CABD dams logic. Pulls raw `cabd.dams` (via `conn_tunnel`), applies edit CSVs, snaps to FWA, AOI filters. Output `<schema>.dams`. Works against any conn that has `cabd.dams` loaded — local or remote.
- `R/lnk_pipeline_load.R:74-192` — user override CSV ingestion. Stages `<schema>.crossing_fixes` + `<schema>.pscis_fixes`.
- `fresh/R/frs_point_snap.R:50-107` — KNN-path snap. Args include `tolerance`, `exclude_edge_types` (default 1425), optional `blue_line_key`, `stream_order_min`. We wrap this in `lnk_points_snap()` for table-level use.
- `bcfishpass/model/01_access/sql/load_crossings.sql` — 24 KB reference for source-precedence union. PSCIS first, then PSCIS-on-modelled (uses modelled road tenure), then CABD, then modelled.
- `bcfishpass/jobs/load_weekly` — confirms CABD public API URL: `https://cabd-web.azurewebsites.net/cabd-api/features/dams?filter=province_territory_code:eq:bc&filter=use_analysis:eq:true` (GeoJSON via ogr2ogr).

## Naming conventions for new exports (per user 2026-05-08)

- `lnk_inputs_verify(conn, required)` — verb-last; mirrors `lnk_baseline_read` / `lnk_baseline_append` family pattern (`lnk_<noun>_<verb>`).
- `lnk_points_snap(conn, table_in, table_out, ...)` — generic, NOT pscis-specific. Snap any point table.
- `lnk_barriers_emit(conn, schema)` — verb-last.

Rationale: these are generic utilities likely belonging in a future `pac` package once it's scaffolded. Naming chosen to be straightforward to relocate.

## Config-driven defaults (no hardcoded magic numbers)

- `parameters_fresh.csv` gains rows for `snap_tolerance_default` (100) and `snap_edge_types_exclude` (`1425`). `lnk_points_snap()` resolves from there when args are NULL. Same pattern existing dimensions/parameters use.

## Cross-refs

- #117 (closed/v0.31.0) — csv-sync from s3://fresh-bc, the consumer-side ledger + bucket reads.
- #137 — manual snapshot path. Loads PSCIS + bchamp + CABD into local DB. Prerequisite for this issue.
- #135 (closed/v0.30.2) — `lnk_pipeline_access` + `barrier_sources` consumer. Defines the column shapes `lnk_barriers_emit()` must produce.
- NewGraphEnvironment/db_newgraph#4 + PR #5 — upstream CSV dump.

## Out-of-scope (deferred)

- Replacing fresh::extdata/crossings.csv as the bundled source.
- Province-wide regression across all 250 WSGs (ADMS smoke is enough).
- Drift-monitor automation (weekly cron checking BCDC + bchamp shapes).
- Eventual port of `lnk_inputs_verify` / `lnk_points_snap` / `lnk_barriers_emit` to `pac` once that package is scaffolded.

## Post-merge `/code-check` (2026-05-08, ran on 5221b92)

`/code-check` was checked off on the task_plan but never actually invoked pre-merge. Caught by user post-merge. Ran the skill (round 1, fresh-eyes subagent, ~1.4k-line diff over 6 R + 6 test files). No bugs, no security issues. Three fragility findings worth a v0.32.1 follow-up:

1. **`R/lnk_crossings_union.R:405`** — int4 overflow risk: `(m.modelled_crossing_id + 1000000000)::text` adds before cast. If modelled_crossing_id ever ≥ 1.15B, silently overflows (Postgres int4 max = 2^31-1 = 2,147,483,647). Override path in `.lnk_crossings_apply_overrides` already does it correctly with `::bigint + 1000000000`. Trivial fix: cast to bigint first.
2. **`R/lnk_crossings_union.R:393, 418`** — CABD/modelled use `LEFT JOIN` to `whse_basemapping.fwa_stream_networks_sp`. If `linear_feature_id` is missing from FWA (refresh drift), `watershed_key` is NULL → row silently excluded from every `barriers_*` table downstream by `blue_line_key = watershed_key`. PSCIS uses `INNER JOIN`, so loss is at least visible there. Either: (a) switch to INNER JOIN to fail-loud, or (b) add a row-count parity check after the union.
3. **`R/lnk_points_snap.R:761`** — `pts.*` collision risk: if `table_in` ever has columns matching the snap output (`linear_feature_id`, `snapped_blue_line_key`, etc.), `CREATE TABLE AS` fails. Today's BCDC PSCIS doesn't, but a future shape-change would. Replace `pts.*` with explicit column enumeration.

Lesson saved as memory: `feedback_no_falsified_pwf_checkboxes.md`. The fragility list above is the v0.32.1 follow-up scope.
