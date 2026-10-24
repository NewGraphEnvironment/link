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
