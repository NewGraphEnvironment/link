# Findings — study_area_run.sh: persistent worker hosts beside the dispatcher and the cloud hosts (#376)

## Issue context

## Problem

A provincial run's modelling phase is bounded by its longest leg, so more hosts shorten it: with group atoms (#361), `data-raw/logs/provincial_361/buckets_group5.md` estimates five hosts at about 216 min against 270 for four. `study_area_run.sh` knows two kinds of host: the dispatcher, and cloud hosts it spins, preps and burns. A machine that already exists and stays up cannot take a bucket.

## Proposal

A third kind of host: a **persistent worker**, reached over ssh, that the driver neither spins nor burns. Given as `--workers=<ssh host>,...`, with one `--focal=` list per worker after the dispatcher's and before the cloud hosts'.

- **Prep:** check out the run's branch, install link at that ref and confirm fresh's version, as `cypher_prep.sh` does on a fresh cloud host. The primitive-vintage and host-parity gates apply as for a cloud host (#276).
- **Modelling leg:** the cloud host's ssh string and exports (`LNK_SCHEMA`, `LNK_GUARD_DOWNSTREAM=warn`, `LNK_HABITAT_GATE=0`, `PGOPTIONS` and `LNK_STATEMENT_TIMEOUT_MIN` (#371), `LNK_RUN_UID`, the git SHAs).
- **Exit status:** some ssh servers return 0 whatever the remote command returned (Tailscale SSH to macOS does). For a worker, every ssh exit status the driver reads (the leg, the stamp and vintage probes, consolidate's `system()` calls) is replaced by what the remote prints, or by the worker's database, as #347 does for completeness.
- **Consolidate:** a source like a cloud host (`schema_consolidate.R` reaches sources over ssh and `docker`); with #369, when its own leg finishes.
- **After consolidate:** no burn. The worker's copy of the run's groups is dropped from its persist schema once consolidate has verified it, so the next run's `host_baseline` starts clean. Until then it is held (#347), reported, never burned.
- **Packing:** `study_area_buckets.R --atom=group` takes the worker's measured speed.

## Acceptance

- A two-host test run (dispatcher + one worker, `--buckets-exact`, a scratch schema) models, consolidates and recomputes every group, and exits 0. A group made to fail on the worker is named and the run exits non-zero, also when the worker's ssh returns 0.
- A provincial run with a worker has a longest leg within 10 % of its packing estimate.
- RUNBOOK §8d documents the worker kind and the exit-status rule.

## Related

#361, #369, #371, #347, #276, #163 / #259.


## Exploration (2026-10-24)

- The driver's remote-host loops all iterate `CY_WS_ARR` and the `CY_*` maps (382 references, ~20 names, in `study_area_{run,hosts,legs,finish}.sh` and three test files).
- `.hosts_query` already frames its answers with sentinels; it hardcodes `cypher@$where` and `docker exec -i fresh-db`.
- `schema_consolidate.R` judges every remote call on `system()`'s rc. On an ssh that exits 0 whatever the remote did, a failed per-table COPY (stage 1) leaves an empty or partial file, stage 2 copies it, and if the bucket's total rows still rose, step 5 deletes the source: a data-loss path. `src_newest` reads only the `status` attribute, so a failed query reads as "no log rows" and refuses under the wrong reason.
- The vintage probe in `preflight_hosts()` is judged on ssh's rc alone; the stamp probe also checks for empty output.
- The model leg's status (`mrc`, then `CY_RUN_RC`) is ssh's rc; `host_release` requires 0.
- `cypher_prep.sh` stashes and `git reset --hard`s `~/Projects/repo/link`, pak-installs link, rewrites `~/.Renviron`, and runs `lnk_persist_init(force_recreate = TRUE)`: none of these is safe on a persistent machine.
- `study_area_buckets.R` already takes `--host-speeds`; its labels are `dispatcher (m1)` then `job<N>`.

## A timing-bound legs test (pre-existing)

`test-study_area_legs.R` "a burn mid-run lists no host that is still modelling" gives host a's account and consolidate 3 s to finish before host b's leg copies the kept file. Under load (the Plan review running beside the suites) it failed twice in seven runs; 3/3 green on the branch and 3/3 at HEAD when idle. Not caused by this branch; noted, not widened into scope.

## worker_prep.sh, run for real on the dispatcher (2026-10-24)

Origin pointed at this repo, a temp clone, config `default`, scratch schema `lnk_test_wprep` (dropped after): exit 0, `=== link 0.68.4 at 1b4ef989…; fresh 0.42.0 at e9793047… (remote_sha)`, 24 tables initialised, `=== READY`. With `FRESH_GIT_SHA=deadbeef1234` exported it refuses ("pins deadbeef1234 but the installed fresh was built from e9793047"); with `LINK_GIT_SHA=deadbeef1234` it refuses ("resolves to deadbeef1234 (env), not the clone's HEAD"); with another origin it refuses ("not the driver's clone"). Under load_all, link's sha resolves from the checkout's git (`source = git`), never an installed `RemoteSha`, so only a pin can make it lie.

## Code-check round 2: values pasted into remote strings, enumerated

Round 2 found the target and stall-hook checks newline-blind (`grep -qx` passes a value whose first line fits; a target with `\n'; touch …` passed, verified), and the round-1 branch check running where no remote host is sent it. Mechanism: a value checked by a line-wise tool, or by a check that does not see every source of the value. So every value the branch pastes into a remote command string, SQL or R source, and its check:

| value | reaches | check |
|---|---|---|
| `--workers=` targets | ssh argv, consolidate R source, `sh -c` | newline refused before `read`; `[[ =~ ^…$ ]]` charset; not `local`; no duplicates |
| `--cy-workspaces=` | key collision check | newline refused before `read` (charset pre-existing, unchanged) |
| `LINK_BRANCH` | cypher and worker prep strings | `[[ =~ ^[A-Za-z0-9._/-]+$ ]]`, when any remote host |
| `--config=`, `--schema=` | every remote string | `case *[!A-Za-z0-9_]*` (pre-existing, whole value) |
| schema from the config's YAML | every remote string, drop SQL | `[[ =~ ^[A-Za-z0-9_]+$ ]]` (new) |
| `--run-label=` | leg string | `case` glob (pre-existing, whole value) |
| `WET_LOAD` | prep strings, single-quoted | refused when it holds `'` (pre-existing) |
| `ORIGIN_URL` | worker prep string | `case` glob, whole value |
| `LNK_TEST_STALL_WSG` | leg string | `[[ =~ ^[A-Z]{4}$ ]]` in driver and lib |
| `RUN_UID`, `RUN_SHA`, `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA` | leg string | generated (timestamp+hex, `git rev-parse`) |
| `STATEMENT_TIMEOUT_MIN` | leg string | integer range (pre-existing) |
| `HOST_PARTIAL` groups | drop SQL array literal | `.hosts_query` passes only `^[A-Z]{4}$` lines |
| bucket groups | leg loop | `study_area_wsgs.R` output (pre-existing) |

The remaining `grep -qx` calls on the branch read log files line by line (`=== READY`, `=== persist init done`), which is the intended semantics.

## Code-check round 3: what a worker reads that the driver did not write, enumerated

Round 3's mechanism: the worker reuses cloud-host code that assumes the host is the driver's alone, built fresh for the run and holding only what the run put there. On a persistent worker every input has a second source. Each source, and what guards it now:

| source on the worker | what it could do | guard |
|---|---|---|
| `~/.Renviron` (or the shell's env, as R sees it) | beat the leg's exports (another schema, habitat gate on, wrong provenance), or pin shas | worker_prep refuses any of `REMOTE_LEG_VARS` set for R (list held equal to `remote_leg_cmd`'s exports by a test; live refusal 2026-10-24), and `FRESH_GIT_SHA`/`LINK_GIT_SHA` pins that are not the real build |
| `~/.Rprofile` | output on stdout, changed options | measured in Phase 1; stamps and probes are judged on output |
| its database's other schemas | the run writing into them | the leg's schema comes from the export, which nothing on the worker can now override; identity check refuses the dispatcher's own or a shared database |
| rows already in the run's schema | read as this run's, then consolidated and deleted | prior-rows refusal before spend (`streams`, `streams_mapping_code`) |
| tables in the schema that are not link's (primitives, bcfp reference) | copied over the dispatcher's, deleted at the source | `consolidate_link_tables()`; the drop's list held equal to it; a live test holds both to what `lnk_persist_init()` creates |
| primitives and discharge | stale or another vintage | not reloaded; vintage gate (load stamps) and discharge (and wet load id) checked at prep |
| the clone | another branch, local edits, another origin | origin must match; reset and clean every prep; HEAD checked before each group |
| files left in /tmp | an older prep script | prep is piped over ssh, never copied |
| other sessions | a git change in the clone mid-run; fresh reinstalled mid-run | HEAD check per group; fresh's mid-run reinstall is caught only after the run by `study_area_verify.sql` (accepted, noted) |
| names ssh writes into logs | the target, `user@host`, the HostName an alias resolves to, `<user>@<host>:` | `remote_redact_init` (target, host part, `ssh -G` HostName), `@` allowed before a match |
| the origin URL sent to it | a token in userinfo | refused |
| its exit statuses | 0 whatever ran | the remote-status rule (RUNBOOK §8d) |
| a prep still writing when the driver dies | unredacted lines after the trap redacts | the trap stops worker prep pids before redacting |

## Code-check round 4: the terminal enumerations

Round 4 found a defect inside round 3's fix (the EXIT trap signalled every pid in `WK_PREP_PIDS`, never cleared, so a pid reused hours later by another session could be killed with its children) and widened round 3's two rows. Fixed, then enumerated:

- **Every pid the branch signals or waits on:** the trap's loop (now only pids `jobs -p` still lists, and the list is cleared once the preps are waited on) and the prep wait (pids started just above). Nothing else on the branch calls `kill`, `pkill` or `wait <pid>`.
- **Every environment variable link's R reads** (grep of `Sys.getenv("…")` over `R/` and the leg's scripts, plus the `<PKG>_GIT_SHA` / `_DIRTY` names built by `paste0`): every `LNK_*` refused at worker prep except `LNK_HOST_ALIAS` (names the host; the vintage stamps key on it); `LINK_GIT_SHA`, `LINK_GIT_DIRTY`, `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA`, `PGOPTIONS` refused; `FRESH_GIT_SHA` must equal the installed `RemoteSha`; `FRESH_GIT_DIRTY` only `false` beside a matching `FRESH_GIT_SHA`; `FWAPG_DIR` / `BCFISHOBS_DIR` are not read while the leg exports the shas; `PG*` and `PG_*_SHARE` are not read by the leg, whose scripts connect with explicit arguments. Live refusals checked for `LNK_BCFP_MODEL_RUN_ID`, `LINK_GIT_DIRTY` and a bare `FRESH_GIT_DIRTY`.
- **Names a worker writes about itself:** worker prep prints `=== host <.lnk_host()>`, which the driver adds to what it redacts (the stamps row carries it). A held worker's leg may write ssh's end-of-session lines after the trap's redaction: the kept-hosts banner says to redact that log again before committing it.

## Phase 1: the worker, measured (2026-10-25 05:16 UTC)

The candidate worker (a macOS host on the tailnet; identity in the private infrastructure repo):

- **ssh exits 0 for `exit 3`.** The premise of the remote-status rule, measured. `( exit 3 ); echo __LNK_RC__=$?` prints `__LNK_RC__=3`. stdout is byte-exact (`a \t b \n`), stderr separate, no PTY.
- **Non-interactive shell:** `/bin/bash` 3.2.57, PATH `/usr/local/bin:/usr/bin:/bin`. `Rscript`, `docker` (`/usr/local/bin`), `git` (`/usr/bin`, works: 2.50.1), `perl` resolve; `psql` does not, which the probes never need (they `docker exec fresh-db psql`). R 4.5.2 prints nothing on startup. 330 GB free.
- **Database:** `docker exec fresh-db psql` answers; `system_identifier` differs from the dispatcher's. It holds `fresh` and `fresh_default` (older builds) and no `provenance` schema, so the vintage gate reads it as unstamped. fwapg's discharge table and `fresh.modelled_stream_crossings` exist.
- **`~/.Renviron`:** none of the refused keys (`LNK_*`, `LINK_GIT_*`, `FRESH_GIT_*`, `FWAPG_GIT_SHA`, `BCFISHOBS_GIT_SHA`, `PGOPTIONS`); 60 keys in all, values not read.
- **R packages:** pkgload 1.5.0; **fresh 0.39.0** (RemoteSha `e247ca19`), below DESCRIPTION's floor `fresh (>= 0.42.0)`, so load_all refuses it and prep stops; wet 0.0.0.9000 (only a `wet`-discharge config needs it).
- **Not yet measured:** whether a dropped ssh session kills the remote loop (Phase 6's killed-loop case).

Two writes stand between the worker and Phase 6, both to state other sessions there share: fresh at the pin (`--auto-install`, pak, so it records `RemoteSha`), and a primitive snapshot that writes load stamps (`snapshot_bcfp.sh --with-bcfp-views --force`). Without the snapshot the run could only proceed on `--preflight-note`, modelling on primitives of unknown date that differ from the dispatcher's.
