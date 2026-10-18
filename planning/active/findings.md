# Findings — schema_consolidate deletes the destination's log history for every group it copies (#354)

## Issue context

**If done:** a group's earlier builds stay in `<schema>.log` on the dispatcher after a multi-host run. **If never:** every cloud-built group keeps only its newest log row, and what it was built from before is lost (it happened to DUNC, KOTL, LARL and SLOC in #246).

## Problem

`schema_consolidate()` deletes the destination's rows for a source's bucket from every table with a `watershed_group_code` column before it copies (`data-raw/schema_consolidate.R:279-286`). `<schema>.log` and `<schema>.log_recompute` have that column, so a group consolidated from a cypher loses every earlier run's log row on the dispatcher.

Measured 2026-10-17 in `fresh_default`: DUNC, KOTL, LARL and SLOC each hold one `log` row, from run `20261017_004619-3f4c713b`. Before that run they held the August (KOTL, LARL, SLOC) and 2026-10-12 (DUNC) rows. PINE and PARS also hold one row each; whether their earlier rows went the same way depends on which host built them in that run, which was not checked.

The persist tables are rightly replaced per group. The log tables are history, and losing them means the record of what a group was built from before is gone.

## Proposal

- Leave the log tables (`log`, `log_recompute`, `log_input` and the other `log_*` tables keyed by run) out of the destination DELETE, and copy their rows additively; `run_id` is already a unique key.
- Check the same for `lnk_pipeline_persist()` on the dispatcher path.


## Exploration (plan mode, 2026-10-17)

`schema_consolidate()` deletes the destination's bucket rows from every BASE TABLE with a
`watershed_group_code` column before it COPYs (`data-raw/schema_consolidate.R:279-286`).
`log`, `log_recompute` and `log_input` carry that column (so consolidate discovers them), so
each cloud-built group keeps only the source's rows and loses the dispatcher's history.

Measured during exploration (2026-10-17, local fwapg):
- `fresh_default.log`: all 241 groups hold exactly 1 row. `fresh.log` holds 2–4 rows for 20
  groups, so the readers (`lnk_log_read()` DISTINCT ON newest, `study_area_verify.sql` keyed
  on `run_uid`) already cope with history.
- PKs: persist tables all include `watershed_group_code`; the log tables do not
  (`log` run_id, `log_input` (run_id, table_name), `log_recompute` recompute_id).
- `/tmp/fresh_default_pre_consolidate_202610162242.dump` still holds the lost rows: `log` for
  DUNC (2026-10-12), KOTL/LARL/SLOC (2026-08-27), **PINE (2026-08-06)** — so PINE lost one too
  (built on cypher-job2); PARS had none. 60 `log_input` rows, 0 `log_recompute`.
- `lnk_pipeline_persist()` (dispatcher path) DELETEs only from named persist tables
  (streams, habitat, barriers, barrier_overrides, streams_access, streams_mapping_code), never
  a log table. Issue's second bullet: no change, pin it with a test.
- RUNBOOK §6c "Known exposure" (a second consolidate wipes `log_recompute`) is this bug.

Operator decision (plan gate): restore the lost rows from the dump.

## Errors Encountered

| Error | Resolution |
|-------|------------|
