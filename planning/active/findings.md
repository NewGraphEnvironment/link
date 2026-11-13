# Findings — Backlog move 6: What a run stamps and checks before launch, and how primitives load (#474)

## Issue context

**If we do it:** each stamp describes something the run read, one rule picks the bcfishpass reference build, the pre-run gate finds its own history, hosts install the fresh `DESCRIPTION` pins, and primitive loads fall back and record what they loaded. **If we never do:** every launch needs a clean bcfishobs clone for a number nothing reads, and a stale primitive can pass the vintage gate.

Move 6 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 8: What a run stamps and checks before launch

**Why here:** `R/lnk_log.R` and the driver's pre-flight; one release before the next provincial run.

#451 (the run stamps a local bcfishobs checkout's commit that no run reads, and refuses to launch when it is dirty), #446 (the bcfishpass reference pin reads a CSV-sync ledger row as the loaded view), #266 (link and flooded select the bcfishpass reference build by different rules), #458 (`<schema>.log` keeps earlier runs' rows; say in RUNBOOK that readers key on `run_uid`) and #450 (the pre-run gate finds its history through `extends:` and a committed record of build minutes) and #269 (`scripts/update_hosts.sh` installs fresh from main while `DESCRIPTION` pins a tag, so a host re-prep can pull a fresh newer than the pin; the worker's refused GitHub token is the other residue, from #439). Touches `R/lnk_log.R`, `R/lnk_stamp.R`, `data-raw/study_area_run.sh` (the bcfishobs gate), `data-raw/study_area_remote.sh`, `data-raw/study_area_verify.sql`, `data-raw/pretest_*`, `scripts/update_hosts.sh`, `DESCRIPTION`, RUNBOOK §8d. Gate: retire or refill `bcfishobs_sha`; one selection rule for the bcfishpass build (#266 with #446); #450's range rule; tag pins or an `Imports:` floor for fresh. One release before the next provincial run.

| issue | title |
|---|---|
| #451 | The run stamps a local bcfishobs checkout's commit that no run reads, and refuses to launch when it is dirty |
| #446 | The bcfishpass reference pin reads a CSV-sync ledger row as the loaded view |
| #266 | link and flooded select the bcfp reference build by different rules against the same table |
| #458 | A provincial run leaves the previous run's rows in <schema>.log |
| #450 | The pre-run gate finds its history without flags or copies: through `extends:`, and from a record of build minutes kept across schemas and hosts |
| #269 | update_hosts.sh installs fresh from main while DESCRIPTION pins a tag |

## Batch 9: How primitives load

**Why here:** `snapshot_bcfp.sh` and the vintage gate; one primitives reload proves it.

#459 (`snapshot_bcfp.sh`: the two-argument `--config` form for GDAL 3.8, and fallbacks for the Parquet and bcdata paths), #276 (the snapshot skip guard keys on a code SHA and is scoped per host; hosts should reach one freshness decision), #273 (the vintage gate asks how old our copy is, not whether the source changed), #270 (capture fwapg `load.sh`'s trace as `loader` rows in `provenance.source_artifact`), and #484 (retry each PSCIS `bc2pg` and refuse a zero-row load: a transient WFS zero count failed two hosts' prep on 2026-11-13; #459's WFS fallback meets the same zero, so the row check covers both). Touches `data-raw/snapshot_bcfp.sh`, `data-raw/study_area_run.sh` (`preflight_hosts`), `R/lnk_preflight_vintage.R`, `R/lnk_artifact.R`, `R/lnk_baseline_current.R`, a new fwapg load wrapper. Gate: ETag change or age per table. Both batches edit the driver's pre-flight, so they run in order inside the move. One primitives reload on a host proves it.

| issue | title |
|---|---|
| #459 | snapshot_bcfp.sh: --config KEY=VALUE fails on GDAL 3.8, and the Parquet and bcdata paths have no fallback |
| #276 | Snapshot skip-guard is keyed on a code SHA and scoped per host: cyphers pull every spin, the dispatcher never does |
| #273 | Vintage gate asks how old our copy is, not whether the source changed |
| #270 | Capture fwapg load.sh's stderr as the primitive provenance record (no fork change needed) |
| #484 | snapshot_bcfp.sh: retry bcdata bc2pg when the WFS returns a zero feature count |



## Exploration (2026-11-12, plan mode)

- No comments on #474 or on any of its 11 child issues at plan time; every child body was read in full.
- `planning/backlog.md` is on the unmerged #468 branch only, so `/planning-init` found no move to claim (MOVE=0).
- flooded `origin/main` (`9f5e7bd`, 2026-11-09) reads no `bcfishpass.log` and no bcfp version in `R/` or `data-raw/`: flooded#87 replaced it. #266 reduces to link's own rule.
- This host is m1 (GDAL 3.13.0, `LNK_HOST_ALIAS` unset). Where #459's GDAL 3.8.4 was met is not recorded in the repo.
- link has no `model_type` reference anywhere; the db tier's columns must be probed on the tunnel before the SQL changes.

The rest of what exploration found is in `task_plan.md`, "Found in exploration".

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `test-lnk_log.R` ".lnk_run_id is unique across many draws" failed once in a run, passed on rerun | Pre-existing and unrelated: ms timestamp + 24 random bits; a collision in 500 draws should be ~1e-4. Not chased here; noted for a follow-up if it recurs. |
| Tunnel to the bcfp reference DB refused (port 63333) | Read `bcfishpass.log`'s DDL and writer from `smnorris/bcfishpass@3bd2824` instead (`db/migrations/archive/v0.5.0/sql/tables/log.sql`, `model/02_habitat_linear/habitat_linear.sh:47`). |
| Ancestor pick chose `fresh_smoke369b` (2 groups) over `fresh_default` (241) | `count(DISTINCT ...)` is bigint, RPostgres returns `integer64`, and `-x` ordering without bit64 attached reads the raw bits. Cast `::integer` in SQL and coerce in R. |
| `pretest_run.sh`: "bad substitution: no closing }" | An apostrophe inside `${VAR:-...}` within double quotes (code-check-shell). Rewrote with `if`. |
| Ancestor candidates hit `bcdata.log` ("column config_name does not exist") | Candidates are schemas whose `log` has a `config_name` column (information_schema.columns). |
| Full suite: 2 failures in `test-lnk_wsg_resolve.R` closure mode; `R CMD check`: those 2 plus `test-lnk_db_conn.R` "reads PGDATABASE" | All three connect through `lnk_db_conn()`'s `PG_*_SHARE` defaults to the bcfp reference tunnel (localhost:63333), down this session (refused). Environmental, not this branch; 5,639 others pass. The tests gate on `skip_if_no_db()`, which reaches the local DB, not the tunnel the call then opens. |
