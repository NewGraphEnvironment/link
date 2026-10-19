# Progress — study_area_run.sh: a run that stops before its tail leaves no record of which groups it was running (#358)

## Session 2026-10-18

- Plan-mode exploration — phases approved by user
- Created branch `358-study-area-run-sh-a-run-that-stops-befor` off main
- Scaffolded PWF baseline from issue #358 with approved phases
- Next: start Phase 1
- Phase 1: `run_wsgs_write` / `run_expected_from_file` in `study_area_finish.sh`, written by
  the driver after the buckets resolve and again after per-host accounting. Tests red first
  (`command not found`), then green.
- Phase 2: `run_expected_recompute_only` (finish lib) replaces the driver's inline block: file ∪ log,
  `--wsgs=` wins, another run's file is fatal only without `--wsgs=`. Acceptance 1 test: GGGG,
  failed on `job1`, named under "no rows". Finish tests 102 pass / 0 skip.
- Phase 3: driver writes `<TS>_consolidate.tsv` from `res$sources`; `consolidate_outcomes` (finish lib)
  sets `CY_CONS_FAIL` / `CONS_FAILED` / `CONS_EXCLUDED`; `run_finish` takes the excluded set as a
  `not_consolidated` class; `run_expected_from_hosts` drops a failed host's signals; `host_release`
  names the failed stage. Driver carries on only when every source has a recorded outcome and one
  failed; otherwise the old exit. Added a test that runs the driver's own R writer against the reader.
- Phase 4: RUNBOOK §8d (five classes, the run_wsgs file, consolidate carry-on); mutation table in findings; structural driver-wiring test.
- Code-check round 1 (`review-round1.md`): 2 fragile findings, both fixed. (1) a failed host's finished
  group SKIPped elsewhere left the expected set (reproduced); `RUN_SKIP` now subtracts every finished
  group, and `CONS_FAILED` sets `RUN_INCOMPLETE`. (2) a bare `--recompute-only` now keeps the run's
  `not_consolidated` groups out until `--wsgs=` names them. Also: excluded groups join `RUN_WSGS`.
  Each fix mutation-checked. Five new lints fixed (test file back to main's 2).
- Full suite: 3293 pass, 3 fail, 0 skip. Failures pre-existing and untouched by the branch: two
  `lnk_wsg_resolve` closure tests need the :63333 tunnel (down), and the golden ADMS dams pin
  (CLAUDE.md: `cabd.dams` gives 7, the test pins 8).
