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
