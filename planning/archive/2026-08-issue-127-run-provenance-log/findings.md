# Findings — Run provenance log on persist schema (#127)

## Verified DB state (2026-08-06, local docker fwapg)

**No provenance exists.** Zero log/stamp/provenance tables in `fresh`, `fresh_default`,
or `public`; `streams` carries no config column.

## Input provenance — what actually exists

Three tiers with very different coverage:

| source | covers | quality |
|---|---|---|
| `bcdata.log` (`table_name`, `latest_download`) | **only `bc2pg` downloads** — 4 `whse_fish.pscis_*`, cutblocks, fire polys | authoritative |
| `pg_class.reltuples` + `pg_total_relation_size` | every table | free |
| `pg_stat_user_tables.last_autoanalyze` | tables written since last stats reset | good proxy |

`last_autoanalyze` cross-checks against known load events:

| table | est_rows | size | last_autoanalyze |
|---|---|---|---|
| `fwa_stream_networks_sp` | 4,907,804 | 9.8 GB | **(none)** |
| `modelled_stream_crossings` | 529,244 | 161 MB | 2026-05-26 |
| `observations` | 372,690 | 225 MB | 2026-05-23 |
| `pscis_assessment_svw` | 19,905 | 19 MB | 2026-05-23 |
| `wsg_outlet` | 246 | 48 kB | 2026-05-23 16:29 |

`wsg_outlet`'s 16:29 matches its recovered `CREATE TABLE` at 16:28:50 exactly.

### The FWA gap (the important one)

- `bcdata.log` has **zero** `whse_basemapping` rows → FWA did **not** come via `bc2pg`.
- `fwa_stream_networks_sp` has `wscode_ltree`/`localcode_ltree` → it **is** the
  fwapg-processed layer, not a raw bcdata pull.
- Its `pg_stat_user_tables` row is entirely empty (`n_live_tup = 0`, all timestamps NULL)
  — bulk-restored, never analyzed. **The `last_autoanalyze` proxy fails on the single
  most load-bearing input.**
- It is loaded by **fwapg's own `load.sh`** from a mounted clone (`FWAPG_DIR`, default
  `../../fwapg`) pulling
  `https://nrs.objectstore.gov.bc.ca/bchamp/fwapg/fwa_stream_networks_sp/<WSG>.parquet`.
- Local fwapg clone: **`v0.4.1-90-ge6e1eb0`**.

→ The only real provenance for FWA is the **fwapg repo SHA**, which is on disk and
nowhere in the DB. Hence `.lnk_fwapg_sha()`.

## Codebase facts that shape the implementation

- **`lnk_pipeline_persist` is called TWICE per `lnk_pipeline_run`** (`:190-191`
  pre-persist, `:265-266` final) → a log write there double-fires. `lnk_pipeline_run`
  must own it.
- `lnk_pipeline_run` returns `invisible(conn)` (`:272`) and has **no `tryCatch`/`on.exit`**.
- `lnk_stamp()` (`R/lnk_stamp.R:69`) already carries config identity, `provenance` via
  `lnk_config_verify`, `software` (versions + git SHA), `run$start_time`.
  **`lnk_stamp_finish()` (`:136`) has ZERO call sites** — this wires it up.
- `.lnk_pkg_git_sha()` (`:254`) is pure-R: env var → `.git/HEAD` walk, no `system()`.
- `.lnk_db_execute()` (`R/utils.R:19`) is **mandatory** — tests mock it
  (`local_mocked_bindings`), raw `DBI::dbExecute` would be untestable.
- Adding a persist table touches **three** sites: the `cols_*` vector, the CREATE
  sequence, and the `.lnk_validate_persist_table()` drift list (`lnk_persist_init.R:321-336`).
- `schema_consolidate.R:140-192` auto-discovers persist tables by *"has a
  `watershed_group_code` column"* — tables without it are silently skipped.
- `LNK_HOST_ALIAS` is read only in `data-raw/`, never from `R/`; `lnk_baseline_append.R:88`
  uses bare `Sys.info()[["nodename"]]` — the reason the ledger mixes `m4` and `runnervmmklqx`.
- `test-lnk_pipeline_run.R:139+` asserts an **exact `calls` vector** and mocks only
  `DBI::dbExecute` → log helpers must be top-level namespace functions.

## #233 / v0.44.3 landed mid-planning (pulled at branch time)

- `inst/extdata/configs/dimensions_columns.csv` → **`dictionary_dimensions.csv`** (32 rows)
- **NEW `dictionary_parameters_fresh.csv`** (19 rows) with `column,type,group,owner,consumed_by,…`

Both column lists become dictionary-driven rather than hand-authored. This also **closes
the #127 deliverable** "data dictionary for `parameters_fresh.csv` columns" — strike it
from the issue.

Critical for tests: **bundles carry different column subsets** (bcfp `dimensions.csv` 30
cols vs the three `default*` bundles' 32), so coverage must be asserted against the
**union**, not any single bundle. This independently confirms blocker 2 (ALTER ADD COLUMN).

Also noted in the #233 archive: `test-lnk_wsg_resolve.R:138` fails without
`public.wsg_outlet` (#227) — but that table was recovered and now exists locally, so the
pre-existing failure may not reproduce here.

## Acceptance-criterion correction

"Editing a tracked config file sets `link_dirty = true`" is really satisfied by
**`config_drift`** (bytes changed, detected by `lnk_config_verify`, no git needed).
`link_dirty` covers the broader case of an uncommitted edit to `R/`. Ship both columns;
restate the criterion on the issue.
