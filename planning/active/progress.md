# Progress — Provincial minimal-breaks run for knowledge's species tuning (#441)

## Session 2026-11-01

- Plan-mode exploration from the `link-breaks` worktree (synced to `origin/main` at `eb0e19d2`); phases presented and reviewed by one Plan agent (`review-plan.md`, no blocker, four fixes folded in)
- Parked by the operator at the gate: the plan was presented for a single overnight approval, and the operator chose to park instead. The baseline carries the full decision set so the resume runs without re-asking it
- Checked out the existing branch `439-fresh-052-gate-borrowed-history` (`0192b90c`, one commit over `origin/main`) rather than cutting a new one, as the operator asked: the pin and the gate change are built on, not redone
- Scaffolded PWF baseline from issue #441 with the approved phases and the decisions at the gate
- Next: parked 2026-11-01; paste the block under ### Resume (Phase 6, after the operator merges #443, #445, #447, #448 and #449 in that order)

```
Continue link#441 at Phase 6 (the run). Repo ~/Projects/repo/link (worktree link-breaks on m4).
Phases 0 to 5 are merged; read planning/active/task_plan.md (launch decisions at the top), findings.md, progress.md.
Before launch: cut a run branch from main and push it; --preflight-only must pass in full (the gate record at 24b2cbb3
stands while it is an ancestor and no watched path changed); clear or route around ~/Projects/repo/bcfishobs's
uncommitted files (BCFISHOBS_DIR at a clean clone, as the rehearsal did); HEAD the two bchamp objects against
data-raw/logs/hosts_ready_439/load_stamps.csv. Then pack, launch detached, and run the verifiers, the audit and the
calibrator, as task_plan.md's Phase 6 says. Cloud spend is approved through the run's own legs.
```

## Session 2026-11-02 (merges)

- The operator had the five PRs merged in order, each after the previous merge's CI went green: #443 (`57cb86e3`, tagged v0.78.0), #445 (`55c2b616`), #447 (`481dc8d3`), #448 (`794ddd0e`), #449 (`c87ba267`). The four after #443 ship only a RUNBOOK paragraph and a test, so they released together as v0.78.1 (`fd91d1b7`, no code change). #415, #440 and #442 closed; #439 and #418 stay open.
- The gate's record at `24b2cbb3` stands: it is an ancestor of `main`, and `DESCRIPTION` maps to `none` in `pretest_inputs.csv` (only the fresh pin is compared), so the 0.78.1 bump does not void it.
- Filed #450 (the gate finds its history through `extends:` and from a committed minutes record, so a new bundle or a brand-new database gates with no flags; provisional lean recorded in its body). Not this run's work.
- Run branch `441-minimal-run` cut from `main` at `552f43d6` for Phase 6. Commit and push this entry before launch, then nothing in the worktree changes while the run is in flight.
- m1's refused token is most likely an expired PAT (`~/.Renviron` `GITHUB_PAT` or the git credential store); renewing it is the operator's. It matters only if `--auto-install` has to move fresh on m1.
- Next: the resume block above, from this branch.

## Session 2026-11-02 (launch, Phase 6)

- Branch `441-minimal-run` pushed and tracking. The two bchamp objects HEAD at 20:30 UTC to the versions in `hosts_ready_439/load_stamps.csv` (observations 1790057230537, crossings 1793134826715): no refresh.
- `~/Projects/repo/bcfishobs` still holds the two files that are not this work's; routed around with `BCFISHOBS_DIR` at a fresh clean clone at its HEAD `dd9a5e5d` (session scratchpad), as the rehearsal did.
- Quiet: no other active client on m4 or m1 at 20:31 UTC. m1's database volume 112 GB free.
- Packed (`data-raw/logs/minimal_run_441/buckets.md`, `plan.tsv`): `study_area_buckets.R --hosts=5 --workers=1 --atom=group --config=default_minimal` on fresh's 246 groups, minutes from `fresh_default_history`, KTSU and OKAN at the median, names `m4,m1,cloud,cloud,cloud`. 241 modelable (5 dropped by presence), 48 / 49 / 48 / 48 / 48 groups, 202 to 203 dispatcher-equivalent min per host (1,012 in all); m4 takes the median speed (no learned row yet).
- Launch decisions as at the top of `task_plan.md`, unchanged: `default_minimal` into `fresh_default_minimal`, tokens `cut-min acc-v5 grad-seg q-fwapg`, 241 groups `--buckets-exact`, m4 + m1 (`--workers=m1`) + `job1,job2,job3`, `--recompute-jobs=8`, `--statement-timeout=30`, `--auto-install`, no `--refresh-primitives`, early recompute, cloud hosts burned as their legs end, no note flags, `--run-label=minimal-provincial-441`. Command: `data-raw/logs/minimal_run_441/launch.sh` (`PREFLIGHT=1` for the no-spend pass).
- From launch until the driver exits nothing in this worktree changes. Resume after a lost session: read `data-raw/logs/minimal_run_441/run.log` and the driver's `data-raw/logs/study_area_run/<TS>_*`; the driver burns its own hosts.

## Session 2026-11-02 to 03 (the run, Phase 6)

- Pre-flight passed in full at `193cb8aa` (gate record at `24b2cbb3`, 11 picks; primitives 0.5 d; credentials, tofu, worker). Launched detached 20:33 UTC with `minimal_run_441/launch.sh`; run_uid `20261102_203300-60ab009d`.
- Host pre-flight passed on all five (parity, primitives). Legs: m1 87.4 min (49), m4 103.3 (48), job2 159.8, job3 168.1, job1 183.0 (48 each); no failed group, no statement bound. Consolidates m1 47.6 min (Tailscale relay, ~700 KB/s), cloud 12.8 to 13.3 min; each cloud host burned as its leg ended. Early recompute 21:51 to 00:15 UTC. Driver exit 0 at 00:21 UTC, critical path 228.2 min.
- Checks (`minimal_run_441/checks/`): `check.sh` all PASS (verify at 241, negative cases, audit 2,191 of 2,191 pairs, model rows on every host, no host kept, no droplet up, outside readers written); `verify_extra.sql` exit 0; 241 rows with tokens `cut-min acc-v5 grad-seg q-fwapg`, one fresh sha, one link sha, clean.
- Calibrator: cloud 0.95, m1 1.18, m4 1.11 (run-wide ratio 0.693). Commits `193cb8aa` (pack, launch), then the evidence.
- Written: `research/study_area_run.md` section, RUNBOOK §8d worker relay note, `CLAUDE.md` Status, #377's runs row.
- The launcher's `run.log` held three droplet addresses (outside the driver's redaction); redacted with the driver's rule before commit.
