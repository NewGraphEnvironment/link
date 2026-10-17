# Task: study_area_run.sh counts finished groups from log text and burns hosts holding unconsolidated work (#347)

## Problem

`study_area_run.sh` decides which groups each cloud host finished by reading the host's run log, and the reading is wrong often enough to lose work.

`bucket_done()` matches `^\[wsg_run_one\] <WSG> … done`, anchored at the start of a line. R writes warnings to stderr in the same stream, and a warning flushed without a newline puts the marker mid-line:

```
8: In st_read.DBIObject(conn, query = query) :[wsg_run_one] FIRE done in 4.6 min (persist=fresh_default)
```

In run `20261017_004619-3f4c713b` (#246, 241 groups, `default`) that hid 18 finished groups: 2 of 50 on job1, 12 of 55 on job2, 4 of 60 on job3. Each was persisted on its host with one log row for the run_uid (checked on the hosts before burn).

The driver then does what its design says with a short count:

1. consolidates only the groups it counted;
2. **burns the cloud hosts right after consolidate**, destroying the 18 groups' only copy;
3. fails the coverage check on whatever is missing and exits before the recompute.

They were saved only because the operator paused the driver (`kill -STOP`) before the burn and the 18 were consolidated by hand.


## Plan context

`data-raw/study_area_run.sh` decides what each host finished with `bucket_done()` (`study_area_run.sh:1287`), a `sed` match anchored at line start. An R warning flushed without a newline put the `done` marker mid-line and hid 18 finished groups in run `20261017_004619-3f4c713b`. The driver then consolidated only what it counted and would have burned the hosts holding the rest (`burn_cyphers || true`, `:1374`), and the EXIT trap burns every cypher on any abort (`:346`).

Measured while planning:
- "Finished" in the DB is `<schema>.log` row with this `run_uid` and **`date_end` NOT NULL** (the issue says `date_completed`; that column does not exist). `date_end` is set by `.lnk_log_run_finish()` after persist (`R/lnk_pipeline_run.R:322`); a failed run keeps `date_end` NULL.
- A `SKIP` group (`wsg_run_one.R:56`, no species) writes **no** log row, so the log is still the only place it shows. It holds nothing to consolidate.
- consolidate reaches each cypher as `ssh cypher@IP docker exec fresh-db psql -U postgres -d fwapg` (`schema_consolidate.R:134,186`); the probe uses the same route.
- The CSV newline moves `config_hash` for all four bundles (file digest, `R/lnk_log.R:124`). Operator call: hashes are accounting, not a gate, so that is fine. The only check that fails on a second hash is the one-off `data-raw/logs/provincial_246/verify_extra.sql`, not the standing `study_area_verify.sql`.

Operator calls (plan gate): add the newline; **keep any host that may hold unconsolidated work, on abort too**, with accounting loud enough that a kept host cannot go unnoticed.

## Phase 1: Tests first (red)
- [x] `tests/testthat/test-study_area_hosts.R`: runs `bash` on the new lib with PATH stubs for `ssh`, `psql`, `tofu`, `doctl` and a mock `cypher_down.sh` in a temp `CYPHER_DIR` that records its calls; `skip_if_not()` when `data-raw/` is absent (R CMD check), `skip_if` no bash >= 4.
- [x] Case: a host log with every `done` marker mid-line, DB fixture holding every group → host reported complete.
- [x] Case: `SKIP` mid-line is accounted for and not put in the consolidate bucket.
- [x] Case: DB finished set larger than what consolidate took → that host is not burned (mock never called for it), the other host is; kept-hosts file names it.
- [x] Case: probe fails (ssh error / no end sentinel) → state `unknown`, never "complete", host kept.
- [x] Case: abort after dispatch (trap path) keeps every holding host; abort before dispatch burns all, as today.
- [x] Confirm red on main's logic; record the mutation (restore the anchored match → mid-line fixture fails) in findings.

## Phase 2: Host-accounting lib
- [x] New sourceable `data-raw/study_area_hosts.sh` (no top-level side effects; globals named in its header):
  - `host_finished <label> <ip|local>`: `SELECT DISTINCT watershed_group_code FROM <schema>.log WHERE run_uid = '<uid>' AND date_end IS NOT NULL`, output framed by begin/end sentinels so a failed ssh/psql is `unknown`, not "none" (Tailscale/ssh exit status not trusted).
  - `host_log_reported <logfile>`: unanchored `[wsg_run_one] <WSG> … done|SKIP` parse; diagnosis plus the SKIP set only.
  - `burn_cyphers` moved here: burns only hosts with `CY_HOLD[$WS]=0`; for each kept host writes a row to `${TS}_kept_hosts.tsv` (host, reason, finished n, consolidated n, burn command) and prints a banner with the `cypher_down.sh --workspace <ws>` command. `--keep-cyphers` still keeps all.
- [x] Phase 1 tests green.

## Phase 3: Wire the driver

Revised after the plan review (`review-plan.md`): bucket = DB ∪ log done; release measured after consolidate (no `streams` rows left on the host for anything it ran or finished) and only when its session exited 0; hosts whose DB did not answer are left out of consolidate and kept; a failed burn stays listed.
- [x] `study_area_run.sh` sources the lib; `CY_HOLD[$WS]=1` set immediately before the bucket dispatch.
- [x] Completeness: finished = DB set ∪ log SKIP set, for the dispatcher (local psql) and each cypher; a log/DB disagreement is printed as diagnosis, never used to decide.
- [x] Consolidate bucket = DB finished set; on `unknown` fall back to the log set and leave the host held.
- [x] After consolidate succeeds, clear `CY_HOLD` per host only when its probe succeeded and finished ⊆ consolidated; the explicit burn then burns cleared hosts only. Consolidate failure → `exit 1` → trap keeps every held host.
- [x] End of run: any kept host makes the run exit non-zero with its own `=== HOSTS KEPT ===` block (separate from RUN_INCOMPLETE / RECOMPUTE_FAIL), pointing at the TSV.
- [x] `bash -n`; `--preflight-only` run still passes (no spend).

## Phase 4: Backstop so a kept host is noticed
- [x] `preflight_local`: list cypher droplets via doctl; fail when one sits in this run's `--cy-workspaces` (a host kept by an earlier run), warn for any other, naming each and its burn command. Droplet naming confirmed against rtj's cypher tofu first.

## Phase 5: Quieter logs
- [x] Add the final newline to `cabd_blkey_xref.csv` in `bcfishpass`, `default`, `default_extrabreaks`, `default_rearbreaks`; confirm `lnk_load_overrides(lnk_config("default"))` no longer warns. Note in NEWS that `config_hash` moves for all four bundles (accounting).

## Phase 6: Live check, docs, follow-up
- [x] `host_finished local` against `fresh_default` for run_uid `20261017_004619-3f4c713b` returns 241.
- [x] RUNBOOK: driver completeness and burn rules (DB is the count, holds, kept-hosts TSV, preflight backstop). CLAUDE.md #246 status fact on #347 updated.
- [x] Draft (not file) a follow-up issue: config_hash checks that fail a run should record instead ("accounting, not a cage"), naming `verify_extra.sql` and reviewing `lnk_preflight_parity()`'s cross-host hash compare. Body shown for review.

## Validation
- [x] Tests pass (`devtools::test()`: 3058 pass, 5 fail, none in this work: 3 need the `:63333` tunnel, which is down; 2 are the golden dams count, which fails the same on clean main), lintr clean on the new test file
- [ ] `/code-check branch` clean
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Out of scope: #348 (coverage gate exits before the recompute).
