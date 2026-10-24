# Progress — study_area_run.sh: record each phase's start and end per host (#375)

## Session 2026-10-23

- Plan-mode exploration — phases approved by user
- Created branch `375-study-area-run-sh-record-each-phase-s-st` off main
- Scaffolded PWF baseline from issue #375 with approved phases
- Next: start Phase 1
- Phase 1: `data-raw/study_area_phases.sh` + `tests/testthat/test-study_area_phases.R` (11 tests, pass). A stub `date` steps one minute per call, so times, minutes and the critical path are known in advance. Mutants (critical path from first end; open phases closed `ok`; a row write that truncates; a write failure that returns non-zero) each fail at least one test.
- Phase 2: driver and finish lib wired (prep, refresh, model, account, consolidate, burn, coverage, views, recompute, compare). Plan review folded in (B1 burn status, B2 no duplicate row on close, G4 table from the trap, O2 failing `date`, S1 recompute-only prep row, X2 wrapper pins). Tests: phases 15, finish 35, hosts 38, prepare 48, all pass; mutants for the close-skip, the `date` fallback and the printed flag each fail one test.
- Next: Phase 3, the dispatcher-only acceptance run from a worktree.
