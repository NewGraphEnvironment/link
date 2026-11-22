# Progress — Backlog move 13: The next fresh pin (#481)

## Session 2026-11-22

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate (soul#928)
- Created branch `481-backlog-move-13-the-next-fresh-pin` off origin/main
- Scaffolded PWF baseline from issue #481 with the drafted phases
- Next: parked 2026-11-22; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#481 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `481-backlog-move-13-the-next-fresh-pin`,
parked 2026-11-22 by `/planning-init link#481 park review`, branched from origin/main at be06e2b.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[481-backlog-move-13-the-next-fresh-pin]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-481 481-backlog-move-13-the-next-fresh-pin and cd there
git checkout 481-backlog-move-13-the-next-fresh-pin   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- DESCRIPTION R/lnk_preflight_fresh.R R/lnk_persist_init.R R/lnk_pipeline_persist.R R/lnk_habitat_validate.R R/lnk_log.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_db_conn.R R/lnk_wsg_resolve.R data-raw/pretest_inputs.csv data-raw/pretest.R data-raw/schema_consolidate.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- data-raw/habitat_variants_build.R data-raw/wsg_vignette_data.R data-raw/host_vintage.R data-raw/study_area_buckets.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- tests/testthat/setup.R tests/testthat/test-lnk_preflight_fresh.R tests/testthat/test-pretest.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- tests/testthat/test-lnk_persist_init.R tests/testthat/test-lnk_pipeline_persist.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- tests/testthat/test-lnk_habitat_validate.R tests/testthat/test-lnk_db_conn.R tests/testthat/test-lnk_wsg_resolve.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- RUNBOOK.md CLAUDE.md NEWS.md   # plan files that moved on main since the park
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
