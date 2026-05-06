## Outcome

Auto-stamping wired into `data-raw/run_provincial_parity.R` — once-per-invocation row appended to `data-raw/logs/bcfp_baselines.csv` capturing `(host, run_label, link_schema, bcfp_model_run_id, bcfp_model_version, bcfp_date_completed)`. Connection pattern reused verbatim from `compare_bcfishpass_wsg.R:44-54` (port 63333, env-var auth). `host` resolves via `LNK_HOST_ALIAS` env var (per-host in `~/.Renviron`), falls back to `Sys.info()[["nodename"]]`. Idempotent on `(host, link_schema, bcfp_model_run_id, run_started_pdt)` — same-minute resume re-runs skip rather than duplicate. Tunnel-tolerant: connection failure logs WARN and the build proceeds.

CSV schema migrated to add `host` column between `run_started_pdt` and `run_label`; three pre-existing rows backfilled to `host=m4`. Verified end-to-end on M4 single-host: smoke + idempotency + tunnel-down all pass. Trifecta verification deferred to next provincial run when M1 docker CLI updated and cypher reachable — confirmed in flight via `default_rearbreaks` trifecta started 2026-05-04 23:23 PDT.

Closed by: PR [#122](https://github.com/NewGraphEnvironment/link/pull/122) (squash `bf5db25`), v0.29.1.
