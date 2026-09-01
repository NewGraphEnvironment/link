# Findings — Parallelise the post-consolidate recompute (#250)

## The issue's safety argument has a hole

#250 argues each WSG's recompute reads shared tables and writes only its own rows,
using a per-WSG scratch table — so loop order is irrelevant. That is true of
everything **except** the barrier views.

`R/lnk_access.R:119` unconditionally calls
`lnk_barriers_views(conn, schema = view_schema, ...)` where `view_schema` is
derived from `table_barriers` (`:116`) — for the recompute, the **persist schema**.
`R/lnk_barriers_views.R` then issues ~38 DDL statements per call against
schema-scoped names every sibling WSG reads:

| line | statement | name |
|---|---|---|
| `:158` / `:159` | `DROP VIEW IF EXISTS` then `CREATE OR REPLACE VIEW` | `<schema>.barriers_<sp>_unified` |
| `:195` / `:196` | same | `<schema>.barriers_<sp>_access` |
| `:223` / `:224` | same | `barriers_{anthropogenic,pscis,dams}_unified` |

Each `.lnk_db_execute` (`R/utils.R:19-31`) is its own autocommit statement, so
DROP-then-CREATE leaves a real interval in which the view **does not exist** — a
concurrent `frs_network_features` SELECT gets `relation ... does not exist`.

**And removing the DROP is not sufficient.** `CREATE OR REPLACE VIEW` also takes
`AccessExclusiveLock`, and a **queued** exclusive request blocks every subsequent
`AccessShareLock`. Job A holds a share lock for its whole network walk (tens of
seconds); job B's DDL queues behind it; job C's *read* queues behind B. Lock
convoy, ending in `lock_timeout` (60 s, `wsg_recompute_one.R:43`) errors that
surface as silent `[WARN]`s. **The hoist is load-bearing; the DROP removal is
defence in depth.**

This is the **only** schema-scoped mutation in the recompute path. Everything else
verified WSG- or row-scoped:

- `zz_lnk_streams_<aoi>` — `lnk_access.R:140-155`, incl. 4 indexes + ANALYZE + on.exit DROP
- `zz_lnk_access_scratch_<aoi>` — `lnk_access.R:169`
- `zz_lnk_mc_scratch_<wsg>` — `wsg_recompute_one.R:76`
- `UPDATE <persist>.streams_access ... WHERE watershed_group_code = aoi` — row-scoped
- `DELETE`+`INSERT` on `<persist>.streams_mapping_code` in a transaction — row-scoped;
  PK is `(id_segment, watershed_group_code)` (`lnk_persist_init.R:311`)
- `lnk_mapping_code` / `lnk_pipeline_mapping_code` — read-only plus one write to the
  WSG-scoped scratch; does **not** call `lnk_barriers_views`
- `lnk_wsg_downstream_check` — strictly read-only, by design (`:39-41`)
- fresh's `frs_network_features`, `frs_wsg_drainage`, `frs_wsg_outlets` — zero DDL

## The DROP VIEW was never a fix

`git blame`: the `_unified` pair arrived in the initial commit `9e350d2`, the
`_access` pair in `2beb42f` copied from it. Neither was added to fix anything.
The view column list is byte-identical across both refactors, so `CREATE OR
REPLACE VIEW`'s "may not rename/retype/reorder" restriction is satisfied. The doc
comment at `lnk_barriers_views.R:66-68` already describes the pair as if
`CREATE OR REPLACE` were the mechanism.

`RUNBOOK.md:380-391` records the cost showing up already in the **sequential**
case: 2026-05-25, an orphaned `frs_network_features` backend held a lock on
`barriers_bt_access` and every later `DROP VIEW` blocked indefinitely. That
incident is why the `statement_timeout` / `lock_timeout` at
`wsg_recompute_one.R:42-43` exist.

## Recompute failures cannot currently fail the run

Three separate reasons, compounding:

1. `|| echo` at `:980` is **inside** the loop, so the loop's last command always
   returns 0 and the subshell always exits 0.
