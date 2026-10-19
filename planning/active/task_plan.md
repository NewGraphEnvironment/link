# Task: One failed group skips the post-consolidate recompute for every group (#348)

In `study_area_run.sh`, one failed group skips the post-consolidate recompute for every group in the run. The coverage check after consolidate asks whether every run group has rows in `<schema>.streams`, and `exit 1`s on the first miss. The recompute (`lnk_access(merge = TRUE)`, the correctness guarantee for cross-group access) comes after it. So when one group fails to model, the groups that did model lose their recompute and the compare. The gate also tests for rows, not rows from this run, so a failed group that still holds an earlier run's rows passes it unremarked.

Design: `/Users/airvine/.claude/plans/quiet-hopping-umbrella.md` (approved 2026-10-18), summarised in findings.md.

## Phase 1: Tests first (fixture schema, failing)
- [x] Move `hosts_bash()` to `tests/testthat/helper-bash.R`, so both shell-lib test files share it; `test-study_area_hosts.R` still passes
- [x] `tests/testthat/test-study_area_finish.R`: build a scratch schema with `skip_if_no_db()` + `.lnk_log_create_tables()` + a minimal `streams`. Groups:
  - AAAA, BBBB closed this run, with rows;
  - CCCC open row this run, no rows;
  - DDDD rows plus another run's row;
  - EEEE closed this run, no rows.
- [x] Test: `run_coverage` splits into recompute / norows / stale / lost exactly
- [x] Test: a `done` signal admits a group with rows and no closed row
- [x] Test: a missing `streams` table is unknown (non-zero), never "all missing"
- [x] Test: `run_expected_from_log` returns AAAA, BBBB, CCCC, EEEE
- [x] Test (acceptance 1): `run_finish` with one missing group calls the stubbed pool and compare with exactly the recompute set, returns 1, and names the missing group
- [x] Test (acceptance 2): zero groups with rows: the pool and compare are not called, it returns 1, and it says why
- [x] Test: the driver refuses `--run-uid` alone, `--recompute-only` alone, a malformed uid, and `--recompute-only --focal=…` (all exit before any Rscript)

## Phase 2: `data-raw/study_area_finish.sh` + driver wiring
- [x] Write the lib (`run_coverage`, `run_expected_from_log`, `run_finish`) and move the tail into `run_finish` with the changes above
- [x] Driver: new flags and validation, move the pool function block above the pre-flight, add the `--recompute-only` branch, normal path calls `run_finish`; update the header usage and "Post-conditions" comment
- [x] `bash -n` both scripts; Phase 1 tests pass; `pool_probe.sh data-raw/study_area_run.sh` still passes (the extraction still works)

## Phase 3: Docs
- [ ] RUNBOOK §8d: the coverage classes, recompute over this run's finished groups, `--recompute-only --run-uid` recovery (replace the "coverage FATAL" wording at ~`:1291`)
- [ ] `CLAUDE.md` #246 status fact on #348: state the new behaviour
- [ ] `research/study_area_run.md`: one line where the run's recovery is described, if it names the coverage exit

## Phase 4: Verification
- [ ] Mutation: restore `exit 1` on missing in a copy of the lib (`LNK_TEST_FINISH_LIB`), and confirm acceptance test 1 goes red
- [ ] Live, read-only: `run_coverage` against `fresh_default` for run_uid `20261017_004619-3f4c713b` with the 241 groups gives 241 recompute and 0 missing (no recompute run)
- [ ] `devtools::test()` full suite, `lintr` on the new test file

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
