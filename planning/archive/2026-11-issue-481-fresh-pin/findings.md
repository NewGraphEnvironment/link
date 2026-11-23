# Findings — Backlog move 13: The next fresh pin (#481)

## Issue context

**If we do it:** the persisted near-river table keeps fresh's key, and both connection helpers read the same variables. **If we never do:** the validator errors on the first install of fresh 0.54.0.

**Open since 2026-11-22:** fresh 0.54.0 shipped on 2026-11-20 (0.55.1 is the latest release); the plan reads fresh's NEWS from 0.52.0 to the pinned tag.

Move 13 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 20: The next fresh pin

**Why here:** one pin bump and one host re-prep.

#452 (`cols_streams_near_river` gains `linear_feature_id` with fresh 0.54.0, and the validator passes `near_river_lfid`), #288 (`lnk_db_conn()` reads `PG_*_SHARE` first, fresh reads `PG*` first) and #222 (the live `lnk_wsg_resolve` tests route to another database than their skip gate; the failure is gone, the mismatch is not). Touches `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `R/lnk_habitat_validate.R`, `DESCRIPTION`, `R/lnk_db_conn.R`, `tests/testthat/test-lnk_wsg_resolve.R`. Gate: which variables both connection helpers read. Only #452 waits on fresh 0.54.0; #288 and #222 ride its pin bump and host re-prep.

| issue | title |
|---|---|
| #452 | cols_streams_near_river mirrors fresh's near_river table, which gained linear_feature_id in 0.54.0 |
| #288 | lnk_db_conn(): prefer standard PG* env vars to match fresh 0.36.0 |
| #222 | test-lnk_wsg_resolve live tests route to wrong DB (skip-gate vs lnk_db_conn mismatch) |



## Exploration, 2026-11-22 (at origin/main be06e2b4, link 0.86.0, fresh pinned v0.52.0)

- **fresh 0.52.0 → 0.55.1** (NEWS read at fresh v0.55.1): 0.53.0 (fresh#282) keys `to_streams` overwrites on `linear_feature_id`; 0.54.0 (fresh#293) adds `linear_feature_id` to the classify target and its `_near_river` table when the streams table carries one, keys their deletes and reads on it, and makes `frs_habitat_predicates(near_river_lfid)` required whenever `near_river_table` is given; 0.55.0 (fresh#305) gives `frs_db_conn()` a 10 s connect timeout, TCP keepalives and `...`; 0.55.1 (fresh#279) changes fresh's tests only.
- **Files changed under fresh `R/`** between v0.52.0 and v0.55.1: `frs_cluster`, `frs_db_conn`, `frs_habitat`, `frs_habitat_classify`, `frs_habitat_overlay`, `frs_habitat_predicates`, `frs_near_river`, `frs_order_child`, `utils`. None added, none under `inst/extdata`. Every one has a row in `data-raw/pretest_inputs.csv` (lines 125-149); `frs_db_conn.R` is `none` (line 149).
- **`.lnk_hv_stage_exprs()`** (`R/lnk_habitat_validate.R:1095`, `:1108`) calls `frs_habitat_predicates(near_river_table =)` with no `near_river_lfid`: errors at fresh >= 0.54.0.
- **`cols_streams_near_river`** (`R/lnk_persist_init.R:218`) has no `linear_feature_id`; the table is created with `CREATE TABLE IF NOT EXISTS` (`:642`), so an existing table never gains a column without an `ADD COLUMN` path. `lnk_pipeline_persist()` projects `names(cols_streams_near_river)` (`R/lnk_pipeline_persist.R:277`).
- **`lnk_pipeline_classify()` drops `<schema>.streams_habitat_near_river`** before classify (`:117`) but not `<schema>.streams_habitat`; `lnk_pipeline_run()` sets the working schema up with `overwrite = TRUE` (`R/lnk_pipeline_run.R:224`), so a build's classify target is new. The variants harness re-classifies kept working schemas (`data-raw/habitat_variants_build.R:928`).
- **`lnk_db_conn()`** reads `PG_*_SHARE` then `PG*` per field with hard-coded defaults; `frs_db_conn()` (fresh v0.55.1) takes `NULL` defaults, resolves args → `PG*` → `PG_*_SHARE`, never mixed, then bounds. `wsg_run_one.R:57` and `wsg_recompute_one.R:35` pass every field explicitly; 8 `data-raw/*.R` scripts call `lnk_db_conn()` bare.
- **`lnk_wsg_resolve()`** province and strict modes return before any connection (`R/lnk_wsg_resolve.R:111-124`); only closure mode opens `lnk_db_conn()` when `conn` is NULL.
- **Consolidate copies the columns both sides share** (`data-raw/schema_consolidate.R:388-390`), and `streams_near_river` is in its persist core (`data-raw/study_area_hosts.sh:434`).

## Resume, 2026-11-22/23 (m1)

- **m1's fwapg was unreachable from about 2026-11-21 20:46 PDT:** the colima VM ran, its guest agent still synced time over vsock, but the guest's network was gone (last host-agent event: the guest dropped its DHCP lease on 192.168.5.1; ssh to the VM and 5432 refused). `colima stop && colima start` (owner's call, 2026-11-23 01:30 UTC) brought `fresh-db` back within 10 s, not in recovery. `LIMA_HOME=~/.colima/_lima limactl list` sees colima's VM; plain `limactl` does not.
- **The shared R library held fresh 0.53.0** (installed 2026-11-16, `RemoteSha 43b7cb32`), not the 0.52.0 main pins. So both arms run fresh from scratch libraries: `~/tmp/pin481/lib052` (v0.52.0, 245c8d8d) and `lib0551` (v0.55.1, 29e7aa13), each `R CMD INSTALL -l` from a worktree of the tag.
- **Phase 5's draft gate was stale:** it skipped on `to_regclass('public.wsg_outlet')`, a table fresh 0.33.0 retired (outlets ship in fresh). Closure mode reads only `whse_basemapping.fwa_downstream()`, so the gate checks that routine.
- **fresh's deprecation message fires with all five arguments explicit** (`.frs_conn_resolve()` reads the environment before the arguments). link muffles it for a fully explicit call; worth a fresh issue (drafted in the PR, not filed).
- **fresh's reach at v0.55.1 is 19 files** (18 at v0.42.0 to v0.46.0): `frs_db_conn.R` joins it through `lnk_db_conn()`, and was the only reached file mapped `none` (`data-raw/logs/fresh_pin_481/reach.md`).
- `data-raw/logs/minimal_breaks_415/proof.R:317` calls `frs_habitat_predicates(near_river_table =)` without `near_river_lfid`, so it would error under fresh >= 0.54.0 if re-run; left as the record it is.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `sed` substitution with `#` delimiter broke on `#288` in the replacement | Edited the map row with Python |
| A helper wrapping `skip_if_no_db()` would close the connection on return (it defers the disconnect to its caller's frame) | A check-only `skip_if_no_fwa_downstream(conn)` beside it |