2. `echo "  ✓ recompute done"` at `:982` is therefore unconditional.
3. `RUN_INCOMPLETE` is assigned exactly once at `:958`, **before** the loop, from
   `complete_fail`. Nothing after `:958` ever raises it.

So today a run in which all 50 recomputes failed exits 0 and writes a compare CSV.
There is also no completeness accounting for the recompute — `report_completeness`
/ `bucket_done` (`:828-853`) are applied only to the modelling logs.

This is the more consequential half of #250: an incomplete recompute is a
**silently wrong** result (those WSGs keep their pre-consolidate access, so
token1/token2 and `;DAM` are wrong for them), not a missing one.

## `lnk_access()` has exactly one caller

`grep` across `R/`, `data-raw/`, `tests/`: only `data-raw/wsg_recompute_one.R:63`,
plus roxygen prose. `lnk_pipeline_run.R:238` and `lnk_compare_wsg` call
**`lnk_barriers_views()`** directly, not `lnk_access()`. So a new `lnk_access()`
argument has a compatibility surface of one internal caller plus the public
contract.

## Species coverage of a hoisted build

`lnk_pipeline_species()` returns `intersect(configured, present)` where
`configured` is `cfg$species` (`R/lnk_pipeline_species.R:63`), so each WSG's active
set is a guaranteed **subset** of `cfg$species`. One build over `cfg$species`
therefore covers every WSG.

Side effect worth naming: the view set becomes **uniform**. Today each caller
builds whichever subset its WSG happens to need, so the schema holds whatever the
last WSG left. After the hoist all configured species exist and are current.

## Idempotence — verified by reading the SQL, not assumed

`lnk_access(merge = TRUE)` reads its own prior output at `R/lnk_access.R:195-197`:
`access_<sp> = CASE WHEN sc.access = 0 THEN 0 WHEN t.access = 2 THEN 2 ELSE 1 END`.
So the recompute is **not** a pure function of untouched inputs. Applying twice
with the same scratch:

| prior `t` | `sc` | pass 1 | pass 2 |
|---|---|---|---|
| any | `0` | `0` | `0` |
| `2` | ≠0 | `2` | `2` |
| `0` or `1` | ≠0 | `1` | `1` |

Fixed point after one application. The `has_barriers_*_dnstr` / `dam_dnstr_ind`
flags are set directly from the scratch, so they are idempotent trivially.

Note the fixed point is **path-dependent** — the `2` (observed upstream) is carried
from history, not derived from the inputs. That is why the parity proof restores
state between passes rather than leaning on idempotence, and asserts idempotence as
its own recorded result (pass B) instead of as a premise.

## Environment constraints

- `/bin/bash` is **3.2.57**; PATH bash is 5.3.9. `wait -n` is bash 4.3+, so it is
  unavailable — confirmed by direct test. Empty arrays under `set -u` also bite on 3.2.
- **`data-raw/logs/study_area_run/` is tracked** — 110 committed files, no
  `.gitignore` entry. Flat per-job logs would add 217 tracked files per provincial
  run to a public repo.
- `redact_log_addresses()` (`:258-268`) globs `"$LOG_DIR"/"${TS}"_*` and skips
  non-files, so per-job logs in a subdirectory are **not** redacted without a change.
- No shell test harness exists — no bats, no shellcheck config, no CI running shell.
  The house convention, stated twice inside `study_area_run.sh` itself (`:402-406`,
  `:512-528`), is to move the predicate into R and test the R.
- No `xargs -P` / GNU parallel anywhere in the repo. Existing fan-out is
  `( ... ) &` + `wait` over a fixed small host set — never a bounded work-list pool.

## Why not `xargs -P`

1. Exit **123** collapses "1 of 50 failed" and "50 of 50 failed" into one status —
   exactly the distinction #250 requires be tested.
2. BSD and GNU `xargs` diverge on `-I` / `-P` interaction; the dispatcher is macOS.
3. It is not the house idiom.

The pool stays simple because the per-job `.rc` file is the source of truth for
exit status, so the harness only needs **liveness** (`kill -0`), which bash 3.2 has.
The evidence also survives a killed dispatcher.

## Errors Encountered

| Error | Resolution |
|-------|------------|
