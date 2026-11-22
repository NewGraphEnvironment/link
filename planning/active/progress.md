# Progress: Backlog move 3 (#471)

## Session 2026-11-22

- Plan-mode exploration; phases approved by the owner as `park review`
- Plan review ran before the baseline; corrections folded into task_plan.md (review-plan.md)
- Created branch `471-backlog-move-3-docs-and-a-check-that-fails` off origin/main; claim on #471 replaced by the branch
- Scaffolded the PWF baseline
- Next: parked 2026-11-22; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#471 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `471-backlog-move-3-docs-and-a-check-that-fails`,
parked 2026-11-22 by `/planning-init link#471 park review`, branched from origin/main at be06e2b.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[471-backlog-move-3-docs-and-a-check-that-fails]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-471 471-backlog-move-3-docs-and-a-check-that-fails and cd there
git checkout 471-backlog-move-3-docs-and-a-check-that-fails   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- .github/workflows/R-CMD-check.yaml CLAUDE.md README.md DESCRIPTION data-raw/study_area_buckets.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- data-raw/study_area_remote.sh tests/testthat/test-lnk_pipeline_prepare.R R/lnk_access.R R/lnk_barrier_overrides.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_compare_mapping_code.R R/lnk_compare_rollup.R R/lnk_crossings_union.R R/lnk_pipeline_load.R R/lnk_pipeline_prepare.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_pipeline_pscis_build.R R/lnk_rules_build.R R/lnk_stamp.R R/lnk_wsg_downstream_check.R R/lnk_wsg_resolve.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_pipeline_access.R R/lnk_pipeline_mapping_code.R R/lnk_barriers_unify.R R/lnk_load.R R/lnk_source.R research/README.md   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- research/study_areas.md research/study_area_run.md research/study_area_scope_and_funders.md   # plan files that moved on main since the park
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
