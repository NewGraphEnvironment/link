# Progress — Backlog move 8: The rules builder and dimensions.csv as the source of truth (#476)

## Session 2026-11-22

- Explored and drafted the phases. There was no plan gate in this pane, so the plan is parked for the coordinator's plan gate.
- Created branch `476-backlog-move-8-the-rules-builder-and-dim` off origin/main.
- Scaffolded the PWF baseline from issue #476 with the drafted phases.

### Resume

```
Continue link#476 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `476-backlog-move-8-the-rules-builder-and-dim`,
parked 2026-11-23 by `/planning-init link#476 park review`, branched from origin/main at 8c40e19.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[476-backlog-move-8-the-rules-builder-and-dim]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-476 476-backlog-move-8-the-rules-builder-and-dim and cd there
git checkout 476-backlog-move-8-the-rules-builder-and-dim   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- R/lnk_rules_build.R R/lnk_log.R R/lnk_mapping_code.R R/lnk_pipeline_mapping_code.R R/lnk_pipeline_run.R R/lnk_config.R   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- R/lnk_config_verify.R R/lnk_vocabulary.R R/lnk_pipeline_prepare.R data-raw/build_rules.R data-raw/regen_provenance.R   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- data-raw/wsg_recompute_one.R data-raw/habitat_variants_build.R data-raw/habitat_variants_score.R   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- data-raw/habitat_score/variants_364.csv data-raw/habitat_score/wsg_roles_364.csv data-raw/habitat_score/README.md   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- data-raw/pretest_inputs.csv data-raw/recompute_readers.R data-raw/audit_configs.R data-raw/sync_bcfishpass_csvs.R   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- data-raw/logs/wetland_door_364/README.md data-raw/logs/rearing_diff_324/README.md data-raw/logs/build_minutes.csv   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/dictionary_dimensions.csv inst/extdata/configs/default/dimensions.csv   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/default/rules.yaml inst/extdata/configs/default/config.yaml   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/default/parameters_habitat_thresholds.csv inst/extdata/configs/default/species_modelled.csv   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/default/README.md inst/extdata/configs/bcfishpass/dimensions.csv   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/bcfishpass/rules.yaml inst/extdata/configs/bcfishpass/config.yaml   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/bcfishpass/parameters_fresh.csv inst/extdata/configs/bcfishpass/presence_groups.csv   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/configs/default_rearbreaks/README.md inst/extdata/parameters_habitat_rules.yaml   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- inst/extdata/parameters_habitat_dimensions.csv inst/extdata/vocabulary.csv tests/testthat/test-lnk_rules_build.R   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- tests/testthat/test-dictionaries.R tests/testthat/test-lnk_pipeline_run.R tests/testthat/test-lnk_config.R   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- tests/testthat/test-pretest.R tests/testthat/test-lnk_vocabulary.R .github/workflows/sync-bcfishpass-csvs.yml .Rbuildignore   # plan files that moved on main since the park
git diff --name-only 8c40e192c0aba6067fc96d0bdd40d3f3f3fc22de origin/main -- research/habitat_thresholds.md RUNBOOK.md CLAUDE.md NEWS.md DESCRIPTION planning/backlog.md   # plan files that moved on main since the park
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

## Session 2026-11-23 (resume, m1)

- Merged origin/main twice (0.88.0 at the resume, 0.91.0 before release); fresh 0.56.0 installed on m1 for main's pin.
- Decisions 1 to 8 answered (all the recommended option). Phases 1 to 7 landed: dictionaries render and validate (#75), residence from dimensions.csv (#189, rest in #512), the sample from `default` and fresh PR #332's sync workflow (#129), the order-1 exception scored and declined (#327), #212 / #316 / #86 closed by decision.
- Phase 1's build took 706.5 min (KLUM 363, FRCN 200); its first score was refused by the validator, which led to `log_variant_pass()` in the harness and a backfill.
- Tests 1,553: 0 failed (6 warnings, also on main). check(): 0 errors, 0 warnings, 3 notes (all on main). `/code-check branch`: round 1 clean; round 2, two fragile README findings; round 3, a defect inside round 2's escaping fix; ended on an enumeration (888 cells through cmark-gfm).
- Commits: 06fddf28..HEAD on this branch.
