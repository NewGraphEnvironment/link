# Progress — study_area_run.sh: record each phase's start and end per host (#375)

## Session 2026-10-23

- Plan-mode exploration — phases approved by user
- Created branch `375-study-area-run-sh-record-each-phase-s-st` off main
- Scaffolded PWF baseline from issue #375 with approved phases
- Next: start Phase 1
- Phase 1: `data-raw/study_area_phases.sh` + `tests/testthat/test-study_area_phases.R` (11 tests, pass). A stub `date` steps one minute per call, so times, minutes and the critical path are known in advance. Mutants (critical path from first end; open phases closed `ok`; a row write that truncates; a write failure that returns non-zero) each fail at least one test.
