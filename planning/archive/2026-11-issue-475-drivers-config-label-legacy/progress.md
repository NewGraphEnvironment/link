# Progress — Backlog move 7: Drivers: an explicit config, a labelled standalone run, and the legacy path (#475)

## Session 2026-11-22

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate
- Created branch `475-backlog-move-7-drivers-an-explicit-confi` off origin/main
- Scaffolded PWF baseline from issue #475 with the drafted phases
- Next: parked 2026-11-22; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#475 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `475-backlog-move-7-drivers-an-explicit-confi`,
parked 2026-11-23 by `/planning-init link#475 park review`, branched from origin/main at 5be4fb3.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[475-backlog-move-7-drivers-an-explicit-confi]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-475 475-backlog-move-7-drivers-an-explicit-confi and cd there
git checkout 475-backlog-move-7-drivers-an-explicit-confi   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/wsgs_dispatch.sh data-raw/wsgs_run_host.R data-raw/wsgs_run_pipeline.sh data-raw/wsgs_run_m4_offline.sh   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/trifecta_15wsg.sh data-raw/trifecta_smoke.sh data-raw/runs_archive.sh data-raw/buckets_balance.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/progress_check.sh data-raw/state_clean.sh data-raw/cypher_prep.sh data-raw/wsg_compare.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/wsg_pipeline_run.R data-raw/query_schema_delta.R data-raw/study_area_buckets.R data-raw/study_area_run.sh   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/study_area_wsgs.R data-raw/study_area_compare.R data-raw/study_area_finish.sh data-raw/study_area_remote.sh   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/study_area_hosts.sh data-raw/recompute_parity.sh data-raw/recompute_sweep.sh data-raw/wsg_run_one.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/wsg_recompute_one.R data-raw/host_stamp.R data-raw/host_vintage.R data-raw/barriers_views_build.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/parity_crosssection.R data-raw/access_disagree_349.R data-raw/habitat_variants_build.R   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- data-raw/habitat_variants_score.R data-raw/pretest_run.sh data-raw/pretest.R data-raw/worker_prep.sh data-raw/README.md   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- R/utils.R R/lnk_publish.R RUNBOOK.md research/provincial_run_runbook.md research/study_area_run.md research/README.md   # plan files that moved on main since the park
git diff --name-only 5be4fb32683275ab193673505843c7597b159d8d origin/main -- inst/extdata/configs/default/config.yaml tests/testthat/test-pretest.R tests/testthat/helper-study_area_hosts.R   # plan files that moved on main since the park
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
