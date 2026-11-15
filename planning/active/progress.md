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
- Plan review landed (2026-11-15 ~00:15 UTC): `planning/active/review-487.md`; dispositions in
  `findings.md`. Folded into Phases 2-4.
- Phase 4: `--stall-sample-after` (both legs, refused under `--recompute-only` and at or above
  the bound), `run_stalls` in the finish lib. `test-study_area_finish.R` 48/48,
  `test-study_area_remote.R` 22/22, `test-lnk_pipeline_prepare.R` 56/56, `test-lnk_stall.R` 39/39,
  `test-pretest.R` 155 pass. Mutants red: samples line printed without a file (1 of 4 stall
  tests), `STALL_WSGS` never set (2 of 4), marker neutralising removed (1 failure).
- Phase 5 (2026-11-15 00:14-00:23Z): run `20261115_001427-474338b7` (NBNK, EUCH stalled) wrote
  `20261115_001427_stall_EUCH.tsv` (4 PgSleep rows) and named it on the TIMEOUT-following line,
  in the summary and under the statement; EUCH re-modelled through a pipe, which closed 1.2 s
  after R exited; `--recompute-only` exit 0. A worker leg was not run: m1 and m4 hold
  different modelled crossings since 2026-11-13, so the pre-spend compare refuses it. Scratch
  schema dropped, worktree removed. Evidence `data-raw/logs/stall_sample_487/`.
- The banner printed "every 60 s" under `LNK_STALL_EVERY_S=15`: it now prints the variable.
- Full suite at `e82c64bb` (2026-11-15 00:20-00:35Z): `[ FAIL 3 | WARN 7 | SKIP 1 | PASS 5839 ]`.
  The three are `test-lnk_db_conn.R:10` and `test-lnk_wsg_resolve.R:143,154`, each
  `lnk_db_conn()` refused on port 63333 (the `PG_*_SHARE` tunnel, not up on m1 tonight); neither
  file nor its code changed on the branch.
- `devtools::check()` at `6a6f2e6c`: 1 error (the same three tunnel tests), 3 warnings and 3
  notes, none naming a file this branch adds (non-ASCII in older R files, Rd cross-refs and
  usage, `setNames` globals).
- code-check round 1 (2 findings, both fixed in `1ca5ac5e`): the default threshold refused
  `--statement-timeout=1..10` alone; stall lines split the readers line.
- code-check round 2 (2 findings, both fixed): the `stall samples:` line was a proxy
  (`bound > threshold`) that round 1's 0.5 min default made false most of the time, a defect
  inside the previous fix; now the sampler creates a marker with its first row and the line
  waits for it, and checks run every `min(every_s, after_s)`. `cut` in `run_stalls` now runs
  `LC_ALL=C` (macOS `/usr/bin/cut` stops at an invalid byte; GNU cut is first on PATH on m1,
  so the test cannot show it red here). One-group checks: a row and the line at 0.5 min; no
  row and no line at 5 min.
