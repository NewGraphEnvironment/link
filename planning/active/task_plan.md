# Task: study_area_run.sh: persistent worker hosts beside the dispatcher and the cloud hosts (#376)

## Problem

A provincial run's modelling phase is bounded by its longest leg, so more hosts shorten it: with group atoms (#361), `data-raw/logs/provincial_361/buckets_group5.md` estimates five hosts at about 216 min against 270 for four. `study_area_run.sh` knows two kinds of host: the dispatcher, and cloud hosts it spins, preps and burns. A machine that already exists and stays up cannot take a bucket.


## Answers to your questions at the gate

**Q2, load_all and staleness.** load_all means the worker's legs run link straight from the driver-owned clone (`LNK_LOAD=loadall`, as the dispatcher does), so the worker's installed link, used by every other session on that machine, is never replaced. Link cannot be stale: prep resets the clone to `origin/<run branch>`, and the existing parity gate (`lnk_preflight_parity`, keyed on `repo_sha`) proves after prep that every host is on the dispatcher's commit. fresh is the one installed piece. Its staleness check at launch is the same parity gate (`fresh_sha` must equal the dispatcher's) plus `lnk_preflight_fresh()` and `load_all()`'s own refusal of a fresh below DESCRIPTION's floor. A mismatch fails before any write. The manual override is `--auto-install`, which already exists for cyphers: on a worker it installs fresh at DESCRIPTION's `Remotes:` pin (`pak::pkg_install`) and re-checks once. `--preflight-note="why"` stays the only downgrade. So everything is aligned and current, or the run does not start.

**Q3, the rename's real cost (measured).** 382 references to ~20 `CY_*` names across 4 libs and 3 test files. A `sed` over word-bounded names is mechanical, behaviour-neutral and proven by the existing 102 `test_that` blocks passing unchanged before and after. The price is a noisy diff (one commit, ~380 lines) and a conflict risk only with a parallel branch on these files (none open). Implications: nothing persisted or logged changes name (`phases.tsv` host column, kept-hosts columns and log file names keep their values). So the rename is cheap; I recommend doing it as its own first commit, scoped to maps meaning *any remote host* (`HOST_*`); cypher-only ones (`CY_IP`, `CY_BURNED`, `--cy-workspaces`) keep `CY_`.

## Decided at the gate (operator, 2026-10-24)

- Worker models from a **driver-owned clone**, `~/Projects/repo/link_worker` on the worker; the worker's own checkout is never touched.
- Worker runs link by **load_all**, installs nothing by default; fresh staleness fails prep, `--auto-install` installs fresh at the pin and re-checks once. Prep never writes the worker's `~/.Renviron`.
- **Rename** any-remote-host maps `CY_*` → `HOST_*` in a separate behaviour-neutral commit (recommended above; approved with the plan).
- A worker whose persist schema holds rows for any group of its bucket **is refused at prep**, naming the groups and the DELETE.
- Worker keys are positional (`worker1..N`); the ssh target never reaches a committed file (redacted from `${TS}_*` logs like addresses).
- The exit-status rule applies to **every remote host**, cyphers included: strictly stricter, one code path.

## Phase 1: Measure the worker (no code)
Needs the worker's ssh target from you on approval (kept out of the repo).
- [ ] Confirm ssh exit status: `ssh <w> 'exit 3'; echo $?` (Tailscale to macOS expected 0)
- [ ] PATH of a non-interactive command: `which Rscript git docker psql bash` and `bash --version` (driver legs need bash only on the dispatcher; check anyway)
- [ ] DB route: docker `fresh-db` (as cyphers) or host psql; fwapg loaded, primitives' load stamps (`host_vintage.R`), discharge table for the run's config
- [ ] Installed fresh vs DESCRIPTION pin; whether `LINK_GIT_SHA`/`FRESH_GIT_SHA` in its `~/.Renviron` would override load_all's sha (`.lnk_pkg_git_sha`)
- [ ] Record findings (no identity) in `findings.md`; adjust Phases 3–4 if a route differs

## Phase 2: Rename any-remote-host maps (behaviour-neutral)
- [ ] Record the four study_area suites' pass counts at HEAD
- [ ] `CY_WS_ARR`→`HOST_ARR`, `CY_BUCKET`→`HOST_BUCKET`, `CY_HOLD`, `CY_RUN_RC`, `CY_CONS_*`, `CY_BUCKET_DONE`, `CY_UNCONS`, `CY_PARTIAL`, `CY_DOUBT`, `CY_PRE*`, `CY_WHY`, `CY_LEG_*`, `CY_NO_OUTCOME` → `HOST_*` across `study_area_{run,hosts,legs,finish}.sh` and their tests; keep `CY_IP`, `CY_BURNED`, `CY_WS`
- [ ] Suites pass with identical counts; commit alone

