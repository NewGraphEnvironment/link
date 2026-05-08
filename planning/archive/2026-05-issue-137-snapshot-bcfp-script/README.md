## Outcome

Shipped `data-raw/snapshot_bcfp.sh` — manual snapshot script that loads bcfp dependencies (BCDC PSCIS, CABD dams, bchamp modelled crossings + observations) into a local Postgres from public sources only. No SSH tunnel, no DB pg_dump. Optional `--with-bcfp-views` flag pulls Simon's bcfp output views from `s3://newgraph` for parity comparison. Stamps `data-raw/logs/bcfp_baselines.csv` with the bcfp build identifier via `lnk_baseline_append(lnk_bucket_log())` (link#117 ledger).

Key plan-mode finding: bchamp `observations.parquet` is the canonical observations source (matches bcfp's `jobs/load_observations`). The `s3://newgraph` fgb dump of `fiss_fish_obsrvtn_events_vw` is a different artifact from a different workflow and not what bcfp consumes — explicitly excluded.

`data-raw/README.md` got a new `## Bootstrap` section documenting prereqs, quick-start, output schema list, and pointer to `lnk_pipeline_crossings()` (#138) as the consumer.

Closed by: PR #145 / v0.31.1 (merge SHA 473146f).

Unblocks #138 Phase 5 (parity verification) — once a contributor runs `bash data-raw/snapshot_bcfp.sh --with-bcfp-views` on their local fwapg, they have everything `lnk_pipeline_crossings()` needs PLUS the comparison-side bcfp views.
