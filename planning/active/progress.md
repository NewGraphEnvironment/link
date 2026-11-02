# Progress — A minimal network for tuning, with parent attributes on the full network (#415)

## Session 2026-11-01

- Plan-mode exploration — phases approved by user (parked)
- Created branch `415-a-minimal-network-for-tuning-with-parent` off origin/main
- Scaffolded PWF baseline from issue #415 with approved phases
- Next: parked 2026-11-01; paste the block under ### Resume into a fresh session

## Session 2026-11-02 (run-to-PR)

- Phases 1 to 4 landed. Plan corrected: `0.77.0`, because PR #437 holds `0.76.0`; the token test compares `default_minimal` with `default`, so #437's `acc-v5` needs no edit in it.
- Smoke on ADMS at `e287abcb`: 15,781 full and 11,985 minimal segments, every minimal cut matched exactly, no access difference, every break named. Swapping the schemas in a copy of `proof.R` fired three guards. Schemas dropped.

### Resume

```
Continue link#415 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `415-a-minimal-network-for-tuning-with-parent`,
parked 2026-11-02 by `/planning-init link#415 park`, branched from origin/main at 2a5d881.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[415-a-minimal-network-for-tuning-with-parent]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-415 415-a-minimal-network-for-tuning-with-parent and cd there
git checkout 415-a-minimal-network-for-tuning-with-parent   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```
