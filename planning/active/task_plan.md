# Task: Provincial minimal-breaks run for knowledge's species tuning (#441)

The umbrella of `track:minimal-run`: the next provincial run, built on #415's minimal network so knowledge can tune species on it (knowledge#120 first). It runs from m4, with no `default` run first. #432 (KO and RB paused, link 0.76.0) is done. The "Decided 2026-11-02" block of the issue is settled: fresh pinned at v0.52.0 before the proof builds, the pre-run gate borrows history from a config the bundle extends, cloud spend approved for the night of 2026-11-01 to 02. One issue, one PR, one merge at a time, in the checklist's order, `/code-check branch` before each PR and `/gh-pr-merge` after it. knowledge#120 stays out of this run.

Planned 2026-11-01 about 22:15 Vancouver time on m4, from the detached worktree `link-breaks`, on branch `439-fresh-052-gate-borrowed-history` (`0192b90c`: the pin, the gate change and its tests), which this plan builds on rather than redoes. **Parked at the gate (operator, 2026-11-01): the baseline is this file; nothing below has run.**

## Decided at the gate

Operator, 2026-11-01, on a parked approval. The approval covers the baseline; the decisions below are the ones the resume runs on without asking again, unless the resume message says otherwise.

### Launch decisions: the provincial run

| Decision | Value | Alternative not taken |
|---|---|---|
| Config, schema | `default_minimal`, `fresh_default_minimal` (new) | |
| Tokens | `cut-min acc-v5 grad-seg q-fwapg` (resolved from the bundle) | |
| Groups | all 241 (`--buckets-exact`, packed `--atom=group`) | |
| Species | modelled BT, CH, CM, CO, PK, SK, ST, WCT, GR; paused KO, RB (resolved) | |
| Hosts | m4 dispatcher, m1 worker, cloud `job1,job2,job3` (`g-8vcpu-32gb`) | only three tofu workspaces exist |
| Packing | `study_area_buckets.R --hosts=5 --workers=1 --atom=group --minutes-schema=fresh_default_history --minutes-exclude=KTSU,OKAN --host-names=m4,m1,cloud,cloud,cloud --plan-out=<log dir>/plan.tsv` | |
| `--recompute-jobs` | 8 | past 8 the database is the limit |
| `--statement-timeout` | 30 (default) | |
| `--auto-install` | on, for the worker | |
| `--refresh-primitives` | off: refreshed in #439, so the gate and rehearsal read what the run reads | on, which would reload after the gate |
| `--recompute-at-end`, `--keep-cyphers` | off: early recompute, each host burned when its leg ends | |
| `--preflight-note`, `--pretest-note` | none: the run needs a real gate pass and fresh primitives | |
| `--run-label` | `minimal-provincial-441` | |
| Dams, mapping code | on, the driver's path (`LNK_GUARD_DOWNSTREAM=warn`, `LNK_HABITAT_GATE=0` until the recompute) | |

Launched detached with `nohup /opt/homebrew/bin/bash`, so it needs no live session and burns its own hosts. Then: `host_speeds_calibrate.R`, `study_area_verify.sql` with `expected_n=241`, `data-raw/logs/provincial_246/verify_extra.sql` and `recompute_audit.R`.

### The rehearsal (#418): run once by hand

Run the real driver once at the run's code, with #418's check list written down as a committed check script (`data-raw/logs/rehearsal_418/check.sh`, in logs so it cannot void the gate) and its result in the record. **#418 stays open** for the gated script: picker, `log_rehearsal`, launch refusal and seeded failures in each class. Why not the gated script now: it edits `study_area_run.sh`'s pre-flight just before the run, each seeded failure needs real hosts, it is 3 hours or more, and the one launch it would guard is guarded by the hand check, because the run is not launched on a failed check.

- Hosts: m4, m1 and two cloud hosts, so two cloud legs finish at different times; four `--focal` lists for four hosts.
- Groups, by #418's rule: a reader and the group it reads on different hosts (line rule, `recompute_deps.R`), a main-stem group with a reader, one group per host, small minutes, MURT included. Named in the record with why.
- Schema: scratch `zz418_rehearsal`, created first (`--pretest-note` cannot record into a missing schema), with a note naming the gate record in `fresh_default_minimal`. Dropped when done.

### Other standing approvals

