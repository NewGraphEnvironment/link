# Code-check round 4: link#347 branch, terminating enumeration

Reviewer: subagent, 2026-10-17, at HEAD `3c366b1d`. Scope: every row of round 3's table
re-walked against HEAD, every place the round-3 fixes added, and every label the lib, the
driver and the RUNBOOK print. No repo file edited. Demos ran in
`$SCRATCHPAD/r4/` with stub `ssh` on PATH and the real `data-raw/study_area_hosts.sh`
sourced. Test file run: `NOT_CRAN=true test_file()`: 31 blocks, 0 failed, 0 error, 0 skipped.

## Enumeration

**43 rows** (21 from round 3, 22 new). **12 verified by running** (a scratchpad demo, or a
named test in the 31-block run that asserts that exact row), **31 by reading.**
**3 unsafe** (Findings 1-3), one of them latent.

The mechanism round 3 named still holds, and all three findings fit it. Each fix checks
provenance or settledness through a variable whose meaning on some path differs from what
its name says:

- `CY_RUN_RC[ws] = 0` is assigned before the wait it stands for.
- `ACC_*` is empty before accounting, so "no finish signal" is really "not read yet".
- `CY_PRE` is taken from `streams`, but the rows it has to discount are in
  `streams_mapping_code`.

## Findings

### 1. The host the driver is waiting on reads as settled, so round 3's Finding 1 still happens (unsafe: finished work labelled "partial, do NOT consolidate", then burned)

`data-raw/study_area_run.sh:1088-1096`:

```bash
  CY_RUN_RC[$WS]=0
  wait "${CY_PID[$WS]}" || {
    CY_RUN_RC[$WS]=$?
```

`CY_RUN_RC` is set to 0 *before* the wait. When the driver gets SIGTERM during that wait,
nothing has trapped TERM, so bash runs the EXIT trap and the `||` branch never runs. The
host being waited on is left with `CY_RUN_RC = 0`, and its ssh session (the remote bucket
loop) is still alive. `.hosts_settled` (`study_area_hosts.sh:154`) reads exactly that
variable. So `hosts_kept_report` (`:431-432`) marks the host `groups_measured = yes`, and
prints "partial, do NOT consolidate" for groups that are still being built.

The window is wide. The driver waits on the cyphers in array order, after the dispatcher.
So whenever cypher 1 outlasts the dispatcher, the driver sits in `wait CY_PID[cypher1]`,
and a kill in that time hits this host.

Measured:

- `r4/waitkill.sh` (bash 5.3.9): the trap saw `RC[a]='0' RC[b]='<unset>' child_alive=yes`.
- `r4/demo_waitkill.sh` (real lib, the driver's exact wait shape, baseline empty, AAAA
  finished, BBBB still building):

```
  cy[a] (cypher-a): run stopped before consolidate released it; may hold finished groups
    finished, still on the host: AAAA
    partial, do NOT consolidate: BBBB
TSV: a  AAAA  BBBB  ""  yes
```

The tests did not catch this because `run_hosts()` sets `CY_RUN_RC[$ws]=0` for every host
by default. The abort test passes only because it `unset`s the value explicitly. That
models a host the loop has not reached yet, and never the one it is waiting on.

The RUNBOOK sentence "A host whose session has not ended 0 is **unsettled**" is false on
this path.

Fix: assign only after the wait returns:

```bash
rc=0; wait "${CY_PID[$WS]}" || rc=$?; CY_RUN_RC[$WS]=$rc
```

Add a lib test with the host waited on (the RC set, then the trap fired), or a driver-shape
demo like the one above.

### 2. A kept report taken before accounting reads none of this run's finish signals, so on a settled host a `CY_PRE` group finished this run is labelled partial (unsafe: finished, paid work burned)

`study_area_hosts.sh:186`: `fin = ACC_FINISHED ∪ ACC_DONE_LOG ∪ (complete − CY_PRE)`.

`ACC_*` is filled only by `host_account` (driver `:1293-1305`), which runs after every wait.
Take the EXIT trap firing after host *a*'s wait returned 0 but before accounting, for
example a kill while waiting on host *b*. That state is real: *a* really is settled. But
`ACC_FINISHED[a]` and `ACC_DONE_LOG[a]` are empty. `hosts_kept_report` (`:429-432`) calls
`host_split` without querying the host's `<schema>.log` or reading `${TS}_run_a.log`, both
of which hold this run's finish record. So for a group in `CY_PRE` (rows from the image,
rebuilt and finished this run) the only signal left is mapping code, and round 3's fix
subtracts it. The group lands in `groups_partial` with `groups_measured = yes`, and the
banner says "partial, do NOT consolidate".

