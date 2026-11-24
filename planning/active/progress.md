# Progress — Backlog move 11: What blocks access at a barrier (#479)

## Session 2026-11-24

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate (soul#928)
- Created branch `479-backlog-move-11-what-blocks-access-at-a` off origin/main
- Scaffolded PWF baseline from issue #479 with the drafted phases
- Next: parked 2026-11-24; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#479 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `479-backlog-move-11-what-blocks-access-at-a`,
parked 2026-11-24 by `/planning-init link#479 park review`, branched from origin/main at c7abea1.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[479-backlog-move-11-what-blocks-access-at-a]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-479 479-backlog-move-11-what-blocks-access-at-a and cd there
git checkout 479-backlog-move-11-what-blocks-access-at-a   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- R/lnk_pipeline_prepare.R R/lnk_barriers_unify.R R/lnk_barriers_emit.R R/lnk_barriers_views.R R/lnk_barrier_overrides.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- R/lnk_pipeline_persist.R R/lnk_persist_init.R R/lnk_pipeline_classify.R R/lnk_pipeline_break.R R/lnk_pipeline_crossings.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- R/lnk_crossings_union.R R/lnk_pipeline_run.R R/lnk_observation_records.R R/lnk_presence_check.R R/lnk_vocabulary.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- R/lnk_log.R R/lnk_access.R R/lnk_aggregate.R R/lnk_downstream.R R/lnk_scenario_export.R R/lnk_wsg_deps.R R/lnk_thresholds.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- R/lnk_score.R R/lnk_source.R R/lnk_pipeline_load.R R/lnk_db_conn.R inst/extdata/thresholds_default.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- inst/extdata/vocabulary.csv inst/extdata/configs/default/config.yaml inst/extdata/configs/bcfishpass/config.yaml   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- inst/extdata/configs/default/parameters_fresh.csv inst/extdata/configs/bcfishpass/parameters_fresh.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- inst/extdata/configs/default/overrides/user_barriers_definite_control.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- inst/extdata/configs/default/overrides/user_barriers_definite.csv inst/extdata/configs/default/parameters_barrier_rules.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- inst/extdata/configs/bcfishpass/parameters_barrier_rules.csv inst/extdata/configs/dictionary_parameters_barrier_rules.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- inst/extdata/configs/dictionary_parameters_barrier_lifts.csv data-raw/study_area_verify.sql   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- data-raw/study_area_verify_negative.sh data-raw/recompute_deps.R data-raw/schema_consolidate.R data-raw/pretest_inputs.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- data-raw/audit_configs.R data-raw/regen_provenance.R data-raw/wsg_run_one.R data-raw/wsg_recompute_one.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- data-raw/wsg_species_presence_check.R data-raw/wsg_species_presence_map.R data-raw/logs/crossings_upstream_478/stamp.csv   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- tests/testthat/test-lnk_pipeline_prepare.R tests/testthat/test-lnk_barriers_unify.R tests/testthat/test-lnk_barriers_emit.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- tests/testthat/test-lnk_pipeline_persist.R tests/testthat/test-lnk_pipeline_crossings.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- tests/testthat/test-lnk_barrier_overrides.R tests/testthat/test-lnk_observation_records.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- tests/testthat/test-lnk_vocabulary.R tests/testthat/test-dictionaries.R tests/testthat/test-lnk_persist_init.R   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- tests/testthat/test-pretest.R tests/testthat/setup.R RUNBOOK.md CLAUDE.md NEWS.md DESCRIPTION planning/backlog.md   # plan files that moved on main since the park
git diff --name-only c7abea1365b746dcb4a1929a8aef23c869b0e239 origin/main -- research/README.md research/barrier_rules.md research/bcfishpass_parity.md   # plan files that moved on main since the park
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
