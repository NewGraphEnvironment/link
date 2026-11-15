# Progress — Record what a stalled statement is waiting on while it stalls (#487)

## Session 2026-11-14

- Plan-mode exploration — phases approved by user
- Created branch `487-record-what-a-stalled-statement-is-waiti` off origin/main (`e5acee31`)
- Scaffolded PWF baseline from issue #487 with approved phases
- Next: start Phase 1
- Phase 1: tests written first. Red at `4585ae0d` + tests (2026-11-15 ~00:20 UTC):
  `test-lnk_stall.R` 6 of 6 error (`.lnk_stall_lines`, `.lnk_loadavg_parse`,
  `.lnk_stall_snapshot`, `.lnk_stall_watch` not found); `test-study_area_finish.R`'s three
  stall tests: `run_stalls` not found (error), the report test 3 failures (no `stall samples:`
  line, no `samples:` under the statement), the `wsg_run_one.R` structural test 1 failure + error
  (no `stall samples:` line in `name_timeout()`).
- Found while probing: RPostgres `dbSendQuery()` blocks until the statement returns, so a test's
  stalled session runs in a background Rscript, found by `application_name`; `count(*)` from
  `pg_stat_activity` arrives as `integer64` (cast `::int`); `tools::pskill(pid, 0L)` is TRUE for a
  live pid and FALSE for a dead one on macOS.
- Phase 2: `R/lnk_stall.R` and `data-raw/wsg_stall_sample.R`; `test-lnk_stall.R` 37/37 pass. A first run of the watch test failed because `sh -c 'sleep 4 & echo $!'` holds system2's stdout pipe until the sleep exits (redirected the sleep); `test-pretest.R` passes with the two new map rows.
- Phase 3: `wsg_run_one.R` starts the sampler after the bound check and prints
  `stall samples:` after a TIMEOUT line when the bound outlasted the threshold. One group
  end to end (2026-11-15 00:07Z, m1, ADMS under `LNK_TEST_STALL_WSG`, bound 1 min,
  `LNK_STALL_AFTER_MIN=0.25`, `LNK_STALL_EVERY_S=10`): four `PgSleep` leader rows, the TIMEOUT
  and `stall samples:` lines, exit 1, no sampler process left 4 s later
  (`data-raw/logs/stall_sample_487/wsg_run_one_adms.log`).
