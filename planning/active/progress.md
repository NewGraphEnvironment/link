# Progress — Backlog move 14: Primitive tables in one shape, and a parallel publish (#499)

## Session 2026-11-22

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate (soul#928)
- Created branch `499-backlog-move-14-primitive-tables-in-one` off origin/main
- Scaffolded PWF baseline from issue #499 with the drafted phases
- Next: parked 2026-11-22; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#499 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `499-backlog-move-14-primitive-tables-in-one`,
parked 2026-11-22 by `/planning-init link#499 park review`, branched from origin/main at be06e2b.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[499-backlog-move-14-primitive-tables-in-one]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-499 499-backlog-move-14-primitive-tables-in-one and cd there
git checkout 499-backlog-move-14-primitive-tables-in-one   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- data-raw/snapshot_bcfp.sh data-raw/snapshot_bcfp_lib.sh data-raw/habitat_publish.R data-raw/pretest.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- data-raw/pretest_inputs.csv data-raw/state_clean.sh R/lnk_publish.R R/lnk_artifact.R R/lnk_export_inputs.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_downstream.R tests/testthat/test-snapshot_bcfp_lib.R tests/testthat/test-lnk_publish.R tests/testthat/test-pretest.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- RUNBOOK.md DESCRIPTION NEWS.md CLAUDE.md data-raw/logs/cabd_shape_494/ data-raw/logs/publish_parallel_488/   # plan files that moved on main since the park
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

## Phase 1, 2026-11-22 (resume)
- Owner answered the four gate questions: 1a, 2a, 3 not ready, 4a (all recommended).
- Reproduced #494 on one saved CABD response, found the real cause (a database's first GDAL load), built `cabd_load()` as a staging table and rebuild, proved it from three starting states and against two mutants; PSCIS checked. Scratch databases dropped.
- Next: Phase 2.
