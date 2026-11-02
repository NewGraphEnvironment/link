# Findings — Provincial minimal-breaks run for knowledge's species tuning (#441)

## Measured at planning (2026-11-02 05:08 to 05:25 UTC, m4)

- **Branch `439-fresh-052-gate-borrowed-history` at `0192b90c`** holds exactly one commit over `origin/main` (`eb0e19d2`): the fresh pin 0.48.0 to 0.52.0 in `DESCRIPTION`, `--history-schema` / `--history-config` through `pretest_run.sh`, `pretest_pick.R`, `pretest_verdict.R`, `pretest_check.R`, `pretest.R` (`pretest_history_source()`, `pretest_record_history()`), two columns on `log_pretest`, and 45 lines of tests. It contains `origin/main`. Pushed and tracking.
- **m4 `fresh_default` holds 4 groups** (PARS, PCEA, FINA, LKEL; newest 2026-10-27, link `ae1df6ff`), the same 4 the branch's `--pick-only` picked. `fresh` holds 12 (`bcfishpass` config). No `fresh_default_minimal`.
- **m1 `fresh_default` holds 241 groups**, one `link_sha` (`1d00c04c`), run `20261023_074321-24d85e8c`, 2026-10-23, 1,077 min of `default` modelling; newest rows per group all `link_dirty` false; hosts m1 74 / 314 min, cypher-job2 68 / 260, cypher-job3 42 / 257, cypher-job1 57 / 247. `fresh_default.log` is 242 rows, 352 kB. `1d00c04c` is an ancestor of `origin/main`.
- **Fresh:** m4 has 0.52.0 installed with no `RemoteSha` (no `Remotes`/`RemoteRef` fields; built 2026-11-02 02:31 UTC); m1 has 0.48.0. Tags on the fresh checkout: v0.52.0, v0.51.0, v0.50.1, v0.50.0, v0.49.0.
- **Primitives (`provenance.source_artifact`, `recorded_by = 'loader'`):** m4 2026-10-25 05:40 UTC, m1 2026-10-23 07:44 UTC. The vintage gate allows 7 days.
- **Database state:** m4 fwapg 310 GB free on the volume, 37 `working_*` schemas, `fresh` 27 GB, `fresh_default` 3.5 GB; m1 database volume 115 GB free, `fresh_default_20261017` 32 GB, `fresh_default` 29 GB, 198 `working_*` schemas totalling 128 GB, `fresh_parity361` 3.9 GB, `fresh_parity362` 3.9 GB. One active client on each at the time (this session's).
- **m4 Postgres** runs fresh's full preset from `docker-compose.yml` (`shared_buffers` 32 GB, `work_mem` 2 GB, `maintenance_work_mem` 4 GB, `effective_cache_size` 96 GB, `max_parallel_workers_per_gather` 8, `random_page_cost` 1.1, `effective_io_concurrency` 200, `temp_buffers` 64 MB, `max_connections` 40). rtj's only open PR is #403 (NECR review); fresh#252 is a docs note on `tuning.md`. Nothing to merge for m4.
- **Cloud:** `doctl` reaches the account (two unrelated droplets up); tofu workspaces `default job1 job2 job3`; size `g-8vcpu-32gb`.
- **Connections:** m1 ssh round trip 0.6 s; 20 pings at 0.2 s to m1 and to the gateway, 0 % loss, 12 to 110 ms; DO API 0.2 s.
- **`default_minimal` resolves to** species BT, CH, CM, CO, PK, SK, ST, WCT, GR, paused KO, RB; tokens `cut-min acc-v5 grad-seg q-fwapg`; `observation_breaks top_per_species`, `observation_upstream province`, `cabd_additions_barriers TRUE`.
- **Proof candidates (`pick_groups.sql`, combined rank):** SETN, MORK, COTR, LFRA, BULK, LNTH, SQAM, COWN, ALBN, NECR, SANJ, HARR. Every `default` group is on `cw` (0 rows `mad`).
- **Two idle R processes on m1** from earlier sessions (4 days and 1 day old, 0 % CPU, no database activity).
- **`study_area_run.sh`** reads `LINK_BRANCH` from `git branch --show-current` (line 480) and is FATAL on an empty one with remote hosts; `main` is checked out in `~/Projects/repo/link`, so a run branch is required in this worktree.
- **`pretest_since_covers()`** (`pretest.R:448`) refuses a history with any NULL `link_sha` or dirty row and requires `since` to be an ancestor of every history sha and each sha an ancestor of `end`.
- **`study_area_compare.R`** exits 0 with nothing compared when no group has a modelled species; it does not stop a non-`bcfishpass` run.

## Plan review

`review-plan.md`: one Plan agent, no blocker, four fixes folded into `task_plan.md`.

## Issue context

**If we do it:** "what is left before the minimal-breaks provincial run" is one lookup (`umbrella.sh next` on this issue), and the run starts from a checked list rather than from memory. **If we never do:** the steps sit in six issues and two status notes, and a skipped one (a host on the wrong fresh, stale primitives) surfaces mid-run.

The umbrella of `track:minimal-run`: the next provincial run, built on #415's minimal network so knowledge can tune species on it (knowledge#120 first). Agreed 2026-11-01 (CLAUDE.md status): it runs from m4, with no `default` run first. #432 (KO and RB paused, link 0.76.0) is done.

**Decided 2026-11-02 (operator).**
- **fresh pin: the latest, v0.52.0.** #439's first step is settled, and it lands before #415's proof builds, so the proof tests the code the run uses. This moves that step ahead of row 1's proof builds.
- **The pre-run gate learns to borrow history.** A bundle with no builds of its own could not be gated, so row 4's gate on the minimal schema could not run. The gate takes `--history-schema` and `--history-config`, only from a config the bundle extends and only while it has no builds of its own. It should become its own issue under this umbrella, ahead of the rehearsal.
- **Work in progress:** branch `439-fresh-052-gate-borrowed-history` (`0192b90c`) holds the pin, the gate change and its tests. `test-pretest.R` passes, and a `--pick-only` on `default_minimal` borrowing `fresh_default` picked PARS, PCEA, FINA and LKEL. The real gate has not run. Still owed on that branch: the RUNBOOK section, NEWS, the bump to 0.78.0, the `default_minimal` README and `CLAUDE.md` lines that still say the gate cannot run, the full suite, `/code-check branch`.
- **How the rest runs:** one issue, one PR, one merge at a time, planned with `/planning-init` on this umbrella.
- **Cloud spend:** approved by the operator for the night of 2026-11-01 to 02 ("you can spend on cloud hosts all night"), so spinning hosts for the rehearsal and the run needs no further ask that night. Burn hosts when their legs end. The run's decisions are still stated at launch.

**Order.** The first open row is next.

1. #415: the minimal bundle and its cut token, and its proof builds. In progress.
2. #439: settle the fresh pin (link pins v0.48.0; m4 has 0.52.0), re-prep the cloud hosts and the worker with `--auto-install`, and refresh the primitives (loaded 2026-10-25; the vintage gate allows 7 days).
3. #440: test-group builds of `default` (MURT, KOTL, BULK and one more) and the `bcfishpass` parity re-score at the run's code, after the fresh pin is settled, since the gate and the rehearsal run only the minimal bundle.
4. #418: the rehearsal through the real driver on a few groups across real hosts, after the pre-run gate (#372's `pretest_run.sh`) passes on the minimal schema at the merged code. Include MURT, a group with only paused species present.
5. The run itself, closing this issue: the run's decisions stated at launch (config, a new persist schema, 241 groups, species, flags), packed with `--minutes-schema`, `--host-names`, `--minutes-exclude=KTSU,OKAN` and `--plan-out`, then the host-speed calibrator, and its row on #377.
6. knowledge#120: chinook rearing tuned on the minimal segments, the first consumer.

**Decide before the run, not members:** #398 (CT aliases), #400 (what counts as a known record) and #402 (presence review, KO and RB rows deferred to #432) are on #377's order before the rehearsal; the agreed plan does not wait on them.

### Members

| issue | title |
|---|---|
| #415 | A minimal network for tuning, with parent attributes on the full network |
| #439 | Ready the hosts for the minimal run: the fresh pin, host prep and fresh primitives |
| #440 | Test-group builds of default and bcfishpass at the minimal run's code |
| #418 | A rehearsal before every provincial run: the real driver on a few groups across real hosts |
| knowledge#120 | Tune chinook rearing on minimal segments and map how the cuts move the result |

## Errors Encountered

| Error | Resolution |
|-------|------------|