The operator consolidates `groups`, burns, and the finished build is lost. The same path
with `CY_PRE_STATE = unknown` sends every finished group to `groups_unknown` instead
(held and flagged, so not lost, but under-reported).

Measured, `r4/demo_pre.sh`. Host *a* has AAAA in its baseline. The DB log answers AAAA and
BBBB finished for this run, and `${TS}_run_a.log` says `AAAA done`. RC=0, killed during
the wait on *b*:

```
  NOTE: cy[a]: streams rows before dispatch (from its image) for: AAAA
    finished, still on the host: BBBB
    partial, do NOT consolidate: AAAA
TSV: a  BBBB  AAAA  ""  yes
```

How often this happens depends on `CY_PRE` being non-empty. `cypher_prep`'s
`force_recreate` drops a drifted `fresh.streams`, so it may be empty on today's image. But
the round-3 fix exists because it can be non-empty, and it prints a NOTE when it is.

Fix: when `ACC_STATE[ws]` is unset (no accounting yet), read `host_finished` and
`host_log_reported "$LOG_DIR/${TS}_run_$ws.log" done` into `fin` before splitting. Or, if
that is not wanted, put a `CY_PRE` group with no read finish signal in `groups_unknown`,
never `groups_partial`.

### 3. (Low, latent) The baseline is taken from `streams`, but the rows it must discount are `streams_mapping_code`; a stale mapping-code row on a group whose `streams` was dropped still reads as finished

`study_area_hosts.sh:135-148` (`host_baseline` uses `host_remaining`, which reads
`streams`) and `:180-181` (the subtraction applies only to the `CY_PRE` groups).

`lnk_persist_init(force_recreate = TRUE)` decides per table
(`R/lnk_persist_init.R:195-219`). On the warm image it drops `fresh.streams` (GENERATED
drift, the documented "snapshot artifact") and keeps any other table with its rows. If an
image ever carries `streams_mapping_code` rows, a group that fails after the pre-persist
this run has two things on the host: new `streams` rows and stale mapping code. The
baseline saw no `streams` rows, so `CY_PRE` is empty, and the group is recoverable.

`r4/demo_f3.sh`: `host_account` prints "not finished: AAAA", while the TSV says
`groups = AAAA, groups_measured = yes` and the banner says "finished, still on the host:
AAAA". Recovery would consolidate a broken build over the dispatcher's copy.

Not reachable today: the image (`cypher-20260512-warm`, link 0.35.0) predates
`streams_mapping_code`.

Fix: take the baseline from `streams_mapping_code` too (or instead), and subtract the
groups that had mapping-code rows before dispatch. The RUNBOOK sentence "their mapping-code
rows are not this run's" then covers every group whose mapping-code rows existed before,
not only those that also had `streams` rows.

## Full table

Direction: **safe** (over-reports or holds), **unsafe**, **latent**, **pre-existing**.
How checked: **R** = run (a demo, or a named test in this run), **r** = read.

### (a) Round 3's 21 rows at HEAD

