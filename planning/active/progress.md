# Progress — Tuning iterations: measure where a threshold variant's time goes (seven steps, two of them verification) (#404)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user
- Created branch `404-tuning-iterations-measure-where-a-thresh` off main
- Scaffolded PWF baseline from issue #404 with approved phases
- Next: start Phase 1
- Phase 1: fresh v0.44.0 installed on m4 (gate decision 3), vintage gate OK, campaign README
  run decision written
- Phase 2: seven step timers + discharge_join, persist_init, base_model, base_recompute rows
  into `variant_timing.csv`; `write_thresholds()` quoting fixed (found by `--step=bundles`)
- Plan review folded (`review-plan.md`)
- Phase 3: base build launched 2026-10-28 19:09:47 UTC from worktree at `45b12b2e`
  (`build_base.log`); `launch_state.txt` holds the load and `pg_stat_activity` at launch
- Phase 4 script `analyze.R` drafted and run on synthetic rows while the base builds
