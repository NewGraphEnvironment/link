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

## Plan revised after the Plan review (2026-10-24)

`review-plan.md` holds the review. Four blockers changed the phases below: no kept report on a workers-only run (B1), workers in the burn list (B2), a `~/.Renviron` pin beats any export over ssh, measured (B3), and target validation including a target that reaches the dispatcher's own database (B4). So the Q2 answer above is corrected: link can be stale on a worker through a `LINK_GIT_SHA` pin, and the worker gate refuses that, as the dispatcher's does for fresh. Worker prep is a separate script, because `cypher_prep.sh` installs, reloads shared primitives and recreates the persist.

## Phase 1: Measure the worker (no code)
Needs the worker's ssh target from the operator (kept out of the repo).
- [ ] ssh exit status (`ssh <w> 'exit 3'; echo $?`), stdout byte-exact and stderr separate (`printf 'a\tb\n' | od -c`), no PTY, BatchMode and ACL check-mode prompts, scp
- [ ] Non-interactive shell, PATH (`Rscript git docker psql bash`), bash version, `~/.Rprofile` output on stdout
- [ ] DB route (docker `fresh-db` or host psql), fwapg loaded, primitives' load stamps (`host_vintage.R`), discharge for the run's config, `system_identifier` differs from the dispatcher's
- [ ] Installed fresh vs the pin; `~/.Renviron` keys (`LINK_GIT_*`, `FRESH_GIT_*`, `LNK_HOST_ALIAS`); pkgload installed; `load_all()` refuses a fresh below the floor
- [ ] Whether a dropped ssh session kills the remote loop
- [ ] Record findings (no identity) in `findings.md`; adjust Phases 3–4 if a route differs

## Phase 2: Rename any-remote-host maps (behaviour-neutral)
- [x] Record the four study_area suites' pass counts at HEAD
- [x] `CY_WS_ARR`→`HOST_ARR` (deferred to Phase 4, which splits the list by kind), `CY_BUCKET`→`HOST_BUCKET`, `CY_HOLD`, `CY_RUN_RC`, `CY_CONS_*`, `CY_BUCKET_DONE`, `CY_UNCONS`, `CY_PARTIAL`, `CY_DOUBT`, `CY_PRE*`, `CY_WHY`, `CY_LEG_*`, `CY_NO_OUTCOME` → `HOST_*` across `study_area_{run,hosts,legs,finish}.sh` and their tests; keep `CY_IP`, `CY_BURNED`, `CY_WS`
- [x] Suites pass with identical counts (hosts 38/125, legs 14/68, finish 34/229, phases 16/61); commit alone

## Phase 3: The exit-status rule (tests first)
- [x] `schema_consolidate.R`: `consolidate_remote()` runs every remote command with an rc trailer on stderr, captured per call, and judges by it (tables, columns, newest-log, stage-1 COPY, source cleanup); tests with a stub ssh that exits 0 whatever ran, plus a structural guard that no raw `ssh '` call is left
- [x] Per-table copy check: stage 2's `COPY n` equals stage 1's line count for a persist table, or the source is not deleted
- [x] `HOST_SSH` per host (`cypher@$IP` for cyphers); `.hosts_query`, `host_consolidate`, `consolidate_outcomes`, the driver's stamp, vintage, auto-install and leg calls and the test fixtures move to it (`HOST_VIA` deferred to Phase 1's measurement of the worker's DB route)
- [x] Extract the leg launcher, stamp and vintage probes and auto-install into a lib the tests can source (`data-raw/study_area_remote.sh`: `remote_run`, `remote_out`, `remote_leg_cmd`, `remote_leg_status`; `tests/testthat/test-study_area_remote.R`)
- [x] Leg ssh strings end with an `__LNK_LEG_END__` echo matched unanchored, inside the braces the `cd` guards; the wrapper's status is non-zero when ssh failed or the sentinel is absent (feeds `HOST_RUN_RC`); tests, mutation-checked
- [x] Vintage, auto-install (plus its install-stage READY line) and stamps judged per host on printed status, captured per call (`${TS}_vintage_<host>.log`, `${TS}_autoinstall_<host>.log`); the worker reachability probe lands with Phase 4