| # | file:line at HEAD | action | changed by 3c366b1d? | provenance / settledness on every path | verdict | how |
|---|---|---|---|---|---|---|
| 1 | hosts.sh:218-256; run.sh:1293-1309 | completeness report, `RUN_INCOMPLETE`, exit 1 | no | DB rows keyed by this `run_uid`; the log file is this run's `${TS}_run_$ws.log`; runs after every wait (settled) | safe (over-reports on a lost run_uid / failed `date_end`) | R (tests "mid-line", "not finished in the database") |
| 2 | hosts.sh:263-267; run.sh:1304, 1312-1358 | consolidate bucket (DB ∪ log done) | no | this run's signals only; independent of `CY_PRE` | unsafe-but-unreachable as before (schema mismatch); loud | r |
| 3 | hosts.sh:264 | unknown host left out of consolidate | no | — | safe | R (test "unknown finished set is left out") |
| 4 | run.sh:1327-1331, 1339-1343 | empty bucket skipped; zero sources has its own branch | no | — | safe | r |
| 5 | hosts.sh:275-296; run.sh:1362-1366 | release (`CY_HOLD=0`), then burn | yes (`CY_DOUBT` arm added) | reached only after every wait returned, so `CY_RUN_RC` is the real status; `ACC_*` filled | safe | R (tests "partial rows neither hold", "with no baseline … hold the host") |
| 6 | hosts.sh:431-432, 447-456 | label `partial` / "do NOT consolidate" | yes (settled vs unsettled) | settledness from `CY_RUN_RC`, pre-set to 0 during the wait (F1); provenance of "no signal" wrong before accounting (F2) | **unsafe: Findings 1, 2** | R (demo_waitkill, demo_pre) |
| 7 | hosts.sh:164-191, 445-448 | label `groups` (recoverable) | yes (`CY_PRE` subtraction, `CY_DOUBT`) | correct where the baseline covers the stale rows; a mapping-code-only stale row is missed | **latent: Finding 3** | R (demo_f3) |
| 8 | hosts.sh:433-438, 457-458 | `measured = no`: candidates | no (now also clears `CY_DOUBT`) | banner says NOT measured | safe | r |
| 9 | hosts.sh:467-474; RUNBOOK 1265-1268 | recompute instruction | yes (`RECOMPUTE_RAN`) | consolidate-fail and coverage FATAL: 0, so "recompute every group", correct | safe | R (tests "aborted run's report", "settled host's report") |
| 10 | hosts.sh:329-334, 428; run.sh:1568-1569 | `KEPT_CAUSE_N`, then non-zero exit | no (`CY_DOUBT` sets `CY_WHY`, so it counts) | — | safe | r |
| 11 | hosts.sh:361-397 | `CY_BURNED=1` | no | — | safe | R (tests "burn that does not complete", "doctl still lists") |
| 12 | hosts.sh:308-325; run.sh:692-699 | refuse a spin into a live workspace | no | — | safe | R (test "pre-flight fails") |
| 13 | hosts.sh:76-100 | known vs unknown (sentinels) | no | — | safe | r |
| 14 | hosts.sh:114-129 | missing streams / mapping-code table: unknown | no; now also feeds the baseline (pre-dispatch missing table → unknown → `CY_DOUBT`) | — | safe | R (test "missing mapping-code table") |
| 15 | hosts.sh:105-107 | missing log table: known, empty | no | — | safe | r |
| 16 | run.sh:1055-1060 | hold from dispatch | yes (baseline loop first) | an exit during the baseline burns all; nothing dispatched yet | safe | r |
| 17 | run.sh:1088-1096 | `CY_RUN_RC` | **meaning changed**: now drives settledness | 0 assigned before the wait; a trap during the wait reads 0 with the ssh child alive | **unsafe: Finding 1** | R (waitkill.sh) |
| 18 | run.sh:1386-1404 | coverage FATAL | no | rows-present, not this-run (documented) | safe given `RUN_INCOMPLETE` | r |
| 19 | run.sh:1371-1374, 1515 | recompute over `ALL_WSGS` | no | — | pre-existing (#348) | r |
| 20 | bucket overlap | last writer wins | no | — | pre-existing | r |
| 21 | hosts.sh:83-86 in the trap | ssh with no command timeout | no; `host_baseline` adds the same probe before dispatch | a hang stalls, no loss; `burn_cyphers` is called under `||`, so `set -e` is off inside it | note | r |

### (b) Rows the round-3 fixes introduced

| # | file:line | what | state checked | verdict | how |
|---|---|---|---|---|---|
| 22 | run.sh:1055 | `host_baseline` call site | before `CY_HOLD=1`, after the dispatcher job starts; `set -e` live, every fallible call sits in `if`; returns 0 | safe | r |
| 23 | hosts.sh:137-141 | baseline known: `CY_PRE` set | `NOTE` printed; the test "mapping-code rows from the image" asserts it | safe | R |
| 24 | hosts.sh:142-146 | baseline probe failed: `CY_PRE_STATE=unknown` | WARN printed; mapping code goes to `CY_DOUBT` | safe | R (test "with no baseline … not a finish signal") |
| 25 | hosts.sh:135-139 | baseline measured on `streams` only | stale mapping code with a dropped `streams` is missed | **latent: Finding 3** | R (demo_f3) |
| 26 | hosts.sh:180-181 | `complete − CY_PRE` on the release path | `ACC_*` filled; a `CY_PRE` group finished this run is kept by DB / log done | safe | r |
| 27 | hosts.sh:180-181 + 429-431 | `complete − CY_PRE` in a kept report before accounting | `ACC_*` empty; a `CY_PRE` group finished this run reads partial | **unsafe: Finding 2** | R (demo_pre) |
| 28 | hosts.sh:182-184 | settled host, baseline failed, before accounting | every finished group goes to `groups_unknown`; held, flagged "check before consolidating" | safe (under-labelled, not lost); same root as F2 | r |
| 29 | hosts.sh:188-189 | `CY_DOUBT` minus fin; `CY_PARTIAL` minus `CY_DOUBT` | disjoint sets; `CY_DOUBT` never in `groups` | safe | R (test "hold the host but are not recovered") |
| 30 | hosts.sh:285-286 | `CY_DOUBT` holds in `host_release` | sets `CY_WHY`, so `KEPT_CAUSE_N` counts it | safe | R (same test) |
| 31 | hosts.sh:436, 445-446 | `CY_DOUBT` cleared when measured=no; printed otherwise | — | safe | r |
| 32 | hosts.sh:154 | `.hosts_settled` definition | the only caller is hosts.sh:432; its input is wrong during the wait | **unsafe via Finding 1** | R |
| 33 | hosts.sh:279 | `host_release` reads `CY_RUN_RC` with a `:-1` default | after the waits, so correct | safe | R (test "session that exited non-zero") |
| 34 | hosts.sh:451-456 | unsettled banner | true wherever RC is really not 0 | safe | R (test "aborted run's report") |
| 35 | run.sh:1518 | `RECOMPUTE_RAN=1` after the pool | a pool failing under `set -e` leaves 0, so "recompute every group" (over-instructs) | safe | r |
| 36 | hosts.sh:467-469 with `RECOMPUTE_FAIL=1` (pool) | "ran WITHOUT these groups" | the failed WSGs are named by the INCOMPLETE block (run.sh:1593-1609) printed first; on the compare-fail exit (run.sh:1545) only "✗ recompute incomplete" names them, which is the pre-existing compare-fail path | safe / pre-existing | r |
| 37 | run.sh:1369 then the trap | banner printed twice: "did NOT run" at the explicit burn, the true state at exit | the TSV carries no recompute field; the last banner is current | safe | r |
| 38 | run.sh:1579-1585 | driver INCOMPLETE recompute wording | matches the lib | safe | r |
| 39 | hosts.sh:429-438 trap, `CY_IP` set, droplet gone | ssh fails, so measured=no, candidates | `accept-new` refuses a reused IP with a new key; errexit off inside `burn_cyphers ||` | safe | r |
| 40 | baseline vs consolidate bucket | bucket = DB ∪ log done, never reads `CY_PRE` | a `CY_PRE` group that SKIPped or failed is not consolidated | safe | r |
| 41 | hosts.sh:290-291 | release note "partial … failed builds, rebuild them" for a `CY_PRE` group SKIPped this run | wording only; nothing lost | safe | r |
| 42 | tests:136 `run_hosts` | defaults every host to `CY_RUN_RC=0` | no test models the host being waited on, which is why F1 passed | test gap behind F1 | r |
| 43 | hosts.sh:425 TSV | no baseline column | an operator re-measuring an unsettled host by hand cannot discount image rows | safe today (no stale mapping code on the image); feeds F3 | r |

### (c) Labels, and what each one assumes

| label (where) | assumes | established on every printing path? |
|---|---|---|
| TSV `groups` / "finished, still on the host" (hosts.sh:440, 448) | provenance: a this-run signal; settled | **no**: F1 (settled read wrong), F2 (signals unread before accounting), F3 (stale mapping code) |
| TSV `groups_partial` / "partial, do NOT consolidate" (441, 450) | settled, and every finish signal was read | **no**: F1, F2 |
| "NOT finished when probed (may still be building)" (455) | unsettled | yes |
| TSV `groups_unknown` / "unknown provenance" (441, 446) | provenance undecidable | yes (over-holds) |
| TSV `groups_measured` yes / unsettled / no (432, 437) | yes = settled | **no**: F1 |
| TSV `reason` (`.hosts_keep_reason`) | `CY_WHY` or held | yes |
| "host did not answer; candidates (NOT measured)" (458) | — | yes |
| "recompute ran WITHOUT these" / "did NOT run" (467-473) | the pool started / did not start | yes; failures reported separately |
| host_release "may be burned" / "partial … rebuild them" (289-291) | settled (after the waits), `ACC` read | yes |
| host_release "✗ … KEEPING it (groups: …)" (294) | informational; the later TSV supersedes it | yes |
| host_account ✓ / ✗ / notes (235-254) | after the waits; DB keyed by run_uid | yes |
| host_baseline NOTE / WARN (141, 145) | before dispatch; "from its image" (pre-flight refuses an adopted droplet) | yes |
| driver INCOMPLETE kept / recompute block (1572-1586) | as for the lib banner | yes |
| RUNBOOK "partial (it failed after the pre-persist) … never consolidated" | settled and signals read | release path yes; trap path **no** (F1, F2) |
| RUNBOOK "A host whose session has not ended 0 is unsettled" | RC assigned after the wait | **no** (F1) |
| RUNBOOK "their mapping-code rows are not this run's" | the baseline covers mapping code | only for groups that had `streams` rows (F3, latent) |

## Not reported

- An unsettled probe taken during the final persist's DELETE / INSERT window omits the
  group from every column. The banner says to re-measure, so this is safe.
- A `CY_PRE` group that finished its final persist but printed no `done` and closed no log
  row reads partial on the release path. This is round 3 row 5's essentially unreachable
  edge, now also for `CY_PRE` groups.
