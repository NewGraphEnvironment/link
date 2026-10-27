# Progress — Why is CHWK 20x SALR at 80% of its size? (#261)

## Session 2026-10-27

- Plan-mode exploration — phases approved by user
- Created branch `261-why-is-chwk-20x-salr-at-80-of-its-size-t` off main (`deeb5b56`)
- Scaffolded PWF baseline from issue #261 with approved phases
- Plan review (background Plan agent) folded in: `review-plan.md`, dispositions in `findings.md` (`4b56a351`)
- Phase 1 harness `walks.R` ran nine groups on m1, 20:32–21:31 UTC, one session; first two attempts refused (another session's `COPY`, then my own concurrent `psql`). `fresh_default` write counters unchanged
- Result: the walk's cost is the per-feature GiST probe over 7.24 M province-wide features, not the pairs; CHWK's probe is 9x SALR's. Walks are 59–106 % of each group's logged minutes
- `walks.R` gained the read-only guard (G6) after the run; `predictors.R` rewritten with the range and outer-row terms and an ancestor prefilter on the below-outlet count
- Worktree `../link_261_rerun` at `1d00c04c` for the instrumented re-run (loads fresh 0.43.0, the run used 0.42.0)
