# Plan review — #376 (Plan agent, 2026-10-24, against HEAD 5f4c48ac)

Condensed from the reviewer's reply; each item carries what was done with it.

## Blockers

- **B1. No kept report on a workers-only run.** `burn_cyphers` returns at once unless `CYPHERS_UP=1` (hosts.sh), the only caller of `hosts_kept_report`, and `CYPHERS_UP` is set only on the spin path. A held worker on a dispatcher+worker run is never written to `kept_hosts.tsv`, `KEPT_CAUSE_N` stays 0 and the run can exit 0. The run.sh tail also branches on `N_CY`. *Verified by reading* (`[ "${CYPHERS_UP:-0}" = "1" ] || return $rc`). → Phase 4: gate on "any remote host dispatched"; tail branch on remote hosts; workers-only test.
- **B2. Workers fall into the burn list** (anything neither held nor burned). → Phase 4: burn set is cyphers only; a released worker is neither burned nor listed as kept; tests after release and from a pre-dispatch trap.
- **B3. A stale `~/.Renviron` pin cannot be overridden over ssh.** *Measured 2026-10-24:* a user Renviron line wins over an exported value, and a `.Renviron` in the working directory replaces `~/.Renviron` entirely. `.lnk_pkg_git_state` takes the env tier first, so a worker's `LINK_GIT_SHA`/`FRESH_GIT_SHA` pin would be stamped into every row; `link_sha` is not a parity key. `--auto-install` (pak) under a `FRESH_GIT_SHA` pin creates exactly the stale state `preflight_local` refuses on the dispatcher. → Phase 4: worker prep runs the dispatcher's staleness test (fresh pin vs RemoteSha; `LINK_GIT_SHA` set and ≠ the clone's HEAD) and refuses with the remediation; `--auto-install` refuses on a worker holding a `FRESH_GIT_SHA` pin.
- **B4. Target validation.** A target reaching the dispatcher's own database (or two targets on one database) would DELETE the bucket on the destination then copy from the same emptied table. `local` is `.hosts_query`'s dispatcher sentinel; a leading `-` is ssh option injection; the target is pasted into shell and R source. → Phase 4: charset `^[A-Za-z0-9][A-Za-z0-9._@-]*$`, not `local`, no duplicates, cypher workspaces may not be named `worker<N>`/`dispatcher`; each worker's `pg_control_system().system_identifier` must differ from the dispatcher's and every other worker's (pre-spend).

## Gaps (exit status)

- `system(intern = TRUE)` captures stdout only, so a stderr trailer needs its own `2>` file per call. *Already so in `consolidate_remote()`.* Not `2>&1`: ssh warnings would land in table names.
- Stage-1 COPY is the data-loss path; the bucket total check cannot see one table landing nothing. → Phase 3: per-table check, stage 2's `COPY n` equals stage 1's line count (persist tables).
- Vintage / auto-install write to one shared log: capture per call, judge per host.
- `scp` of the prep script to `/tmp/cypher_prep.sh` on a persistent machine can leave an older copy that still prints `=== READY`. → worker prep is piped (`ssh w bash -s < script`).
- New remote calls (partial drop, prior-rows probe, DB identity) need the same sentinel framing.
- Every `CY_IP`-as-`where` site, `consolidate_outcomes`' `cypher@<ip>` row match and the `cypher@` test stubs → `HOST_SSH`, introduced in Phase 3.
- `cypher_prep.sh` worker mode is wider than "no pak": every R call uses the installed link, `snapshot_bcfp.sh` reloads the worker's shared primitives (every prep, since reset wipes the clone's ledger row), the wet load pak-installs, `cd ~/Projects/repo/link` is hardcoded, `git stash` grows. → separate `data-raw/worker_prep.sh`: clone/reset, assert fresh + staleness, check discharge and vintage (no reload, no wet install), persist_init by load_all without force_recreate.
- Concurrency in the clone: each group `load_all`s afresh, so a git change mid-leg changes code after parity passed. → the remote loop checks HEAD against the run's sha before each group.
- `LNK_TEST_STALL_WSG` validated `^[A-Z]{4}$` before it reaches an ssh string.

## Scope / ordering

- Introduce `HOST_SSH` in Phase 3 (`cypher@$IP` for cyphers), move `consolidate_outcomes` and stubs with it.
- The leg launcher, stamps and vintage probe live in run.sh, which no test sources: extract into a lib before writing their tests.
- Cheap worker checks (reachability, target rules, DB identity, prior rows non-strict) run pre-spend in `preflight_local`, so `--preflight-only --workers=` is a real dry check.
- Partial drop: persist tables only (keep the open log row), only when settled, `PRE` known and empty, `PARTIAL` never `DOUBT`; a failed drop fails closed (next prep refuses).
- The prior-rows refusal checks `streams` and `streams_mapping_code` only (as `host_baseline` does); it prints the groups, not a DELETE to paste.
- Redaction of targets word-bounded and quoted (`\Q…\E`).
- `--keep-cyphers` does not apply to workers.

## Phase 1 measurements added

stdout byte-exact and stderr separate (`printf 'a\tb\n' | od -c`), no PTY; BatchMode/ACL check-mode prompts; whether a dropped session kills the remote loop; the non-interactive shell, PATH, bash version; `~/.Rprofile` output; `~/.Renviron` keys (`LINK_GIT_*`, `FRESH_GIT_*`, `LNK_HOST_ALIAS`); pkgload installed and `load_all()` refusing a fresh below the floor.

## Acceptance

- The stall run does not test the exit-status rule (a group's failure never depended on ssh's rc). → add live probes on the real worker: `consolidate_remote` reads 3 from `exit 3` while ssh returned 0; kill the remote loop mid-leg → no END sentinel → worker held, run exits non-zero.
- State the failure run's expected outcome (worker released, no kept_hosts.tsv, group in `no_rows`, exit 1); choose groups whose longest statement is well under the 1-minute bound.
- Speed from a few small groups is overhead-dominated, and `--minutes-schema` mixes hosts: measure on mid-size groups, by host.
- RUNBOOK also changes: phases host column, "burn, per cypher", the recovery recipe's `cypher@<ip>`, the kept-hosts wording.
