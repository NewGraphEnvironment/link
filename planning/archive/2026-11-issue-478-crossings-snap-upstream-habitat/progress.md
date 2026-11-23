# Progress — Backlog move 10: Crossings: snapping, and habitat upstream of each crossing (#478)

## Session 2026-11-22

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate (soul#928)
- Created branch `478-backlog-move-10-crossings-snapping-and-h` off origin/main
- Scaffolded PWF baseline from issue #478 with the drafted phases
- Next: parked 2026-11-22; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#478 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `478-backlog-move-10-crossings-snapping-and-h`,
parked 2026-11-23 by `/planning-init link#478 park review`, branched from origin/main at 5be4fb3.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[478-backlog-move-10-crossings-snapping-and-h]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-478 478-backlog-move-10-crossings-snapping-and-h and cd there
git checkout 478-backlog-move-10-crossings-snapping-and-h   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- planning/active/task_plan.md R/lnk_points_snap.R R/lnk_pipeline_pscis_build.R R/lnk_crossings_union.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- R/lnk_wsg_downstream_check.R R/lnk_barriers_unify.R R/lnk_barriers_emit.R R/lnk_aggregate.R R/lnk_vocabulary.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- inst/extdata/vocabulary.csv NEWS.md DESCRIPTION RUNBOOK.md CLAUDE.md tests/testthat/test-lnk_points_snap.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- tests/testthat/test-lnk_aggregate.R data-raw/crossings_parity.R data-raw/query_habitat_thresholds_obs.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/query_habitat_thresholds_mad.R research/bcfishpass_parity.md   # plan files that moved on main since the park
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
The Plan review ran before the park: do not run it again at this resume. This replaces
the review planning.md item 3 runs beside Phase 1. Check only what moved: each file a
git diff line above printed changed on origin/main since the park, so re-read it against
the phase that edits it and correct the plan where the code moved.
Nothing printed means the plan stands.
One exception: anything task_plan.md lists under its "## Open decisions" heading is not
settled. Ask me each before the phase that needs it, move it to the decisions once I
answer, and write a fork you meet yourself under that same heading.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```
