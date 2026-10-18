# Task: schema_consolidate deletes the destination's log history for every group it copies (#354)

`schema_consolidate()` deletes the destination's rows for a source's bucket from every table with a `watershed_group_code` column before it copies (`data-raw/schema_consolidate.R:279-286`). `<schema>.log` and `<schema>.log_recompute` have that column, so a group consolidated from a cypher loses every earlier run's log row on the dispatcher.

**Approach (approved):** name the history tables once in `.lnk_log_specs()`; consolidate DELETEs the bucket from persist tables only and replaces a history table's rows by primary key, atomically, through a staged `psql -1 -f` script. Restore the rows #246 lost from the pre-consolidate dump (operator, plan gate).

## Phase 1: Tests first
- [x] `test-lnk_log.R`: `.lnk_log_specs()` names every table `.lnk_log_create_tables()`
  builds, and no log table's PK includes `watershed_group_code` (corrected from `run_key`:
  replace by full primary key, which deletes only rows being rewritten; see findings)
- [x] New `tests/testthat/test-schema_consolidate.R` (sources the script,
  `skip_if_not(file.exists())` as `test-lnk_fanout_judge.R` does):
  `consolidate_history_sql()` emits the staged replace keyed on the primary key, no
  `watershed_group_code` predicate
- [x] Same file, live (`skip_if_no_db()`): on a scratch schema, an earlier run's row survives
  a re-copy of the same group, and a re-copied same `run_id` replaces rather than duplicates
  or collides; restore the old DELETE and watch it go red
- [x] `test-lnk_pipeline_persist.R`: captured SQL never DELETEs from a `log*` table

## Phase 2: Name the history tables once
- [x] `.lnk_log_specs()` (table, cols, pk); `.lnk_log_create_tables()` reads it (DDL unchanged —
  existing DDL tests pass as is)

## Phase 3: Consolidate keeps history
- [x] Split persist / history tables; DELETE persist only; refuse a source before deleting if a log PK is not shared
- [x] `consolidate_history_sql()` + stage 2 via `psql -1 -f` for history tables
- [x] Update the comments that describe the bucket DELETE (script header, step 3.5,
  `study_area_run.sh:1389-1392` line refs)

## Phase 4: Docs
- [x] RUNBOOK §6c: replace "Known exposure" with the history rule; §6c note at ~507 and §8d
  recovery passage (~1268) say the log history survives a re-consolidate
- [ ] NEWS entry — deferred to `/gh-pr-merge`: in this repo NEWS is written by the release commit (`bf1521d3`), not on the branch

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
