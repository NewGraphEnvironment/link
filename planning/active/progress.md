# Progress — Backlog move 1: The parent gradient on the full network, and the grad tokens (#469)

## Session 2026-11-09

- Plan-mode exploration — phases approved by user (parked)
- Gate: #462 reported as transfer cost; #420 closed with a doc line; proof on four groups
- Created branch `469-backlog-move-1-the-parent-gradient-on-th` off origin/main (`3c0ab0bc`)
- Scaffolded PWF baseline from issue #469 with approved phases
- Next: parked 2026-11-10; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#469 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `469-backlog-move-1-the-parent-gradient-on-th`,
parked 2026-11-10 by `/planning-init link#469 park`, branched from origin/main at 3c0ab0b.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[469-backlog-move-1-the-parent-gradient-on-th]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-469 469-backlog-move-1-the-parent-gradient-on-th and cd there
git checkout 469-backlog-move-1-the-parent-gradient-on-th   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```

## Session 2026-11-12

- Resumed in worktree `link-al_461`; merged `origin/main` (0.80.0, #465) cleanly, so the release is 0.81.0.
- Phase 1: `grad-fwa` row, #420's doc line, test. Verified no link segment crosses an FWA
  segment boundary (BULK, `fresh_default`: 0 of 42,458).
- Phase 2: `pipeline: gradient:` (`R/lnk_gradient_parent.R`, mapped `any`), `default_parent`,
  the grad spec, the judgement before the log opens and the swap after break, `verify_groups()`
  on the shared state SQL; `.lnk_streams_parent_builds()` moved out of the `none` file.
  Tests: vocabulary 75, gradient parent 79, config 220, pretest 126, dictionaries 154 (line
  refs in `dictionary_species_modelled.csv` moved +6 with `lnk_config.R`).
- `/code-check` rounds 1 to 3 on the #463 code and `proof.R` (`cb1b052a`, `06daef04`,
  `6f0eea81`; findings in `data-raw/logs/grad_parent_463/review-round*.md`).
- Phase 3: 0.81.0 bumped (`eaaedf29`); `streams_parent_build.R --verify` passed for the four
  groups before building (`verify_before/`); `run.sh BULK SETN MORK COTR` built control
  (`zz469_control`) and parent (`fresh_default_parent`) for all four at `6f0eea81`, exit 0.

## Session 2026-11-13

- `proof.R` wrote `builds.csv`, `segments.csv`, `gradient.csv`, `access.csv` (all checks there
  pass: same segments in control, parent and `fresh_default`; parent gradient equals
  `gradient_minimal` on every segment, 10,053 to 13,433 changed per group; access identical),
  then stopped: Docker Desktop was closed and m4 restarted, so habitat, `habitat_classes.csv`,
  `near_river_462.csv` and `verdict.csv` were never written. Restarted Docker and `fresh-db`
  (06:35 UTC, recovering from WAL); session wrapped up on the owner's word before re-running.
- Next: once `psql -h localhost -U postgres -d fwapg -c 'select 1'` answers, check the four
  groups' rows survived recovery (`segments.csv` counts), run the A1 artifact comparison, then
  `Rscript data-raw/logs/grad_parent_463/proof.R --wsgs=BULK,SETN,MORK,COTR` from this worktree;
  then Phase 4.
