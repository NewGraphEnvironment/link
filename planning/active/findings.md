# Findings — Auto-stamp bcfp baseline in run_provincial_parity.R (#121)

## Issue context

`data-raw/logs/bcfp_baselines.csv` records the bcfp comparison baseline (`model_run_id` + SHA) each link comparison was computed against. The CSV's existing rows are compare-flavoured: `(link_schema, bcfp_model_run_id)` pairs. Currently hand-maintained — the goal is auto-stamping.

Stamping must happen where comparisons actually occur. The trifecta orchestrator (`data-raw/trifecta_provincial.sh`) dispatches builds; it does not compare. Comparison happens one layer down inside `run_provincial_parity.R` (per-WSG via `compare_bcfishpass_wsg()`).

### Where bcfp is touched

| Script | Queries bcfp? | Stamp here? |
|--------|--------------|-------------|
| `data-raw/trifecta_provincial.sh` | No (dispatch only) | No |
| `data-raw/run_provincial_parity.R` | Yes — per-WSG via `compare_bcfishpass_wsg()` | Yes — once per invocation |
| `data-raw/compare_bcfishpass_wsg.R` | Yes — single WSG | Sub-call (not stamped per-WSG) |
| `data-raw/compare_rollups.R` | No — link-vs-link RDS delta | No (no bcfp involved) |

### Proposed solution (from issue body)

1. Wire the stamp at the top of `run_provincial_parity.R`, once per invocation (not per-WSG). Same script handles single-host runs and trifecta-dispatched per-host runs.
2. CSV schema migration: add `host` column. Trifecta runs produce 3 rows (m4 / m1 / cypher) all with the same `bcfp_model_run_id` but different host context. Backfill existing rows to `m4`.
3. Tunnel-tolerance: warn-and-continue if the bcfp tunnel can't open. Stamp failure must not block a build.
4. Idempotency: if `(host, link_schema, bcfp_model_run_id, run_started_pdt)` row already exists, skip.

Final CSV columns: `run_started_pdt, host, run_label, link_schema, bcfp_model_run_id, bcfp_model_version, bcfp_date_completed, notes`.

### Out of scope (per issue)

- Mid-run bcfp build collision detection (Tuesday rebuilds shifting bcfp build mid-trifecta). Separate enhancement.
- Stamping on `compare_rollups.R` (link-vs-link methodology delta, no bcfp involved).

## Plan-mode exploration notes (2026-05-04)

### Insertion point in `run_provincial_parity.R`

- Args parsed at lines 36–77.
- Setup banner (WSG count, output dir) at lines 79–83.
- Per-WSG-timings CSV initialized at lines 85–105 with `write.table()`; helper `append_time()` writes one row per WSG completion, captures `host_id = Sys.info()[["nodename"]]`.
- WSG loop starts line 107: `for (w in wsgs)`.
- Each iteration calls `compare_bcfishpass_wsg(wsg = w, config = cfg)` at lines 115–120 and saves RDS.
- Natural one-shot stamp insertion: between line 105 (end of setup) and line 107 (loop start).

### Tunnel pattern in `compare_bcfishpass_wsg.R`

- Lines 44–54: reads `PG_PASS_SHARE` env var, errors if missing (message references "localhost:63333").
- Connection: `host = "localhost"`, `port = 63333`, `dbname = "bcfishpass"`, `user = Sys.getenv("PG_USER_SHARE", "newgraph")`, `password = Sys.getenv("PG_PASS_SHARE")`.
- `on.exit()` cleanup registered at line 54.
- Tunnel is assumed pre-open; the script does not self-open. Stamp helper inherits this contract.

### CSV current state (3 rows + header)

```
run_started_pdt,run_label,link_schema,bcfp_model_run_id,bcfp_model_version,bcfp_date_completed,notes
2026-05-02 21:00,provincial_parity,fresh,?,?,?,bcfishpass-bundle provincial run; bcfp baseline not recorded at run time (pre-baselines.csv)
2026-05-03 14:23,provincial_default,fresh_default,120,v0.7.14-113-ga7373af,2026-04-28 23:17,default-bundle provincial run; bcfp baseline confirmed via bcfishpass.log query 2026-05-04
2026-05-04 09:44,provincial_default_extrabreaks,fresh_default_extrabreaks,120,v0.7.14-113-ga7373af,2026-04-28 23:17,default_extrabreaks bundle (orphan-class breaks v0.28.0 branch)
```

Run-label convention: `provincial_<bundle>` (or `provincial_parity` for the bcfishpass bundle).

### R-side helpers — none

No existing function in `R/` queries `bcfishpass.log` or appends to `bcfp_baselines.csv`. Related exports:

- `lnk_stamp()` — captures link/fresh package versions, not bcfp baseline metadata.
- `lnk_db_conn()` — opens fwapg connection; does not handle bcfp tunnel.

Helper will be inline in `data-raw/run_provincial_parity.R` to match the orchestration-tooling scope.

### Trifecta tunnel access per host

| Host | Tunnel state | Notes |
|------|--------------|-------|
| **M4** | Pre-opened on localhost (manual) | Same precondition as the per-WSG comparisons |
| **M1** | Must be pre-open on M1 | `ssh m1 "Rscript run_provincial_parity.R ..."` — no tunnel setup in trifecta orchestrator |
| **Cypher** | Opened by `cypher_run.sh` shell wrapper before `Rscript` invocation | `ssh -L 63333:127.0.0.1:5432 db_newgraph -N` |

Stamp helper inherits all three host modes via the same `localhost:63333` contract.

### `compare_rollups.R` — confirmed out of scope

Reads RDS files emitted by `compare_bcfishpass_wsg()`, joins on wsg+species+habitat_type+unit, emits link-vs-link deltas. No bcfp tunnel touched.

### Discarded path

Earlier wiring at `data-raw/trifecta_provincial.sh` start (build-time stamp) was considered and discarded uncommitted before this plan was written. No revert step needed.
