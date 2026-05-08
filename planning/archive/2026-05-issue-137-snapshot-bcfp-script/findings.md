# Findings — manual snapshot of bcfp dependencies (#137)

## Issue context

Issue #137 in NewGraphEnvironment/link. Title: "data-raw: manual snapshot of bcfp dependencies into local fresh schema". Phase A of the self-sufficiency roadmap (link#117 + db_newgraph PR #5 shipped Phase 0).

## Source authority confirmed during plan-mode exploration

| Table | Source | Loader pattern | Why this source |
|---|---|---|---|
| `whse_fish.pscis_*` (4 tables) | BCDC catalogue | Python `bcdata bc2pg --refresh` | Canonical loader; Simon's db_newgraph + bcfp use same pattern |
| `cabd.dams` | `https://cabd-web.azurewebsites.net/cabd-api/features/dams?filter=province_territory_code:eq:bc&filter=use_analysis:eq:true` | ogr2ogr from GeoJSON | Same URL bcfp's `jobs/load_weekly` uses |
| `fresh.modelled_stream_crossings` | `https://nrs.objectstore.gov.bc.ca/bchamp/modelled_stream_crossings.gpkg.zip` | curl + ogr2ogr | Bcfp's `model_00_stream_crossings` builds + uploads this WEEKLY out of bcfp DB during Tue rebuild (confirmed 2026-05-07) |
| `bcfishobs.observations` | `https://nrs.objectstore.gov.bc.ca/bchamp/bcfishobs/observations.parquet` | ogr2ogr from /vsicurl parquet | Same as bcfp's `jobs/load_observations`. Authoritative — what bcfp actually consumes |

### NOT used: `s3://newgraph/bcfishobs.fiss_fish_obsrvtn_events_vw.fgb.zip`

This is a view dump from a different workflow (`db_newgraph/jobs/dump_weekly`, runs Sunday). It's a single-view subset of the bcfishobs schema, not what bcfp consumes. The authoritative path is the parquet from bchamp. Do not use the s3://newgraph fgb.

### Comparison-side bcfp views (optional)

- `s3://newgraph/bcfishpass.crossings_vw.fgb.zip` — current bcfp output, dumped Sunday (after the previous Tue rebuild). Aligned with the most recent rebuild SHA between Wed and following Tue. Useful for parity diffing in #138 Phase 5.
- `s3://newgraph/bcfishpass.streams_vw.fgb.zip` — same.

## Existing primitives reused

- `R/lnk_bucket_log.R` (#117) — reads `s3://fresh-bc/bcfishpass/log.json` for build identifier.
- `R/lnk_baseline_append.R` (#117) — appends ledger row.
- bcfp reference: `jobs/load_weekly` (CABD pattern), `jobs/load_modelled_stream_crossings` (bchamp gpkg pattern), `jobs/load_observations` (bchamp parquet pattern).

## Cross-refs

- #117 (closed/v0.31.0) — csv-sync rewrite. Provides `lnk_bucket_log` + `lnk_baseline_append`.
- #138 (in flight, parked) — `lnk_pipeline_crossings` consumer. Phase 5 parity needs the comparison-side views from this snapshot.
- NewGraphEnvironment/db_newgraph PR #5 — populates s3://fresh-bc/bcfishpass/log.json that this script reads for the baseline stamp.

## Out-of-scope

- Drift-monitor automation (weekly GHA + crate schema-validate). Defer.
- Habitat-table refactor in `lnk_pipeline_mapping_code`. Separate concern.
- Optional launchd plist for weekly auto-refresh. Anyone who wants it can write 10 lines.
