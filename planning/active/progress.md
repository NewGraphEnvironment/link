# Progress — Provincial minimal-breaks run for knowledge's species tuning (#441)

## Session 2026-11-01

- Plan-mode exploration from the `link-breaks` worktree (synced to `origin/main` at `eb0e19d2`); phases presented and reviewed by one Plan agent (`review-plan.md`, no blocker, four fixes folded in)
- Parked by the operator at the gate: the plan was presented for a single overnight approval, and the operator chose to park instead. The baseline carries the full decision set so the resume runs without re-asking it
- Checked out the existing branch `439-fresh-052-gate-borrowed-history` (`0192b90c`, one commit over `origin/main`) rather than cutting a new one, as the operator asked: the pin and the gate change are built on, not redone
- Scaffolded PWF baseline from issue #441 with the approved phases and the decisions at the gate
- Next: parked 2026-11-01; paste the block under ### Resume into a fresh session

## Session 2026-11-01 (22:36 Vancouver onward)

- Phase 0 done, then Phase 1's gate issue (#442), the loader and the guards. `/code-check branch` and PR to follow.
- The operator's resume keeps the merge: this run stops short of `/gh-pr-merge` at each PR.
- Code-check over the branch, three rounds. Round 1: one build of the bundle's own ended the short-history guard; the launch refusal named a remedy that fails. Round 2, inside round 1's fix: two lines still assumed a borrowing bundle has no own rows, two judgements exited as "could not run", no route for a group added after both histories. Round 3, same family: a bad own build read as a bad borrowed history. Ended on an enumeration (`findings.md`, "Code-check enumeration"; round 3's message table; `data-raw/logs/gate_borrow_442/messages.txt`).
- A full suite run showed 16 validator failures after I killed an earlier run mid-file; the file alone passes 470, and a clean full run passes 5,232 with 0 failed.

- Phase 2 on branch `415-proof-builds-lifts`, stacked on PR #443 (the merge is the operator's): `lifts.R` committed before the builds; `run.sh` on BULK, SETN, MORK, COTR at `6bf9ca06` (47 min, every step passed); `proof.R` every check passed; `lifts.R` both controls passed; review found it counted barrier positions as cuts, so it now counts segment starts too, with a control that can fail (final CSVs from `lifts.R` as of `ac52e150`). Parent tables gzipped (11.8 to 3.7 MB). Filed #444 (parent attributes); #415's body ticked.

- Phase 3 (PR #447): default test builds identical to their last builds; bcfishpass parity 48/50 on m1; m1's GitHub token refused, fresh installed with remotes; #446 filed (reference pin reads a CSV-sync row).
- Phase 4 (PR #448): m4 and m1 primitives refreshed, same object versions, vintage line passes.
- Phase 5: the gate passed on default_minimal (11 picks, link `24b2cbb3`). The rehearsal's first try stopped at the worker's prep (URL check against m1's insteadOf rule); fixed in `worker_prep.sh`; the second try passed every check.
- Reviewer agents this session: three rounds per PR for PRs 1 to 5, above the five-per-task bound because each PR has its own floor.

### Resume

```
Continue link#441 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `439-fresh-052-gate-borrowed-history`,
parked 2026-11-02 by `/planning-init link#441 park`, branched from origin/main at eb0e19d.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[439-fresh-052-gate-borrowed-history]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-441 439-fresh-052-gate-borrowed-history and cd there
git checkout 439-fresh-052-gate-borrowed-history   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```
