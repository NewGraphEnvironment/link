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

## Session 2026-10-28 (continued, after the base build)

- Base build exited 20:19:54 UTC (69.6 min; launched 19:09:47 UTC from the worktree at
  `45b12b2e`): 17 `base_model` rows summing 67.1 min (KOTR 7.0 min longest, LPCE 1.7
  shortest), 9 `base_recompute` rows summing 2.4 min, no Error line. No other backend on
  the database at launch or at the base end; 1-minute load 2.2 to 4.2 through the run.
- `analyze.R`: the last "done in" line per pass wins across `build_*.log` (REVL is re-run
  by the full pass after the pre-flight and `variant_timing.csv` replaces its rows, so a
  first-match lookup would have compared the full run's seconds with the pre-flight's total).
- Pre-flight `--step=variants --only=bt_rear_wet_p10 --wsgs=REVL` launched 20:20:36 UTC
  (`build_preflight_revl.log`).
- Next: check the pre-flight's step sum against its total, then the full nine-group pass.
- Pre-flight exited 20:21:46 UTC: the variant's seven steps sum to 20.7 s and the `default`
  pass's four to 17.8 s, each printed as 0.3 min. `analyze.R` ran clean on a copy of the
  pre-flight data (its residual tolerance was `0.05 / 60` min, below the log's 0.1 min
  print precision; now 0.05 min).
- Full pass `--step=variants --only=bt_rear_wet_p10` launched 20:22:17 UTC
  (`build_variants.log`), no other backend on the database.
- Full pass exited 20:36:26 UTC (13.8 min over nine groups, `default` then the variant;
  145 timing rows). `analyze.R` on the real rows: variant pass 5.6 min over nine groups,
  classify 36.5 / connect 30.9 / persist 30.3 / digests 0.4 %; `default` pass 6.8 min; four
  jobs over groups 1.6 and 1.8 min. No step's median share reaches half, so no statement
  depth. README filled (builds, measurement, verdict, evidence); verdict added to #377's
  iteration-speed list; classify and connect minutes per group posted on fresh#275;
  `CLAUDE.md` status and `NEWS.md` bullet written; #404's acceptance boxes ticked.
- Worktree removed. Next: tests, `/code-check branch`, archive, PR.
