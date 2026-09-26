# Progress — Per-bundle habitat thresholds CSV in config.yaml (#282)

## Session 2026-09-25

- Plan-mode exploration — phases approved by user; then "go all phases to pr"
- Gate decisions: log threshold values (new log table + dictionary); `default_tuned` thin via `extends: default`
- Phase 0: #284 review saved on its parked branch (`284-research-calibrate-ch-and-bt-gradient-a`)
- Created branch `282-per-bundle-habitat-thresholds-csv-in-co` off main
- Next: Phase 1
- Baseline suite on main (worktree `../link-baseline-282`): 3 failures, all environmental — `test-lnk_db_conn.R:10`, `test-lnk_wsg_resolve.R:143,154` connect to the down `:63333` tunnel.
- Phase 1: `.lnk_habitat_thresholds_csv(cfg)` + classify/connect default `NULL`. Mutation (hard-wire fresh path in a copy) turns the new tests red. `/code-check` round 1 Clean (`review-round1.md`); rounds 2–3 deferred to a cumulative review of the branch diff before the PR.