- Cloud spend through the end of the run's own legs, even past the night. About $0.16 per host-hour (2026-08-31), about $5 in all. Hosts burn when their legs end; a kept host holds the only copy of its groups and stays up.
- Filing without body review: the gate issue and the parent-attribute issue, in our own repo.
- m1 cleanup only if its database disk falls below 40 GB free (115 GB at planning): drop `fresh_smoke*`, `zz399_*`, `zz401_*`, `fresh_parity362`, whose write-ups have landed. Never `fresh_default` or `fresh_default_20261017`. The operator can make more room if asked.
- #418 left open when #441 closes, with a note on both.
- One swap from the checklist's order: #440's test builds (Phase 3) before #439's primitive refresh (Phase 4), so the builds compare code against code on the loads their baselines were built on. #439's fresh install on m1 does not wait.
- The only m1 data copied is `fresh_default.log` (242 rows, 352 kB), for the gate's picks and bound and for packing on minutes.

### What was found at planning that the issue does not cover

1. The gate's picks on m4 are hollow: m4's `fresh_default` holds 4 groups, and the branch's `--pick-only` picked exactly those 4 (PARS, PCEA, FINA, LKEL). The 241-group history (`20261023_074321-24d85e8c`, link `1d00c04c`, fresh 0.42.0) is only on m1. All 241 newest `default` rows there are clean at `1d00c04c`, an ancestor of `main`, so `pretest_since_covers()` accepts them; `--since` defaults to that sha, a range of link 0.68.0 to 0.78.0 and fresh 0.42.0 to 0.52.0, so expect 8 to 12 picks.
2. The driver dies on a detached HEAD (`LINK_BRANCH` empty is FATAL with remote hosts), and `main` is checked out by `~/Projects/repo/link`: the rehearsal and the run each launch from a pushed branch cut from `main`.
3. m4's fresh 0.52.0 has no `RemoteSha` (installed by `R CMD INSTALL`), so the pre-flight cannot resolve `fresh_sha`: reinstall from the tag.
4. Primitives are stale on both hosts (m4 2026-10-25, m1 2026-10-23, past the 7-day gate); m1 is on fresh 0.48.0.
5. #440's "last build" is not one comparison: m4's `zz432_post` (fresh 0.52.0, link `a6942b5d`: BULK, MURT, KOTL, KETL, NBNK, SALR) is the near baseline for the code; m1's `fresh_default` is the last provincial build at fresh 0.42.0. No fresh 0.48.0 build of these groups exists at this config, so the 0.48 to 0.52 move cannot be isolated on `default`; parity against `fresh_parity361` reports the move across the whole range.
6. Postgres: m4's `fresh-db` runs the full tuned preset line for line with fresh's `docker-compose.yml`; m1 has rtj#379's; cloud hosts get theirs at prep. fresh#252 is a docs note. Nothing to merge.
7. Connections at planning: m1 ssh round trip 0.6 s, 0 % loss on 20 pings to m1 and the gateway, jitter 12 to 110 ms, DO API 0.2 s.

### Timeline (estimates)

