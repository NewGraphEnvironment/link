# Progress — One failed group skips the post-consolidate recompute for every group (#348)

## Session 2026-10-18

- Plan-mode exploration — phases approved by user ("Go all phases to PR")
- Created branch `348-one-failed-group-skips-the-post-consolid` off main
- Scaffolded PWF baseline from issue #348 with approved phases
- Next: start Phase 1
- Phase 1: `tests/testthat/test-study_area_finish.R` (8 tests, fixture schema + Rscript stub, real pool functions extracted from the driver); `hosts_bash()` moved to `helper-bash.R`
- Phase 2: `data-raw/study_area_finish.sh` (`run_coverage`, `run_expected_from_log`, `run_finish`); driver gains `--recompute-only --run-uid= [--wsgs=]`, pool block moved above the pre-flight, tail replaced by `run_finish`
- Verified: finish tests 8/8 and hosts tests pass; `bash -n` both; `pool_probe.sh` PASS=37 FAIL=0; recompute_parity/sweep extraction still resolves
- Mutation: a copy of the lib restoring the exit on a missing group fails acceptance tests 1 (6 failures) and 2 (3 failures)
- Live, read-only: `run_coverage` on `fresh_default` for run_uid `20261017_004619-3f4c713b`: expected 241 (from the log), 241/241 recompute, 0 missing
- Phase 3: RUNBOOK §8d gains "A missing group costs only itself" (classes table, recovery commands); CLAUDE.md #348 fact and research/study_area_run.md recovery line updated
