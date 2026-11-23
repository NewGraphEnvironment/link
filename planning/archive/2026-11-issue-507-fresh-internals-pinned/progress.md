# Progress — Backlog move 18: fresh's internals pinned by argument, at fresh 0.56.0 (#507)

## Session 2026-11-23

- Explored and drafted the phases; no plan gate in this pane: parked for the coordinator's plan gate
- Created branch `507-backlog-move-18-fresh-s-internals-pinned` off origin/main
- Scaffolded PWF baseline from issue #507 with the drafted phases
- Next: parked 2026-11-23; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#507 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `507-backlog-move-18-fresh-s-internals-pinned`,
parked 2026-11-23 by `/planning-init link#507 park review`, branched from origin/main at b89d315.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[507-backlog-move-18-fresh-s-internals-pinned]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-507 507-backlog-move-18-fresh-s-internals-pinned and cd there
git checkout 507-backlog-move-18-fresh-s-internals-pinned   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only b89d3150a0ad5fdc0808c441d48a09250af2ca88 origin/main -- R/lnk_preflight_fresh.R tests/testthat/test-lnk_preflight_fresh.R DESCRIPTION RUNBOOK.md NEWS.md CLAUDE.md   # plan files that moved on main since the park
git diff --name-only b89d3150a0ad5fdc0808c441d48a09250af2ca88 origin/main -- man/lnk_preflight_fresh.Rd data-raw/pretest_inputs.csv data-raw/pretest.R data-raw/pretest_run.sh   # plan files that moved on main since the park
git diff --name-only b89d3150a0ad5fdc0808c441d48a09250af2ca88 origin/main -- data-raw/pretest_reach_fresh.R data-raw/study_area_run.sh data-raw/cypher_prep.sh data-raw/worker_prep.sh   # plan files that moved on main since the park
git diff --name-only b89d3150a0ad5fdc0808c441d48a09250af2ca88 origin/main -- data-raw/logs/fresh_pin_481/ data-raw/query_habitat_thresholds_mad.R R/lnk_pipeline_connect.R R/lnk_config.R   # plan files that moved on main since the park
git diff --name-only b89d3150a0ad5fdc0808c441d48a09250af2ca88 origin/main -- R/lnk_discharge.R R/lnk_pipeline_persist.R R/lnk_pipeline_classify.R R/lnk_stamp.R tests/testthat/test-pretest.R   # plan files that moved on main since the park
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

## Session 2026-11-23 (resume, build)

- Nothing moved on main since the park; the owner's 0.56.0 decision moved into the plan's decisions.
- Phase 1 (304c7e72): internals pinned by ordered signature; mutation proof red on 3 tests.
- Phase 2 (a4f75802): `getFromNamespace()` drift guard; mutation proof red in a worktree.
- Phase 3 (ad2381c1, 565e4478): fresh v0.56.0 pinned; reach unchanged (19 files), map unchanged; suite and `devtools::check()` on scratch 0.56.0 (0 errors, 0 warnings, 5 notes, one of them ours and fixed); builds in `data-raw/logs/fresh_pin_507/`.
- Phase 5: the gate's pick at 565e4478 (`pick_20261123_183614/`), no unmapped file.
- `/code-check branch`: round 1 one fragile finding (compare.R did not check the groups were built; 702aafff), round 2 clean, round 3 one fragile (a non-closure at an internal's name passed; 83072945), round 4 clean.
- The first build job waited 60 min for a quiet database (another session's statements, one 3.8 h old) and then crawled; stopped at 19:24 UTC, its orphaned backend cancelled, and relaunched with `QUIET_MAX_MIN=0`: minutes carry that load, digests do not.
