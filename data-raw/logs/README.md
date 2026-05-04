# `data-raw/logs/`

Run artifacts from pipeline drivers (`compare_bcfishpass_wsg.R`, `run_provincial_parity.R`, the trifecta scripts) plus operational outputs (pg_dumps, methodology-delta queries, regression logs).

## Subdirectories

Per-run output is keyed by topic. Each subdir holds `<WSG>.rds` per-WSG rollup tibbles plus `<TS>_per_wsg_times.csv` host-tagged timing rows.

| Subdir | Source script | Contents |
|--------|---------------|----------|
| `provincial_parity/` | `run_provincial_parity.R --config=bcfishpass` | bcfishpass-bundle rollups (link vs bcfp tunnel) |
| `provincial_default/` | `run_provincial_parity.R --config=default` | default-bundle rollups |
| `provincial_default_extrabreaks/` | `run_provincial_parity.R --config=default_extrabreaks` | orphan-class break-source experiment (v0.28.0) |
| `methodology_delta/` | `query_schema_delta.R` | schema-vs-schema delta RDS snapshots |
| `dumps_<schema>/` | `consolidate_schema.R` (manual) | pg_dump custom-format files for cross-host consolidation |
| `baseline_pre_*/` | hand-archived | Pre-change baselines kept for regression diffs |

## Top-level files

### `bcfp_baselines.csv` — bcfp build inventory per run

Records which `bcfishpass.*` schema rebuild each provincial run was compared against. Critical for paper trail because:

- The tunnel's `bcfishpass.*` schema rebuilds **weekly Tuesdays ~20:00 PDT** via `smnorris/db_newgraph`'s scheduled GHA workflow.
- Today's rollups in `provincial_*/` carry `bcfishpass_value` columns sourced from whichever build was live at the moment of comparison.
- Without recording the build, tomorrow's same-config rerun produces shifts that look like methodology change but are actually upstream-rebuild change (`bcfishpass.streams_habitat_*` repopulated from new code / new input data).

Columns:

- `run_started_pdt` — local time the provincial dispatch fired
- `run_label` — directory name where rollup RDS files landed
- `link_schema` — persistent target schema for `lnk_pipeline_persist`
- `bcfp_model_run_id` — primary key from `bcfishpass.log`
- `bcfp_model_version` — `<tag>-<commits>-g<short-sha>` string
- `bcfp_date_completed` — when Simon's rebuild finished
- `notes` — anything else (orphan-branch experiments, partial reruns, etc.)

How to query the current bcfp baseline (run before any provincial dispatch):

```sql
-- localhost:63333 / dbname=bcfishpass / user=newgraph / password=PG_PASS_SHARE
SELECT model_run_id, date_completed, model_version
FROM bcfishpass.log
ORDER BY model_run_id DESC LIMIT 1;
```

### Future automation

The csv-sync rewrite ([link#117](https://github.com/NewGraphEnvironment/link/issues/117)) will append to this CSV at sync time, recording which bcfp build the bundle CSVs are now SHA-pinned to. That closes the loop: every comparison rollup has both the bcfp build AND the matching bundle CSV state on file.

Until then, manually append a row at the start of each provincial run.

## Naming convention for log files

Run logs follow `<TS>_<topic>_<host>.txt` where `<TS>` is `YYYYMMDDHHMM`. See `data-raw/README.md` (parent) for the broader conventions.