Phases 1 to 5 about 7 to 9 hours (PR 1 about 1.5 h with CI; proof builds about 2.5 h; #440 about 1.5 h, m4 and m1 in parallel; gate 0.5 to 1 h; rehearsal about 1 h plus its PR). 2026-10-23's 1,077 host-minutes over five hosts is about 215 min per leg; the minimal network has fewer segments, so the legs are 3 to 4 hours, the recompute tail about an hour (overlapped since #374). From a resume at a given time, add about 11 to 13 hours to the run's end.

## Phase 0: prove the dependencies first (about 15 min, under $0.20)

- [x] PWF baseline on `439-fresh-052-gate-borrowed-history` (parked, 2026-11-01). The PWF carries forward through each PR and is archived by the last.
- [x] Install fresh from the tag on m4 and confirm `RemoteSha` equals `v0.52.0^{commit}`.
- [x] Copy m1's `fresh_default.log` into m4's `fresh_default_history` (242 rows, `pg_dump -t`) and confirm the count and the 4 hosts.
- [x] Connection probes written to the record: 60 pings to m1 and the gateway (loss and jitter), ssh round trip to m1 three times, DO API time. Loss above 1 % or a round trip above 3 s is reported before anything is spun.
- [x] `study_area_run.sh --preflight-only --config=default_minimal --schema=fresh_default_minimal --workers=m1 --cy-workspaces=job1,job2,job3` on this branch. The gate and vintage failures are expected; the credential, tofu state, ssh and worker reach lines must pass.
- [x] Spin and burn `job1` with `cypher_up.sh` and `cypher_down.sh`: a real test of the DigitalOcean, S3 state, ssh and Tailscale paths, and of whether auto mode allows it.
- [x] Report any failure to the operator right away.

## Phase 1: PR 1, the fresh pin and the gate (new issue, attached to #441 ahead of #418)

- [x] File the gate issue, label `track:minimal-run`, add its row to #441, and record the m4 history finding.
- [x] `data-raw/pretest_history_load.sh`: copies a host's `<schema>.log` into a named local schema by `pg_dump -t` (so the primary key and indexes come too), taking the host as an argument.
- [x] Refuse a borrowed history short of the config's modelable groups, in the pick and in the launch check, and make `--pick-only` refuse, not warn, on a history the launch check would refuse (a row with no `link_sha`, or a dirty or unknown `link_dirty`). Tests, plus a mutation proving each guard fires.
- [x] Load `fresh_default_history`. `--pick-only` with `--since` from the 241-group history: the range is fresh 0.42.0 to 0.52.0, so an unmapped file refuses here. Fix the map (`data-raw/pretest_inputs.csv`) if it does, and read fresh's NEWS 0.49.0 to 0.52.0.
- [x] What the branch still owes: RUNBOOK §8d section, NEWS, 0.78.0, the `default_minimal` README and `CLAUDE.md` lines saying the gate cannot run.
- [x] Full suite (5,232 expectations, 0 failed), `/code-check branch` (three rounds, ended on an enumeration), `/gh-pr-push`. `/gh-pr-merge` is the operator's (resume message, 2026-11-02). Ticks #439's pin box; `Relates` #439 and #441.

## Phase 2: PR 2, #415's proof builds and research

- [x] Add `data-raw/logs/minimal_breaks_415/lifts.R`, committed before the builds (`run.sh` refuses tracked changes), answering **how far observation lifts move the minimal cuts**. Shaped by the plan review:
  - `barrier_overrides` holds observation, habitat-classification and control lifts with no source column, so the counterfactual is built, not filtered: copy the group's working tables into a scratch schema, rebuild `barrier_overrides` there with an empty observations table (the other lifts stay), and call `link:::.lnk_pipeline_prep_minimal()` on it, so classes, presence, paused species, orphans and subsurface flow are the build's own. The built `gradient_barriers_minimal` minus that is the observation lifts' effect.
  - Cuts are the whole `break_order` (gradient minimal, falls, definite), so km that changes is measured on the full cut set.
  - `lifts.csv`: observation lifts, cuts removed, cuts added above a lift, how far each moved, km of segment that changes.
  - `lifts_obs.csv`: `compare.R`'s #433 measure, so it reads beside `research/species_paused.md`: records of modelled species on a changed segment, and the median and largest gradient shift.
  - Runs before Phase 3 rebuilds BULK: `wsg_run_one.R` keeps `working_<wsg>`, and the #440 build would replace it.
- [x] Groups: **BULK, SETN, MORK, COTR**, the top of `pick_groups.sql` by combined rank (all on `cw`; 0 groups on `mad` in `default`). If a group has few lifts, add LFRA and say so. Downstream-first.
- [x] `run.sh`, then `proof.R`, then `lifts.R`, at one clean commit and with nothing installed between. Evidence committed; README updated with the picks and why.
- [x] `research/minimal_network.md` (index row added), read beside `species_paused.md`. RUNBOOK §6b. Scratch schemas `zz415_default` and `zz415_minimal` kept until the PR merges, for review; dropped then.
- [x] File the parent-attribute issue from what the proof shows, with the lift result in its body and knowledge#120's mechanics check as acceptance. Edit #415's body, tick its boxes.
- [x] `/code-check branch` (three rounds, ended on round 3's enumeration of every number and provenance claim), PR stacked on PR 1. Merge is the operator's. `Fixes #415`, with the parent attribute carried by #444.

## Phase 3: PR 3, #440's test builds (m4 and m1 side by side), before the primitive refresh

- [x] **m4:** `default` on MURT, KOTL, BULK and KETL into `zz440_default`, build and recompute, compared with `zz432_post` (code) and m1's `fresh_default` (last provincial). Segments, barrier rows, accessible km, habitat per species.
- [x] **m1:** fresh 0.52.0 first (`worker_prep.sh`'s `install-fresh`), then the `bcfishpass` re-score from a worktree there (ADMS, BULK, BABL, ELKR and closure) into `fresh_parity441`, dispatcher only, against `fresh_parity361`, with `moves.R`. Logs copied back and redacted.
- [x] `research/bcfishpass_parity.md` revised in place; the `default` comparison beside it. Drop `fresh_parity362` as the keep-the-previous rule says.
- [x] `/code-check branch` (three rounds, ended on round 3's enumeration), PR stacked on PR 2. Merge is the operator's. `Fixes #440`.

## Phase 4: PR 4, #439's hosts and primitives

- [ ] `snapshot_bcfp.sh --with-bcfp-views --force` on m4, and on m1 under `bash -lc` as RUNBOOK §8d gives it. Confirm load stamps on both.
- [ ] Cloud hosts install fresh and snapshot at prep, from whatever S3 holds then; the run's `--auto-install` and `preflight_hosts` confirm fresh. Just before launch, compare S3's `log.json` with both hosts' ledger rows (`verify_extra.sql` check 5 fails on a mismatch), and refresh again if it moved; a refresh does not void the gate.
- [ ] Ledger and evidence committed. `/code-check branch`, PR, merge, `Fixes #439`.

## Phase 5: PR 5, the gate and the rehearsal (#418)

- [ ] Run branch from `main`. Quiet check, then `pretest_run.sh --config=default_minimal --schema=fresh_default_minimal --history-schema=fresh_default_history --history-config=default --minutes-exclude=KTSU,OKAN`. A real pass is required, recorded and committed. The scratch schema is built `LIKE` a history schema holding only `log`; each pick's `lnk_persist_init()` creates the rest. First gate in that shape, so its log is read, not assumed.
- [ ] What voids the gate after it passes: any change to `study_area_run.sh`, `wsg_recompute_one.R`, `schema_consolidate.R` (mapped `unexercised`) or `data-raw/pretest*` (its own rules), as well as the modelling path. The rehearsal's check script lives at `data-raw/logs/rehearsal_418/check.sh`, and a driver fix means the gate runs again.
- [ ] Rehearsal as decided above: `--preflight-only`, the small run, then each check named pass or fail: exit 0, `study_area_verify.sql`, the negative script, `recompute_audit.R`, `phases.tsv` rows on every host, hosts burned and none kept, `outside_readers.tsv`, and outputs against the last build (a report, not a fail).
- [ ] Teardown; the worker checked clean. Evidence and #418's body updated.
- [ ] `/code-check branch`, PR, merge, `Relates` #418.

## Phase 6: PR 6, the run

- [ ] Run branch from `main`, pushed; `--preflight-only` passes in full. Launch decisions written into `progress.md` and pushed before launch.
- [ ] Pack, launch detached, wait on the driver's own end marker with a foreground re-read of its exit and verifiers. **Nothing is edited or committed in this worktree while it runs, the PWF included:** each dispatcher group stamps this worktree's HEAD and dirty state into its `log` row, and `study_area_verify.sql` raises on a second `link_sha`. Only remote legs check that HEAD moved. The progress entry is written after the driver exits.
- [ ] A second full launch would need a new gate (the first run's rows become the history and are not ancestors of the gate's sha); the fallback for a partial failure is `--recompute-only`, which skips the pre-flight.
- [ ] Verifiers, audit, calibrator, `research/study_area_run.md`, #377's runs row, RUNBOOK if the run taught anything, `CLAUDE.md` Status.
- [ ] `/planning-archive`, `/code-check branch`, PR, merge, `Fixes #441`.

## What would stop the run, and what to do instead of waiting

| If | Do |
|---|---|
| Auto mode refuses the cloud spin | Found in Phase 0. If it first appears later: re-pack and run on m4 and m1 alone (no spend, slower), and say so. Do not retry or rephrase. |
| Auto mode refuses a `git push` or a merge | Hosts reset to origin, so this blocks remote legs. Commit locally, finish what needs no push, leave the operator the bare command. The run does not launch from unpushed code. |
| DigitalOcean, S3 state or Tailscale credentials fail later | Same fallback: m4 and m1 alone. A token rotation is the operator's. |
| The gate refuses an unmapped file | Map it with its reason. That is in PR 1. |
| A gate pick fails its bound | Check for other sessions and load; re-run on a quiet database. `--allow-busy` only if another session holds it for over 30 min, recorded. A real stall goes to a fix PR. |
| The gate or #440 shows a defect in fresh 0.52.0 | Reproduce it, file it in fresh, fix on a fresh branch and release if small. Otherwise fall back to the last good fresh tag, and re-run from Phase 1. |
| A proof check stops on a piece with a named cause | Record it and continue. **Access moved 1 % or more of a group's accessible km with no named cause: hold the launch.** Finish the other phases and leave the evidence. |
| The lift measure is large | Not a stop. It goes in the issue and the research file. |
| `bcfishpass` parity falls below 48 of 50 | Each move explained. Not a stop unless the cause also reaches `default`'s modelling. |
| A rehearsal check fails | A driver defect gets a fix PR, then the rehearsal again (the gate too if the modelling path changed). **No launch on a failed check.** After two failed cycles stop there, burn what can be burned and report. |
| A group fails in the run | The driver carries on and names it. Re-model under the `run_uid` once on m4, then `--recompute-only` (#348). |
| A host is kept | It holds the only copy, so it stays up, listed with its burn command. Recovery follows RUNBOOK §8d. |
| The m1 link drops mid-leg | A dropped ssh session ending the worker's loop is unmeasured (RUNBOOK §8d). The driver reads the missing end marker, keeps m1 and names it; the run finishes on the other hosts and exits non-zero. Recover by `--recompute-only` after re-modelling the worker's missing groups on m4 under the run_uid, or report if the gap is large. |
| A leg runs far over its packing estimate | Not a stop; the statement bound catches a stall. Report the leg and the group against `plan.tsv`. |
| A statement hits 30 min | The group fails alone. Re-model once at a 60 min bound, if nothing else is on the database. |
| Disk below 40 GB on m4 or m1 | m1: the approved cleanup. m4 (310 GB free at planning): stop the leg's next group, report; nothing deleted on m4 beyond this plan's own scratch. |
| Another session loads the database | Wait for quiet, up to 30 min, before the gate or the launch. During a run watch and report it; touch nothing of theirs. Two idle R processes on m1 (4 days and 1 day old at planning, 0 % CPU, no database activity) are left alone. |
| CI is red on setup or the CDN | Rerun once. If upstream stays down, merge on the local full suite and say so in the PR. CI red on the code stops that PR. |
| The session ends (usage limit, crash) | The driver is detached and burns its own hosts. The PWF is pushed at the end of each phase and before launch; the resume is in `progress.md`. |

Mac sleep is not a risk: caffeinate holds it on m4 and m1 has sleep off.

## Owed at the end (reported, done after merge)

- [ ] #418's gated rehearsal script (picker, `log_rehearsal`, launch refusal, seeded failures), left open with a note on #418 and #441.
- [ ] knowledge#120, the first consumer of `fresh_default_minimal`.
- [ ] The host-speed calibrator's second and third runs (#163's three-run acceptance) on the runs that follow.

## Validation

- [ ] Tests pass (full suite at each PR)
- [ ] `/code-check` clean (once over each PR's branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:

- **PR 1:** `test-pretest.R` and the full suite; each new guard fired by mutation; `--pick-only` on the 241-group history shows picks that are not m4's 4 groups.
- **PR 2:** `proof.R`'s own stops, and `lifts.R`'s control: in a species with no observation lift, its no-lift set equals the built set exactly.
- **PR 3:** the comparison reconciles (segments, barrier rows, accessible km, habitat per species) and each parity move is explained by `moves.R`.
- **PR 4:** load stamps on both hosts inside the vintage window; `--preflight-only` vintage line passes.
- **PR 5:** a `pass` row in `fresh_default_minimal.log_pretest`, and every rehearsal check named pass.
- **Run:** `study_area_verify.sql` passes at `expected_n=241` with `-v schema=fresh_default_minimal -v run_uid=<uid>`, `verify_extra.sql`, `recompute_audit.R` exit 0, tokens `cut-min acc-v5 grad-seg q-fwapg` on every `log` row, one fresh sha on every host, no kept host, no droplet left under `doctl`.
