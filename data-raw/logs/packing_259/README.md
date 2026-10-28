# packing_259 — packing weights and host speeds against measured legs (link#259)

Run 2026-10-28 UTC from m4 at link `998c986a` + this branch. Fitted on the 2026-10-17 provincial
`default` run (`20261017_004619-3f4c713b`), scored on 2026-10-23's (`20261023_074321-24d85e8c`), each
group on the host its 10-23 log row names. The verdict is in `research/study_area_run.md`, "How hosts
are packed".

| file | what it holds |
|---|---|
| `log_rows.tsv` | finished `log` rows of both builds (src schema, run_uid, wsg, host, start, end, minutes), from m1's `fresh_default` (10-23) and `fresh_default_20261017` (10-17); the 5 rows with no run_uid are older builds restored by #354 and are dropped |
| `segments.tsv` | FWA stream segments per group (`whse_basemapping.fwa_stream_networks_sp`, m4's fwapg) |
| `fit.R` | the producer: `Rscript fit.R > fit.md` from this directory |
| `fit.md` | its output: per-leg error, share error and makespan for each weight × speed, as logged and with KTSU and OKAN left out; the same-group drift between runs; the seed |

`log_rows.tsv` was exported on m1 under `bash -lc` (its non-interactive ssh PATH lacks `psql`), the SQL on
stdin, with `psql -A -F <tab> -P footer=off`:

```sql
SELECT 'fresh_default_20261017' AS src, run_uid, watershed_group_code AS wsg, host, to_char(date_start AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') AS start_utc, to_char(date_end AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') AS end_utc, round((extract(epoch
  FROM date_end-date_start)/60)::numeric,3) AS minutes
  FROM fresh_default_20261017.log
 WHERE date_end IS NOT NULL
UNION ALL
SELECT 'fresh_default', run_uid, watershed_group_code, host, to_char(date_start AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'), to_char(date_end AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'), round((extract(epoch
  FROM date_end-date_start)/60)::numeric,3)
  FROM fresh_default.log
 WHERE date_end IS NOT NULL
 ORDER BY 1,2,5;
```
