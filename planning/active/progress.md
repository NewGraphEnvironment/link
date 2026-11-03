# Progress — Province-wide `default` run at v0.78.2: re-model `fresh_default` for every change since 0.68.0 (#454)

## Session 2026-11-03

- Plan-mode exploration on m4 (worktree `link-breaks`); phases approved by the operator as a parked baseline (fresh stays at 0.52.0, reinstalled from the tag on m4)
- Created branch `454-default-run` off origin/main at `73105fbc` (v0.78.2)
- Scaffolded PWF baseline from issue #454 with approved phases
- Next: parked 2026-11-03; paste the block under ### Resume into a fresh session

## Session 2026-11-03 (resumed, 15:28 UTC)

- Phase 0 confirmed: branch on origin at `53c7e555`, main merged (already up to date).
- fresh: m4's 0.53.0 (an `R CMD INSTALL` from `~/Projects/repo/fresh` on branch `293-custom-aoi-jobs-delete-whole-watershed-g`, HEAD `142b34d`, built 2026-11-03 00:36 UTC, no `RemoteSha`) replaced by pak from `v0.52.0`: `RemoteSha 245c8d8d`, the same as m1. Reinstall 0.53.0 from that checkout after the run if it is still wanted.
- **m1 rename refused by auto mode** (no reason given). Handed to the operator; the launch waits on it, the gate does not.
- **m4 drop refused** as irreversible; the reversible route ran instead: `fresh_default` renamed to `fresh_default_dev_20261103` (3.5 GB, droppable later), a new `fresh_default` seeded with `log` LIKE `fresh_default_history.log` (242 rows, `run_id` text with no default). The four `token_*` columns are absent from the 0.68.0 log; `.lnk_log_create_tables()` adds them at the first run open.
- `BCFISHOBS_DIR`: clean clone at `dd9a5e5d` in the session scratchpad.
- Probes (`data-raw/logs/default_run_454/phase1_hosts.txt`): m1 direct over Tailscale, both databases quiet, 283 and 287 GB free, no cypher droplet, bchamp objects unmoved (1790057230537, 1793134826715), fresh 0.52.0 on both.
- `--preflight-only` (`checks/preflight_phase1.log`): every line passes but the gate (no `log_pretest` yet), as planned.
- Next: the gate, on a clean tree at this commit.
- Gate (15:32 to 16:24 UTC, at `68a6196f`, no history flags): **PASS**, 11 of 11, 0 other sessions seen. Minutes this run against last build: SETN 7.7/16.3, BULK 4.8/13.7, QUES 15.5/9.3 (bound 28.0), LFRA 4.2/6.6, TOAD 4.8/6.0, HARR 3.4/5.7, UPCE 2.0/3.7, OKAN 2.8/3.7 (median), TAKL 2.3/3.2, HORS 1.8/2.6, SAJR 1.0/1.6. Report `data-raw/logs/pretest/20261103_153249_default/`, log `checks/gate.log`.

- `--preflight-only` in full after the gate (`checks/preflight_only.log`): exit 0, the gate line passes.
- **Packed** (`data-raw/logs/default_run_454/buckets.md`, `plan.tsv`): `LNK_LOAD=loadall Rscript data-raw/study_area_buckets.R --hosts=5 --workers=1 --atom=group --config=default --focal=<fresh's 246 groups> --minutes-schema=fresh_default_history --minutes-exclude=KTSU,OKAN --host-names=m4,m1,cloud,cloud,cloud --plan-out=.../plan.tsv`. 241 modelable (5 dropped by presence), 1,015 dispatcher-equivalent min in all. Learned speeds m4 1.107, m1 1.183, cloud 0.947. Groups and raw minutes per host: m4 52 / 219, m1 55 / 234, job1 45 / 188, job2 45 / 188, job3 44 / 187; every host's load 197 to 198 dispatcher-equivalent min, job2 the longest by a fraction. Component atoms would give 231.
- **Launch decisions** (as the gate table, unchanged): `default` into `fresh_default`, 241 groups `--buckets-exact`, m4 dispatcher, m1 `--workers=m1`, `job1,job2,job3`, `--recompute-jobs=8 --statement-timeout=30 --auto-install`, no `--refresh-primitives`, `--run-label=default-provincial-454`, `BCFISHOBS_DIR` the scratchpad clone. `launch.sh` holds the five lists in driver order; checked against `plan.tsv` (same 241, no duplicate). `PREFLIGHT=1` passes (`checks/preflight_launch.log`).
- **Launch held:** m1 still holds `fresh_default` (16:25 UTC); the operator runs the rename, then the launch is one command (below).

#### Launch, once m1's rename is done

```
cd ~/Projects/repo/link-breaks && BCFISHOBS_DIR=<clean bcfishobs clone at dd9a5e5d> nohup /opt/homebrew/bin/bash data-raw/logs/default_run_454/launch.sh > data-raw/logs/default_run_454/run.log 2>&1 & disown
```

### Resume

```
Continue link#454 from its parked PWF baseline. Repo ~/Projects/repo/link, branch `454-default-run`,
parked 2026-11-03 by `/planning-init link#454 park`, branched from origin/main at 73105fb.
Run these in order, and stop at the first that fails; each failure means what it says:

cd ~/Projects/repo/link && git fetch -q origin
git worktree list | grep -F '[454-default-run]' || echo none   # a path printed: that tree holds the branch; cd to it and skip the checkout
git branch --show-current; git status --porcelain --untracked-files=no   # another branch with changes, or one another session may be on: do not check out here; git worktree add ../link-454 454-default-run and cd there
git checkout 454-default-run   # fails: the branch is not on origin
git pull --ff-only   # fails: this machine has commits origin lacks; resume where they were made
git merge origin/main   # a conflict: main moved meanwhile; resolve it, commit, and go on

Then read planning/active/task_plan.md, findings.md, progress.md and review-plan.md if present.
The gate decisions, the measurements and the Plan-agent review are already folded in:
do not re-plan and do not re-ask them.
Start Phase 1 and run every phase to the PR (/code-check branch, /planning-archive,
/gh-pr-push). This message is the resume instruction that starts the run-to-PR
mandate; the merge stays with me.
```
