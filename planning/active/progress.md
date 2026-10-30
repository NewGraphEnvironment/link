# Progress — Read a fish record at a segment's start as not upstream of that segment (#399)

## Session 2026-10-30

- Plan-mode exploration — phases approved by user (parked)
- Found during exploration: bcfishpass's own observation walk passes `include_equivalents = False` (`load_streams_upstr_observations.sql`, `smnorris/bcfishpass@620dbe43`), so the issue's parity premise was wrong; gate decisions: no bundle key, retire `acc-v1` / `acc-bcfp` for `acc-v2` / `acc-bcfp-2`, measure on m1's local fwapg in `zz399_*` scratch schemas
- Created branch `399-read-a-fish-record-at-a-segment-s-start` off origin/main
- Scaffolded PWF baseline from issue #399 with approved phases
- Plan review run synchronously (one `Plan` agent, 18:21–18:28 UTC): eleven findings, one blocker (the inherited `pre_post_diff.R` direction rule aborts on every expected piece, since no cut moves), all verified and folded into `task_plan.md`; `review-plan.md`
- Next: parked 2026-10-30; paste the block under ### Resume into a fresh session

### Resume

```
Continue link#399 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `399-read-a-fish-record-at-a-segment-s-start`,
parked 2026-10-30 by `/planning-init link#399 park`, branched from origin/main at 804276e.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[399-read-a-fish-record-at-a-segment-s-start]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-399 399-read-a-fish-record-at-a-segment-s-start and cd there
git checkout 399-read-a-fish-record-at-a-segment-s-start   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```
