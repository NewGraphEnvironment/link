# Progress — Backlog move 16: Rainbow trout back in default, and the presence review's last rows (#501)

## Session 2026-11-22

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate (soul#928)
- Created branch `501-backlog-move-16-rainbow-trout-back-in-de` off origin/main
- Scaffolded PWF baseline from issue #501 with the drafted phases
- Next: parked 2026-11-22; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#501 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `501-backlog-move-16-rainbow-trout-back-in-de`,
parked 2026-11-22 by `/planning-init link#501 park review`, branched from origin/main at be06e2b.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[501-backlog-move-16-rainbow-trout-back-in-de]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-501 501-backlog-move-16-rainbow-trout-back-in-de and cd there
git checkout 501-backlog-move-16-rainbow-trout-back-in-de   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_observation_records.R R/lnk_species_pooling.R R/lnk_presence_measures.R R/lnk_presence_check.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_barrier_overrides.R R/lnk_vocabulary.R R/lnk_config.R R/lnk_pipeline_species.R R/lnk_pipeline_prepare.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- R/lnk_pipeline_break.R data-raw/wsg_species_presence_check.R data-raw/wsg_species_presence_map.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- data-raw/pretest_inputs.csv data-raw/habitat_diff_segments.R data-raw/streams_parent_build.R inst/extdata/vocabulary.csv   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- inst/extdata/wsg_regions.csv inst/extdata/configs/default/species_modelled.csv   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- inst/extdata/configs/default/species_pooling.csv inst/extdata/configs/default/parameters_fresh.csv   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- inst/extdata/configs/default/presence_groups.csv inst/extdata/configs/default/wsg_species_presence_review.csv   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- inst/extdata/configs/default/overrides/wsg_species_presence_overlay.csv   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- inst/extdata/configs/dictionary_species_modelled.csv inst/extdata/configs/dictionary_species_pooling.csv   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- tests/testthat/test-lnk_config.R tests/testthat/test-lnk_observation_records.R tests/testthat/test-lnk_barrier_overrides.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- tests/testthat/test-lnk_csv_sync.R tests/testthat/test-lnk_vocabulary.R tests/testthat/test-lnk_pipeline_species.R   # plan files that moved on main since the park
git diff --name-only be06e2b497394e1ddb011e84d7c06b61067cf428 origin/main -- tests/testthat/test-lnk_log.R RUNBOOK.md research/species_presence.md research/output_vocabulary.md   # plan files that moved on main since the park
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
