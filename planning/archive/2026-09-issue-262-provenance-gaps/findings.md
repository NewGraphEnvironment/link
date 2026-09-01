# Findings — Provenance gaps before the 217-WSG run (#262)

## Measurement, 2026-09-01 (local docker fwapg, `fresh.log`, last 3 days)

```
 n | n_run_id | n_label | n_bcfp_id | n_bcfp_ver | n_dirty
37 |       37 |       0 |         0 |          0 |      22
```

Confirms all four counts in the issue body. What it does **not** confirm is the issue's
account of *why* two of them are zero.

## Correction 1 — `run_label` is plumbed end to end already

`grep -rn LNK_RUN_LABEL` over the tree returns four hits and **no orchestrator**:

| file | line | what |
|---|---|---|
| `R/lnk_pipeline_run.R` | 115 | the parameter default |
| `man/lnk_pipeline_run.Rd` | 17, 65 | generated docs |
| `RUNBOOK.md` | 474 | one prose mention |

`lnk_pipeline_run(run_label=)` → `.lnk_log_run_start(run_label=)` (`:147`) → the INSERT
(`R/lnk_log.R:584`). The column is NULL because nothing sets the env var, not because
the write path is missing. So gap 1's R-side work is the *cross-host id*, not the label.

## Correction 2 — the bcfp columns have a writer; its source is unreachable by design

`.lnk_bcfp_log_current(conn)` (`R/lnk_log.R:664`) is called at `:570` and its two fields
inserted at `:604-605`. It probes `information_schema` for `bcfishpass.log` and returns
NULL when absent.

Measured on the pipeline's own database:

```sql
SELECT count(*) FROM information_schema.tables WHERE table_schema='bcfishpass';
-- 0
```

The run is deliberately tunnel-free (`study_area_run.sh` header: "No M4, no `ssh m1`,
no bcfp tunnel"). The compare reference is `fresh.streams_vw_bcfp` — a **local snapshot**
`ogr2ogr`'d from `newgraph.s3` by `snapshot_bcfp.sh`.

That snapshot's build id is already recorded. `snapshot_bcfp.sh` step 6 calls
`lnk_baseline_append(lnk_bucket_log(), ...)`, writing
`data-raw/logs/bcfp_baselines.csv`. Latest m1 row:

```
2026-08-31 14:50,m1,snapshot-20260831,n/a,,v0.7.15-47-ga702229,2026-08-19T04:31:37Z,...
```

So the deterministic ref exists locally, tunnel-free. Querying `bcfishpass.log` at
compare time (the issue's ask) would need the tunnel back **and** would name the build
the tunnel is at *now* — it rebuilds weekly — rather than the one the snapshot was taken
from. That is a wrong pin, not a missing one.

**`bcfp_model_run_id` has no tunnel-free source.** `lnk_bucket_log()` requires only
`model_version`, `date_completed`, `head_sha`; `lnk_baseline_append()` writes `""` for
the id and says so in its own docs. NULL there is honest absence.

## Correction 3 — the recompute gap and `link_dirty` are exactly as reported

`data-raw/wsg_recompute_one.R` has zero `lnk_log` / `lnk_stamp` calls while rewriting
`<persist>.streams_access` and `<persist>.streams_mapping_code`.

`link_dirty`: 22 dispatcher rows flagged; `git status --porcelain --untracked-files=no`
empty at the same moment. Probed both pathspec forms on this tree — `:(exclude)` exits 0,
and excluding a path that does not exist is harmless (so `fresh`, which has no
`data-raw/logs`, is unaffected by the same predicate).

## Design constraint discovered: DDL inside the recompute pool is a lock convoy

The pool runs at `--recompute-jobs=4` (max 16). `CREATE TABLE IF NOT EXISTS` and
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` take AccessExclusiveLock, and a queued
exclusive request blocks every sibling's AccessShareLock behind it — precisely why
link#250 hoisted `barriers_views_build.R` out of the pool.

So `.lnk_log_recompute_start()` must **verify** the table exists and fail loudly, never
create it. `lnk_persist_init()` and every modelling run already create it via
`.lnk_log_create_tables()`, and the modelling phase always precedes the recompute in the
driver.

## Why `log_recompute` is its own table rather than a `phase` column on `log`

- `lnk_log_read()` does `DISTINCT ON (watershed_group_code) ... ORDER BY date_start DESC`.
  A recompute row is newer, so it would be returned as "what produced this network" —
  which it did not.
- `count(*)` on `log` currently means "WSGs modelled", and `study_area_verify.sql` reads
  it that way.
- `arg_dams`, `arg_mapping_code`, `wsg_upstream`, `config_drift` are modelling facts and
  would be NULL or misleading on a recompute row.
- `schema_consolidate.R:156` discovers tables by "has a `watershed_group_code` column and
  is a BASE TABLE", so a new table is picked up with no list to maintain.

## Issue context

<full body preserved in the GitHub issue #262; the corrections above supersede its
sections 1 and 3 as to cause, not as to symptom>

## Errors Encountered

| Error | Resolution |
|-------|------------|
