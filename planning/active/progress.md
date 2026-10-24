# Progress — study_area_run.sh: bound each modelling statement, so a runaway statement fails as a named group (#371)

## Session 2026-10-23

- Plan-mode exploration — phases approved by user
- Measured the default: longest finished group of `20261023_074321-24d85e8c` is SETN 16.3 min (`fresh_default.log`); KTSU 65.4 is the stall
- Created branch `371-study-area-run-sh-bound-each-modelling-s` off main
- Scaffolded PWF baseline from issue #371 with approved phases
- Next: start Phase 1
- Phase 2: `.lnk_timeout_statement()` passes 10/10, including a live cancel through RPostgres (DBI's frames hold the SQL as `statement`). Probe of `wsg_run_one.R` on ADMS: `PGOPTIONS='-c statement_timeout=3s' LNK_TEST_STALL_WSG=ADMS` printed `statement_timeout=3s`, then `TIMEOUT after 3s: SELECT pg_sleep(3600) -- LNK_TEST_STALL_WSG`, rc=1, nothing written; without `PGOPTIONS` it printed `statement_timeout=0` and refused the hook (the control: so `PGOPTIONS` is what reached the connection).
