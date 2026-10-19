# Findings — One failed group skips the post-consolidate recompute for every group (#348)

## Context and design (from plan mode)


In `data-raw/study_area_run.sh` the coverage check after consolidate (`:1394-1410`) `exit 1`s on the first run group that has no `<schema>.streams` rows. The recompute (`lnk_access(merge = TRUE)`, `:1425-1545`) and the compare come after it, so one failed group costs every other group its recompute. The check also asks only whether a group has rows, not whether they come from this run, so a failed group that still holds an earlier run's rows passes, the recompute covers it, and nothing at that point says its rows are stale.

What exploration settled:
- **"Finished this run" is already defined** in `data-raw/study_area_hosts.sh` (#347): `host_finished` = `<schema>.log` row with `run_uid = RUN_UID AND date_end IS NOT NULL`, with log `done` markers only adding. `.lnk_log_run_fail()` (`R/lnk_log.R:1055`) leaves `date_end` NULL, so a failed group has an *open* row. Since #354, consolidate copies each group's log rows to the dispatcher, so after consolidate the dispatcher's `log` names cypher groups too.
- **Reuse:** `.hosts_query` (sentinel-framed local/remote query; unknown never reads as empty) and the set helpers (`.hosts_union/minus/inter/csv`) in `study_area_hosts.sh`.
- **The pool functions** (`csv_lines`, `run_recompute_pool`, etc., `:1127-1280`) are pulled out of `study_area_run.sh` by `pool_probe.sh`, `recompute_parity.sh` and `recompute_sweep.sh` with `sed`/`awk` pattern matches. They must stay in the driver. Moving them within the file is safe because the matches do not depend on position.
- **A fixture schema test already exists:** `test-schema_consolidate.R` uses `skip_if_no_db()` plus `.lnk_log_create_tables()` on a scratch schema. `test-study_area_hosts.R` runs a bash lib with stubs on PATH, and that is the pattern followed here.
- A cypher group that failed leaves its open log row **on the cypher** (consolidate takes finished groups only). So in `--recompute-only`, reading the expected set from the dispatcher's log cannot see such a group. That is why `--wsgs=` is offered.

## Design

New sourced lib **`data-raw/study_area_finish.sh`** (sourced after `study_area_hosts.sh`; uses its helpers). It holds everything from coverage onwards, so the normal run and `--recompute-only` share one path and tests can reach it:

- `run_coverage <expected csv> <signals csv>`: one strict local `streams` query and one `log` query for `RUN_UID`. Sets:
  - `COV_RECOMPUTE` = expected ∩ has rows ∩ (closed log row this run ∪ signals);
  - `COV_NOROWS` = no rows at all;
  - `COV_STALE` = rows, but not from a build this run finished (an earlier run's, or this run's partial pre-persist);
  - `COV_LOST` = finished this run, no rows on the dispatcher (consolidate lost them).

  Prints one line per class. Returns 1 when the database does not answer, and the driver then FATALs as before, because it cannot verify.
- `run_expected_from_log`: the groups with **any** `log` row for `RUN_UID`, open or closed (for `--recompute-only` without `--wsgs=`).
- `run_finish <expected csv> <signals csv>`: coverage, then the log-tables / barrier-views prep, the pool over `COV_RECOMPUTE`, the judge, the compare over `COV_RECOMPUTE`, and the final report. This is today's `:1383-1620`, moved and changed only as follows:
  - **Missing groups never exit.** They set `RUN_INCOMPLETE=1`, and the report names each by class.
  - **An empty `COV_RECOMPUTE` skips the recompute and the compare**, and the run prints why ("no run group has rows from a build this run finished").
  - The report gives the recovery command: `LNK_RUN_UID=<uid> LNK_SCHEMA=… Rscript data-raw/wsg_run_one.R <WSG> <config>`, then `study_area_run.sh --recompute-only --run-uid=<uid> …`.
  - It returns the status, and the driver `exit`s with it.

Driver changes (`study_area_run.sh`):
- Flags:
  - `--recompute-only` and `--run-uid=<uid>`, both required together. `<uid>` must match `^[0-9]{8}_[0-9]{6}-[0-9a-f]{8}$`, the format minted at `:330`.
  - Optional `--wsgs=A,B` (recompute-only only).
  - `--recompute-only` is refused with `--focal`, `--cy-workspaces`, `--preflight-only`, `--refresh-primitives` or `--auto-install`.
  - The focal-count check is skipped in recompute-only, as it already is for preflight-only.
- In recompute-only, `RUN_UID` is the given uid (exported as `LNK_RUN_UID`, so `log_recompute` rows carry it), and the header says `MODE: --recompute-only`.
- The pool function block moves above the pre-flight. Right after the trap, `--recompute-only` checks `pg_isready`, takes its expected set (`--wsgs=`, or else `run_expected_from_log`), and calls `run_finish "$expected" ""`. It skips the pre-flight, dispatch and consolidate, and says why: it reads persisted tables only. Zero expected groups means a non-zero exit naming the run_uid.
- Normal path: `RUN_WSGS` = union of buckets minus every host's SKIP set. Signals = dispatcher `ACC_FINISHED ∪ ACC_DONE_LOG` ∪ each cypher's `CY_BUCKET_DONE`. Then `run_finish "$RUN_WSGS" "$signals"`.


## Errors Encountered

| Error | Resolution |
|-------|------------|
