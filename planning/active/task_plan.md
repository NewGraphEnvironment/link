# Task: schema_consolidate deletes the destination's log history for every group it copies (#354)

`schema_consolidate()` deletes the destination's rows for a source's bucket from every table with a `watershed_group_code` column before it copies (`data-raw/schema_consolidate.R:279-286`). `<schema>.log` and `<schema>.log_recompute` have that column, so a group consolidated from a cypher loses every earlier run's log row on the dispatcher.

**Approach (approved):** name the history tables once in `.lnk_log_specs()` (with a `run_key`); consolidate DELETEs the bucket from persist tables only and replaces a history table's rows by run key, atomically, through a staged `psql -1 -f` script. Restore the rows #246 lost from the pre-consolidate dump (operator, plan gate).

## Phase 1: Tests first
- [ ] `test-lnk_log.R`: `.lnk_log_specs()` names every table `.lnk_log_create_tables()`
  builds, and each `run_key` is a column of its table and the PK or its leading column
- [ ] New `tests/testthat/test-schema_consolidate.R` (sources the script,
  `skip_if_not(file.exists())` as `test-lnk_fanout_judge.R` does):
  `consolidate_history_sql()` emits the staged replace keyed on `run_key`, no
  `watershed_group_code` predicate
- [ ] Same file, live (`skip_if_no_db()`): on a scratch schema, an earlier run's row survives
  a re-copy of the same group, and a re-copied same `run_id` replaces rather than duplicates
  or collides; restore the old DELETE and watch it go red
- [ ] `test-lnk_pipeline_persist.R`: captured SQL never DELETEs from a `log*` table

## Phase 2: Name the history tables once
- [ ] `.lnk_log_specs()` with `run_key`; `.lnk_log_create_tables()` reads it (DDL unchanged —
  existing DDL tests pass as is)

## Phase 3: Consolidate keeps history
- [ ] Split persist / history tables; DELETE persist only
- [ ] `consolidate_history_sql()` + stage 2 via `psql -1 -f` for history tables
- [ ] Update the comments that describe the bucket DELETE (script header, step 3.5,
  `study_area_run.sh:1389-1392` line refs)

## Phase 4: Docs
- [ ] RUNBOOK §6c: replace "Known exposure" with the history rule; §6c note at ~507 and §8d
  recovery passage (~1268) say the log history survives a re-consolidate
- [ ] NEWS entry (version bump left to `/gh-pr-merge`)

## Phase 5: Restore the lost rows (operator: yes)
- [ ] Extract `log` + `log_input` rows for DUNC, KOTL, LARL, SLOC, PINE from the 22:42 dump
  into a scratch schema (`pg_restore --data-only -t` into a copy), INSERT … ON CONFLICT DO
  NOTHING into `fresh_default`; counts before/after recorded in
  `data-raw/logs/consolidate_history_354/`
- [ ] Re-run `study_area_verify.sql -v run_uid=20261017_004619-3f4c713b -v expected_n=241`
  and `verify_extra.sql`; both pass; `lnk_log_read()` still returns this run's row per group
- [ ] CLAUDE.md #246 status: the four (five, with PINE) groups' earlier log rows restored

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