## Phase 4: The worker kind in the driver (tests first)
- [x] Tests: workers-only run writes the kept report and exits non-zero when held (B1); a released worker is neither burned nor listed kept, and a pre-dispatch trap does not burn one (B2); target refusals (leading `-`, quotes, `local`, duplicates, workspaces named `worker<N>`/`dispatcher`); `consolidate_outcomes` with a worker host; partial drop excludes `DOUBT`, skips when `PRE` unknown; redaction of a target with regex metacharacters; `LNK_TEST_STALL_WSG` validated
- [x] Args: `--workers=`, `HOST_ARR` (workers then cyphers) and `CY_ARR`, `HOST_KIND`; `--focal=` count = 1 + workers + cyphers; `--recompute-only` refuses `--workers`; banner shows keys only; redaction replaces each target, word-bounded and quoted, with `<workerN>`
- [x] Every `N_CY` / `CYPHERS_UP` use decided: cypher-only (DO/tofu, droplets, spin, burn) vs any remote host (gates, persist init and backup, `preflight_hosts`, buckets, dispatch, kept report, tail branch)
- [x] Pre-spend worker checks in `preflight_local`: reachability, `system_identifier` distinct; prior rows (`streams`, `streams_mapping_code`, non-strict) refused naming the groups once the buckets resolve, still before spend
- [x] `data-raw/worker_prep.sh`, piped over ssh: clone `~/Projects/repo/link_worker` if absent, fetch and reset (no stash); everything by load_all; fresh assertion; staleness refusal (`FRESH_GIT_SHA` pin vs RemoteSha, `LINK_GIT_SHA` ≠ HEAD); discharge and vintage checked, not reloaded; `lnk_persist_init` without `force_recreate`; `=== READY`
- [x] `--auto-install` on a worker installs fresh at the `Remotes:` pin, refusing when a `FRESH_GIT_SHA` pin would outlive it
- [x] Legs: worker string `cd ~/Projects/repo/link_worker && export LNK_LOAD=loadall …` with the cypher exports, and a HEAD check against the run's sha before each group; `host_finish_leg` for a worker: account, consolidate, release, then drop its partial groups' persist rows (settled, `PRE` known and empty, log rows kept, sentinel-judged; a failed drop fails closed), `burn` row `skipped`
- [x] Forward `LNK_TEST_STALL_WSG` (validated `^[A-Z]{4}$`) over ssh when set

## Phase 5: Packing with a worker
- [x] `study_area_buckets.R --workers=N`: labels `dispatcher, worker1.., job1..`, the printed command carries `--workers=<target>` placeholders and focal order; speeds stay `--host-speeds` (dispatcher first, then workers, then jobs)
- [ ] Document how a worker's speed is measured: mid-size groups' minutes by host (not `--minutes-schema`'s newest row, which mixes hosts)

## Phase 6: Live acceptance (two-host test)
- [ ] Live probes on the worker: `consolidate_remote` reads 3 from `exit 3` while ssh returned 0
- [ ] Dispatcher + worker, `--buckets-exact`, scratch schema `fresh_worker376`, mid-size groups: models, consolidates, recomputes, exits 0; both verifiers pass at `expected_n`
- [ ] Failure run: `LNK_TEST_STALL_WSG=<worker group> --statement-timeout=1` on groups whose longest statement is well under a minute; expected: worker released, no `kept_hosts.tsv`, the group in `no_rows`, exit 1
- [ ] Kill the remote loop's shell mid-leg: no END sentinel, worker held and listed, run exits non-zero
- [ ] Evidence to `data-raw/logs/worker_376/` (README indexes runs; launcher stdout redacted); drop `fresh_worker376` on both hosts after

## Phase 7: Docs
- [ ] RUNBOOK §8d: "Persistent workers" (kind, prep, clone, no burn, partial drop) and the exit-status rule; also the phases host column, "burn, per cypher", the recovery recipe's `cypher@<ip>`, the kept-hosts wording
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

