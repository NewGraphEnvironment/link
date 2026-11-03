# Progress — Parent attributes on the full network: each segment reads its minimal parent's gradient (#444)

## Session 2026-11-03

- Plan-mode exploration — phases approved by user (parked)
- Created branch `444-parent-attributes-on-the-full-network` off origin/main
- Scaffolded PWF baseline from issue #444 with approved phases
- Next: parked 2026-11-03; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#444 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `444-parent-attributes-on-the-full-network`,
parked 2026-11-03 by `/planning-init link#444 park`, branched from origin/main at 82606e6.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[444-parent-attributes-on-the-full-network]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-444 444-parent-attributes-on-the-full-network and cd there
git checkout 444-parent-attributes-on-the-full-network   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```

## Session 2026-11-03 (resumed)

- Resume checks passed in the `link-breaks` worktree (branch current with origin, main unmoved).
- Phase 1: `lnk_streams_parent()` (`R/lnk_streams_parent.R`), `test-lnk_streams_parent.R` (52 expectations on a two-schema fixture), map row `none`. Each of four planted defects (smallest overlap, no transaction, loose superset, no row count) turns the file red. Full suite: FAIL 0, WARN 6 (all in `test-lnk_csv_sync.R` and `test-lnk_pipeline_access.R`), SKIP 1, PASS 5,273. Lint clean on the new files.
- Phase 2: `data-raw/streams_parent.R` (pair guard over sourced `pretest.R`), `data-raw/streams_parent_build.R` (driver, `--verify`), `test-streams_parent_build.R` (27 expectations: 17 fabricated refusals, the code judgement on mocked diffs, and the real 193cb8aa/4dfbfa49 pair passing while the last `R/lnk_pipeline_break.R` change refuses). Four planted defects in the guard (cut-min, reach, species, fresh pin) each turn it red. `pretest_*` calls carry `nolint: object_usage_linter` (sourced at run time).
- Driver tried on BULK and MORK into the scratchpad: the live pair passes, 2 to 3 s per group. `--verify` named SETN (no rows) and three planted faults (a changed `run_id_full`, a missing row, a row off its length); Phase 4's rebuild replaces those rows. Postgres notices quieted in the driver (`d3014902`).
- Phase 3: `grad-parent` row (`gradient=parent;parent_cut=cut-min`, 0.79.0) and its test (live, no shipped config resolves it, at least four resolve); RUNBOOK §6b "Parent attributes: `streams_parent`", a §8d paragraph on the owed rebuild, the grad row of the axis table; NEWS 0.79.0 entry (the `DESCRIPTION` bump stays the final commit). There is no single provincial-run checklist in §8d, so the line went after "Two post-conditions".
- Phase 4: province built from `a97044e2` (23:02 to 23:06 UTC): pair passed, 241 groups, 3.9 min summed, 5,546,370 rows = `fresh_default.streams`, 96 segments straddle (max 1.000 m), `--verify` all current. `prototype_check.R`: 0 differences in BULK, SETN, MORK, COTR (lengths within 5.5e-12 m). `research/minimal_network.md` gains "Parent attributes"; #444's body ticks four boxes and carries the table's shape for knowledge#120.