## Phase 3: The exit-status rule (tests first)
- [ ] Tests: stub ssh that exits 0 while the remote command failed — consolidate must not copy a partial table or delete from the source; a leg with no end sentinel reads as failed; a vintage probe with no pass sentinel fails
- [ ] `schema_consolidate.R`: one helper runs every remote command with an rc trailer on stderr (`…; echo __LNK_RC__=$? >&2`) and judges by it: enumeration, columns, newest-log, per-table COPY (stage 1), source cleanup
- [ ] Leg ssh strings end with an `__LNK_LEG_END__` echo; the leg wrapper's status is non-zero when ssh failed or the sentinel is absent (feeds `HOST_RUN_RC`, so release stays strict)
- [ ] Vintage probe, `--auto-install` and the reachability probe judged on printed sentinels; stamps already judged on output (verify)
- [ ] `.hosts_query` and consolidate sources take a per-host ssh target (`HOST_SSH`) instead of `cypher@$ip`

## Phase 4: The worker kind in the driver (tests first)
- [ ] Tests: `burn_cyphers` never burns a worker; kept report prints a worker row with no burn command; release of a worker deletes its partial groups only when settled; focal order dispatcher → workers → cyphers; target charset refused
- [ ] Args: `--workers=` (charset-restricted), `HOST_KIND`/`HOST_SSH`, `--focal=` count = 1 + workers + cyphers; banner shows keys only; `redact_log_addresses` also replaces each target with `<workerN>`
- [ ] Prep: reachability probe (sentinel), then `cypher_prep.sh` in worker mode (env knobs: clone at `~/Projects/repo/link_worker` if absent; load_all, no pak, no `~/.Renviron`; `lnk_persist_init` without `force_recreate`; same snapshot, wet-load and `=== READY` contract)
- [ ] Gates: branch-pushed/clean-tree gates apply when any remote host exists; parity over every host; per-host vintage; prior-rows refusal for workers via `host_remaining`; `--auto-install` on a worker installs fresh at the `Remotes:` pin
- [ ] Persist init + backup, legs (worker string: `cd ~/Projects/repo/link_worker && export LNK_LOAD=loadall …`, same exports as cyphers), `legs_wait`/`host_finish_leg`: account, consolidate, release; then drop partials instead of burn (`burn` phase row `skipped`)
- [ ] Forward `LNK_TEST_STALL_WSG` over ssh when set (banner already warns), so a group can be made to fail on a remote host

## Phase 5: Packing with a worker
- [ ] `study_area_buckets.R --workers=N`: labels `dispatcher, worker1.., job1..`, the printed command carries `--workers=<target>` placeholders and focal order; speeds stay `--host-speeds` (dispatcher first, then workers, then jobs)
- [ ] Document how a worker's speed is measured: its group minutes from the Phase 6 run against the same groups' 2026-10-23 minutes

## Phase 6: Live acceptance (two-host test)
- [ ] Dispatcher + worker, `--buckets-exact`, scratch schema `fresh_worker376`, a few small groups each: models, consolidates, recomputes, exits 0; both verifiers pass at `expected_n`
- [ ] Failure run: `LNK_TEST_STALL_WSG=<worker group> --statement-timeout=1`: group named, run exits non-zero, worker kept only if it holds finished work, with the worker's ssh returning 0
- [ ] Evidence to `data-raw/logs/worker_376/` (README indexes runs; launcher stdout redacted); drop `fresh_worker376` on both hosts after

## Phase 7: Docs
- [ ] RUNBOOK §8d: "Persistent workers" (kind, prep, clone, no burn, partial drop) and the exit-status rule
- [ ] Driver header usage + flags; CLAUDE.md status block; `research/study_area_run.md` hosts note

## Owed at the end (reported, done after merge)
- [ ] Acceptance 2: a provincial run with a worker has a longest leg within 10 % of its packing estimate (next provincial `default` run; fills #377's runs row)

## Validation
- [ ] Tests pass (`devtools::test()`; the four study_area suites in particular)
- [ ] `lintr::lint_package()` clean
- [ ] `/code-check branch` clean (three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: each guard is proved by restoring the defect (ssh stub exits 0 on a failed COPY → test goes red without the trailer); the rename by identical suite counts; the worker path end to end by Phase 6 on real hosts, including the ssh-returns-0 case.

