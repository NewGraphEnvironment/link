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
- Refuted the code-range explanation (`range_hypothesis.*`): SETN is slowest on a narrow range
- `walk_prefilter.R`: same features per segment in 33 of 33 walks; walks 3.6–24.6× faster in eight groups, 1.2× in SETN (output-bound, 4.8 M pairs)
- `predictors.R` gained the sample walk (`probe_us`, `probe_pre_us`); on the nine groups it predicts measured walk seconds at slope 1.00 (`predictors_subset.tsv`)
- Gate decision 2 done: SALR and CHWK re-run from `../link_261_rerun` at `1d00c04c`, all digests unchanged; CHWK 617.6 s of which walks 589.4 s
- Phase 2: `predictors.R` over 241 groups launched 23:01 UTC (frozen copy); `correlations.R` written, not yet run
- Phase 2 done: `predictors.R` 241 groups; `correlations.R`: predicted walk seconds Spearman 0.982 against 10-23 minutes, #261's below-outlet count −0.08; prefilter would save 36–51 % of the pool's summed job time
- Phase 3: README, `research/recompute_cost.md` (+ index row), fresh issue drafted (scratchpad, shown in the final report), #261 body edited with the verdict, #377 measured line filled and a follow-up item added, CLAUDE.md status; RUNBOOK unchanged (no mechanic moved)
- Code-check: three rounds (review-round{1,2,3}.md), ended on round 3's enumeration; tests 4,354 / 0 / 0; merged origin/main (#392, workflows); archived
