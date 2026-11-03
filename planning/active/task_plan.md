# Task: Province-wide `default` run at v0.78.2: re-model `fresh_default` for every change since 0.68.0 (#454)

`fresh_default` was last built at link 0.68.0 on fresh 0.42.0 (run `20261023_074321-24d85e8c`). Since then #326, #396, #399, #401, #402, #429 and #432 have each changed what `default` models, and each says its groups re-model at the next provincial `default` run. #441 built `fresh_default_minimal` at 0.78.1 on m4 (run `20261102_203300-60ab009d`). #444 joins full segments to the minimal segment they sit in, so it needs `fresh_default` built at the same code, species set and primitives load, in the same database. If never done, `fresh_default` stays at 0.68.0, behind seven modelling changes, and #444 has nothing to join to.

Planned 2026-11-03 on m4 from the worktree `link-breaks` at `73105fbc` (v0.78.2, the tip of `main`). Branch `454-default-run` (the mechanical slug `454-province-wide-default-run-at-v0-78-2-re` ends on a cut word; #441's precedent is `441-minimal-run`). One issue, one PR; the merge is the operator's.

## Decided at the gate

Operator, 2026-11-03, at plan approval.

| Decision | Value | Alternative not taken |
|---|---|---|
| fresh | **0.52.0, the pin as it stands.** m4's installed fresh (0.53.0, `R CMD INSTALL` at 00:36 UTC today, no `RemoteSha`) is reinstalled from the tag with pak so the pre-flight can resolve `fresh_sha`; whoever installed 0.53.0 (the fresh checkout on m4 is on `293-custom-aoi-jobs-delete-whole-watershed-g`) reinstalls it after the run | bump the pin to 0.53.0 (m1 hand install, a wider gate, `fresh_default` on a different fresh than `fresh_default_minimal`) |
| Config, schema | `default` into `fresh_default` | |
| Tokens | `cut-full-top acc-v5 grad-seg q-fwapg` (resolved from the bundle; checked by `--preflight-only`) | |
| Groups | all 241 (`--buckets-exact`, packed `--atom=group`) | |
| Hosts | m4 dispatcher, m1 worker (`--workers=m1`), cloud `job1,job2,job3` | |
| Packing | `study_area_buckets.R --hosts=5 --workers=1 --atom=group --config=default --minutes-schema=fresh_default_history --minutes-exclude=KTSU,OKAN --host-names=m4,m1,cloud,cloud,cloud --plan-out=<log dir>/plan.tsv`; speeds from the learned state (m4 1.11, m1 1.18, cloud 0.95) | pack on `fresh_default_minimal`'s minutes (another network; the state was learned on the history's weights, and #163's convergence wants the same weights run to run) |
| `--recompute-jobs` | 8 | |
| `--statement-timeout` | 30 (default) | |
| `--auto-install` | on (the worker and the cloud hosts assert fresh at the pin) | |
| `--refresh-primitives` | off: the run reads the 2026-11-02 load the minimal build read; the two bchamp objects are HEADed against `hosts_ready_439/load_stamps.csv` just before launch and refreshed only if they moved | |
| Early recompute, each cloud host burned when its leg ends | on (the defaults) | `--recompute-at-end`, `--keep-cyphers` |
| `--preflight-note`, `--pretest-note` | none: a real gate pass is required | |
| `--run-label` | `default-provincial-454` | |
| m1's `fresh_default` (0.68.0, 241 groups, 29 GB) | `ALTER SCHEMA fresh_default RENAME TO fresh_default_20261023` on m1 before the pre-flight: a worker's schema must hold no rows for its bucket; it stays as the 0.68.0 reference beside `fresh_default_20261017` | dropped |
| m4's `fresh_default` (30 groups in `streams`, 4 `log` rows from #326's PCEA/FINA/PARS/LKEL builds at 0.68.6, 1.7 GB) | `DROP SCHEMA fresh_default CASCADE` on m4, then seed it with the 241-group `default` history alone: `CREATE SCHEMA fresh_default; CREATE TABLE fresh_default.log (LIKE fresh_default_history.log INCLUDING ALL); INSERT INTO fresh_default.log SELECT * FROM fresh_default_history.log` (242 rows). The issue keeps nothing of the 30 groups; the seeded `log` is what the gate reads (below), and the run's own rows land beside it under their own `run_uid` (`study_area_verify.sql` is keyed on the run_uid; `verify_extra.sql` check 2 needs each `streams` group's newest row to be the run's, which holds because the drop empties `streams`) | left in place and overwritten group by group; or a borrowed-history gate, which `default` cannot take |
| The gate | `pretest_run.sh --config=default --schema=fresh_default --minutes-exclude=KTSU,OKAN`, **no history flags**, at the run branch's head on a quiet database. The issue's command (`--history-schema=fresh_default_history`) cannot run: `pretest_run.sh:92-94` refuses the flag without `--history-config`, and `pretest.R:375-378` refuses `--history-config=default` for `--config=default` (`default` has `extends: ~`, so its chain is itself; the borrowed path is for a child bundle only, as #450 says). With no flags the pick reads `fresh_default.log`'s own history, which the seeding above makes the 241 groups at `1d00c04c`; `--since` defaults to it, the range is link `1d00c04c` to HEAD and fresh 0.42.0 to 0.52.0 as #441's gate, the scratch is built LIKE a schema holding only `log`, and the verdict writes `fresh_default.log_pretest`, which `pretest_check.R` reads at launch. Expect about 11 picks and about an hour | `--pretest-note` |
| Rehearsal (#418) | not run again: the driver has not changed since the 2026-11-02 rehearsal and run (0.78.2 is records only), and `default`'s path through it is the same | |
| `BCFISHOBS_DIR` | a clean clone of bcfishobs at `dd9a5e5d` in the session scratchpad, as #441 did (#451 is the fix; not this run's work) | |
| Cloud spend | approved through the run's own legs: three `g-8vcpu-32gb` droplets for about 3 to 4 h, about $5 to $8 | |
| #369, #371, #374, #375, #376 | each gets a measured line from this run in its body, and stays open for the operator to close | closed here |
| Not in scope | #259's `fit.R` re-fit, #261's `predictors.R` / `correlations.R` re-run, the `bcfishpass` schema's re-model, #444 itself, #446, #450, #451, the stale first-party installs the check lists (link 0.78.1 installed on m4 is not read: every leg and recompute job runs by `load_all`) | |

Launched detached (`nohup /opt/homebrew/bin/bash data-raw/logs/default_run_454/launch.sh`), so it needs no live session and burns its own hosts. While the driver runs nothing in this worktree changes, the PWF included (each dispatcher group stamps this worktree's HEAD and dirty state).

### Found at planning (2026-11-03, about 09:00 Vancouver time)

- Tailscale to m1 is direct (`tailscale ping -c 3 m1`: 6 ms, no relay); m1 answers over ssh with fresh 0.52.0 (`RemoteSha 245c8d8d`, `RemoteRef v0.52.0`), `fresh_default` 241 groups at 0.68.0, 288 GB free on `/`, no active client.
- m4: no active client, 283 GB free; `fresh_default_history` holds 242 rows (m1 75, cypher-job1 57, job2 68, job3 42, all 0.68.0); `fresh_default_minimal` 241 rows at `cut-min`, 19 GB.
- `doctl` lists two droplets that are not ours to touch (`geopro`, `qwc-prod`); `check.sh`'s burn check counts cypher droplets only.
- `~/Projects/repo/bcfishobs` still holds the two unrelated files (`planning/active/task_plan.md` modified, `duplicates.csv` untracked), HEAD `dd9a5e5d`.
- `fresh_default.log_pretest` does not exist on m4: the `default` gate has never run here, so no record can clear the launch until Phase 2 passes.
- Plan review (2026-11-03, `review-plan.md`): the issue's gate command is refused by the code (above), so the schema is seeded and the gate runs with no history flags; `--preflight-only` does not check a worker's prior rows; the launcher needs `BCFISHOBS_DIR`; the launch flags, `--focal` order, packer names, `check.sh` and the pak reinstall were each verified against the code. The two foreign droplets are ignored by the driver and by `check.sh` (`^cypher-` only). Not verified by the review: the timeline and spend, that m4's `~/.Renviron` sets no `FRESH_GIT_SHA`, that the fresh checkout holds both tags.
- Timeline: Phase 1 about 30 min, the gate about 1 h, the run about 3 to 4 h (the full network at 0.78.2 holds 2 to 3 times fewer segments than the 0.68.0 build the history's 1,077 host-minutes were measured on, and the minimal run modelled at 0.69 of its plan), checks and records about 1 h. About 6 h from approval to the open PR.

## Phase 0: branch and baseline

- [x] Branch `454-default-run` from `origin/main` at `73105fbc`; PWF baseline committed and pushed (the driver refuses a detached HEAD and an unpushed branch).

## Phase 1: hosts ready (no spend)

- [x] m4: `pak::pkg_install("NewGraphEnvironment/fresh@v0.52.0")` and confirm `RemoteSha` equals `git rev-parse v0.52.0^{commit}` (`245c8d8d`), version 0.52.0; record who had 0.53.0 so it can go back after the run.
- [ ] **Refused by auto mode (2026-11-03 15:29 UTC); handed to the operator.** m1: `ALTER SCHEMA fresh_default RENAME TO fresh_default_20261023`; confirm no `fresh_default` schema remains and `fresh_default_20261023.log` holds 242 rows.
- [x] **Renamed, not dropped:** auto mode refused the `DROP` as irreversible, so the schema (30 groups, 8 `log` rows for 4 groups, 3.5 GB) became `fresh_default_dev_20261103`, droppable later. m4: ~~`DROP SCHEMA fresh_default CASCADE` (1.7 GB, nothing kept per the issue)~~, then the seed (`CREATE SCHEMA`, `log` LIKE `fresh_default_history.log` INCLUDING ALL, `INSERT ... SELECT`); confirm `fresh_default` holds `log` alone with 242 rows and that `fresh_default_history` and `fresh_default_minimal` are untouched.
- [x] `BCFISHOBS_DIR`: a clean clone at `dd9a5e5d` in the scratchpad; `git status --porcelain` empty.
- [x] Quiet and reach, written to `data-raw/logs/default_run_454/phase1_hosts.txt`: `tailscale ping -c 3 m1`, ssh round trip, `pg_stat_activity` on both hosts, free disk on both, `doctl compute droplet list` (no `job*` droplet up), the two bchamp objects' `x-amz-version-id` against `hosts_ready_439/load_stamps.csv` (1790057230537, 1793134826715); a move means `snapshot_bcfp.sh --with-bcfp-views --force` on m4 and m1 and a re-check, which does not void the gate.
- [x] `study_area_run.sh --preflight-only --config=default --schema=fresh_default --workers=m1 --cy-workspaces=job1,job2,job3 --auto-install` from the branch: the gate line is expected to refuse (no record yet); fresh, tokens, vintage, credentials, tofu state, ssh, and the worker's reach and database identity must pass. The worker's prior-rows check is not made under `--preflight-only` (`study_area_run.sh:1594-1597`, `NOT CHECKED (workers ...)`); it runs at launch, after the buckets resolve and before any spend, and m1's missing `fresh_default.streams` reads as empty there. Log kept as `checks/preflight_phase1.log`.

## Phase 2: the pre-run gate (#372)

- [x] Quiet check, then `bash data-raw/pretest_run.sh --config=default --schema=fresh_default --minutes-exclude=KTSU,OKAN` (no history flags, per the gate decision above; the seeded `log` is the history) at the branch head. A real pass, recorded in `fresh_default.log_pretest`; its report `data-raw/logs/pretest/<UTC>_default/` committed. An unmapped changed file refuses: map it with its reason (`data-raw/pretest_inputs.csv`) and re-run.
- [x] (Not needed: every pick passed, 0 other sessions seen.) A pick that fails its bound: check for load and other sessions, re-run on a quiet database; `--allow-busy` only if another session holds the database for over 30 min, recorded. A real stall or failure holds the launch and goes to a fix PR (which voids the gate; it runs again).
- [x] `--preflight-only` again, in full, with the log kept (`checks/preflight_only.log`).

## Phase 3: pack and launch

- [x] Pack as decided (`buckets.md`, `buckets.stderr`, `plan.tsv` under `data-raw/logs/default_run_454/`); read the five legs' projected minutes and name the longest.
- [x] `data-raw/logs/default_run_454/launch.sh` on #441's pattern (`minimal_run_441/launch.sh`): the five `--focal` lists in driver order (dispatcher, worker1, job1, job2, job3), `--config=default --schema=fresh_default --run-label=default-provincial-454 --recompute-jobs=8 --statement-timeout=30 --auto-install --buckets-exact --workers=m1 --cy-workspaces=job1,job2,job3`; `PREFLIGHT=1` runs it with `--preflight-only`.
- [x] Launch decisions and the packing written to `progress.md`, committed and pushed before launch.
- [ ] `BCFISHOBS_DIR=<clean clone> PREFLIGHT=1 /opt/homebrew/bin/bash data-raw/logs/default_run_454/launch.sh` passes, then launch detached with `BCFISHOBS_DIR=<clean clone> nohup /opt/homebrew/bin/bash data-raw/logs/default_run_454/launch.sh > data-raw/logs/default_run_454/run.log 2>&1 & disown` (the launcher aborts without the variable); note the launch time with `date -u`. Wait on the driver's own end (a background `until` loop on `run.log`'s final summary line, then a foreground re-read of the exit status and the `<TS>_*` files); nothing in the worktree changes meanwhile.
- [ ] A failed group: the driver carries on and names it; re-model once on m4 under the `run_uid`, then `--recompute-only --run-uid=<uid>` (#348). A kept host holds the only copy of its groups and stays up with its burn command listed.

## Phase 4: checks and records

- [ ] `bash data-raw/logs/rehearsal_418/check.sh <TS> <run_uid> fresh_default <exit> 241 dispatcher worker1 job1 job2 job3` with `CHECK_OUT=data-raw/logs/default_run_454/checks`: driver exit, `study_area_verify.sql` at 241, the negative cases, `recompute_audit.R`, model rows on every host, no host kept, cloud hosts burned, `outside_readers.tsv`.
- [ ] `verify_extra.sql` (`provincial_246/`) at `expected_n=241`; tokens `cut-full-top acc-v5 grad-seg q-fwapg` on all 241 `log` rows, one link sha (the branch's), fresh 0.52.0 with one `fresh_sha`, `link_dirty` false; `tailscale ping m1` after the run beside the pre-launch probe.
- [ ] `host_speeds_calibrate.R --plan=<plan.tsv> --phases=<TS>_phases.tsv`; `host_speeds.tsv` and its history committed (the calibrator's second run toward #163's three).
- [ ] `run.log` redacted with the driver's rule before commit (the launcher's stdout is outside the driver's redaction).
- [ ] `research/study_area_run.md`: a section "The province-wide `default` run (2026-11-03, 241 groups; #454)" with the legs, consolidates, recompute, critical path, size, and each leg against `plan.tsv` (the first run packed on learned speeds); `fresh_default_minimal`'s segment count beside `fresh_default`'s for #444.
- [ ] #377's runs row; measured lines on #369, #371, #374, #375 and #376 (left open for the operator); `CLAUDE.md` Status; RUNBOOK §8d only if the run taught a mechanic. #444's body gains the line that `fresh_default` now exists at the same code.
- [ ] #454's "Before launch" and "Acceptance" boxes ticked in the body, with the gate box's command replaced by the one that ran (no history flags, seeded `log`) and why.

## Phase 5: close

- [ ] `/planning-archive` (README with Measurement and Evidence), `/code-check branch` (three rounds at least, ended on an enumeration of the record's claims, each read from a committed artifact), `/gh-pr-push` with `Fixes #454`. The merge is the operator's.

## What would stop the run, and what to do instead of waiting

| If | Do |
|---|---|
| Auto mode refuses the pak install, a schema drop or rename, the cloud spin, or a push | Say so once and hand over the bare command; do not retry or rephrase. A refused spin falls back to m4 and m1 alone (no spend, slower), re-packed on two hosts. |
| The bchamp objects moved | Refresh both hosts as above, re-check, continue. |
| The gate refuses an unmapped file | Map it with its reason; re-run. |
| The gate refuses on its history (`fresh_default.log` short of 241 groups, or a row it cannot resolve) | The seed is wrong: re-seed from `fresh_default_history.log` whole and re-run `--pick-only` first. |
| A gate pick fails its bound or a pick fails | As Phase 2 says. **No launch on a failed gate.** |
| A group fails in the run | Carry on; re-model under the run_uid on m4, then `--recompute-only` (#348). |
| A host is kept | It stays up, listed with its burn command; recovery per RUNBOOK §8d. |
| m1's link drops mid-leg | The driver keeps m1 and names it; finish on the other hosts, then re-model its missing groups on m4 under the run_uid and `--recompute-only`, or report if the gap is large. |
| A statement hits 30 min | The group fails alone; re-model once at a 60 min bound if nothing else is on the database. |
| Another session loads a database | Wait for quiet up to 30 min before the gate or the launch; during a run watch and report, touch nothing of theirs. |
| Disk below 40 GB | m1: report (never `fresh_default_20261017` or `_20261023`). m4: stop and report. |
| The session ends | The driver is detached and burns its own hosts; `progress.md` is pushed before launch and carries the resume. |

## Owed at the end (reported, done after merge)

- [ ] #444's parent table, now buildable.
- [ ] The calibrator's third run (#163's three-run acceptance) on the run that follows.
- [ ] #259's `fit.R` re-fit and #261's `predictors.R` / `correlations.R` re-run on this run's minutes (named in the record as still owed).
- [ ] fresh 0.53.0 back on m4 for whoever installed it, if they still need it.

## Validation

- [ ] Tests pass (no code changes planned; if the gate forces a `pretest_inputs.csv` row, `test-pretest.R` runs)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: Phase 1 by the probes' output in `phase1_hosts.txt` and `--preflight-only` passing every line but the gate's; Phase 2 by a `pass` row in `fresh_default.log_pretest` and `--preflight-only` passing in full; the run by `check.sh` all PASS, `verify_extra.sql` exit 0, tokens and shas as above, `doctl` listing no `job*` droplet, and the calibrator's rows; the records by `/code-check`'s enumeration of every number against its committed artifact.

**Parked (operator, 2026-11-03).** Approval here writes and pushes the PWF baseline (branch `454-default-run`, this plan as `task_plan.md`, a synchronous Plan review folded in) and stops. Nothing in Phases 1 to 5 runs until the resume block in `progress.md` is pasted into a fresh session; the run-to-PR mandate starts there.
