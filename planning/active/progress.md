# Progress — study_area_run.sh: a run that stops before its tail leaves no record of which groups it was running (#358)

## Session 2026-10-18

- Plan-mode exploration — phases approved by user
- Created branch `358-study-area-run-sh-a-run-that-stops-befor` off main
- Scaffolded PWF baseline from issue #358 with approved phases
- Next: start Phase 1
- Phase 1: `run_wsgs_write` / `run_expected_from_file` in `study_area_finish.sh`, written by
  the driver after the buckets resolve and again after per-host accounting. Tests red first
  (`command not found`), then green.
