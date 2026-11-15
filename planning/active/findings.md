# Findings — Record what a stalled statement is waiting on while it stalls (#487)

## Issue context

**If we do it:** the next stall leaves a record of why it stalled: a lock and the session holding it, an I/O or worker wait, or a statement that is simply working. That lets it be fixed where it lives, in the driver's ordering or in fresh's walk. **If we never do:** the cause stays unknown. This stall has now failed or held up runs on four dates, and each time the evidence was gone before anyone could read `pg_stat_activity`.

## Problem

Fresh's near-river walk (`CREATE TEMP TABLE pg_temp.frs_near_river_walk AS ...`) sometimes runs for an hour or more where it normally takes a minute or two. Every case on record:

| date | run | group | normal | stalled |
|---|---|---|---|---|
| 2026-10-23 | provincial run, on m1 | OKAN; KTSU | 59 s and 3 s when re-run afterwards on the same tables, same plan | over 4 h (cancelled); 65 min |
| 2026-10-25 | `worker_376` Runs B and C, on the dispatcher | KHTZ, MAHD | under 2 min in Run A | cancelled at the 30 min bound |
| 2026-11-13 | `20261113_032716-44ee6edc`, 241 groups, 4 hosts | TAHS | 2.1 min on a worker on 2026-11-03 | cancelled at 30 min |
| 2026-11-14 | `20261113_202138-1d2b0e18`, the same run shape, bound 60 | SANJ | 3.5 min in the run before | cancelled at 60 min |

The two November runs used link `e5acee31`, driven by `study_area_run.sh` from a cloud dispatcher the same size as its three workers. Their logs are kept outside this repo. CLAUDE.md records the October cases: "Mechanism not identified; no fresh issue filed".

What every case shares:
- **The stall is on the host whose database is taking other heavy work.** In October that was another session's load. In November it was workers consolidating into the dispatcher, with the `-j8` recompute running too. In the 2026-11-14 run, SANJ started about when the first worker's consolidation began (23:55Z, estimated to a couple of minutes, because `run_local.log` has no per-group timestamps).
- **No worker group has ever stalled.**
- **Groups either side, on the same host, under the same load, run at their usual speed.** On 2026-11-14 SALM, SKGT and SMOK took 2.4, 1.4 and 4.0 min, against 2.6, 1.4 and 4.5 the run before.
- **Re-run at rest, the statement is fast with the same plan** (the October case).

A higher bound does not help. 30 and 60 min both expired, on a statement that normally takes minutes. All it does is tell a slow statement from a stuck one, and it costs that much wall time per stall.

## Proposed Solution

Record, while the stall is happening, what the stalled backend is doing. A cancelled backend can no longer be inspected, so one snapshot taken at the bound comes too late. Suggested shape (the design is link's call):

1. While a group runs, a second connection checks every 60 s whether that group's backend has been on one statement for more than N minutes (10 by default, settable). Once it has, each check appends one row to `<TS>_stall_<WSG>.tsv`. A row holds the backend's `pg_stat_activity` fields (`state`, `wait_event_type`, `wait_event`, `query_start`), the same for its parallel workers (`leader_pid`), and `pg_blocking_pids()`. For each blocker it also holds `pid`, `state`, `query_start` and the first 200 characters of `query`. The host's load average and the number of active backends on the database go in the same row.
2. The group's `TIMEOUT after` line names the file, and the driver's INCOMPLETE block repeats it beside "statement bound hit".
3. The sampler ends with its group, and cannot fail it. A sampler error is logged and the group carries on.

A series of samples rather than a single row shows whether the wait changed: a `Lock` wait that turns into no wait once consolidation ends, for example.

The plan is the open question. The walk reads the stalled session's own temp tables, so another session cannot `EXPLAIN` it. Recording the plan needs something inside the session, which is fresh's code. Leave that until the samples show whether the stall is a wait at all.

## Tests

Use the existing `LNK_TEST_STALL_WSG` hook: a `pg_sleep` stall must produce rows with `wait_event = PgSleep`. Add a lock case: a test session holds `ACCESS EXCLUSIVE` on a table the stalled statement reads, and the rows must name that session's pid and query in the blocker columns. Show both red before the sampler lands.

## Out of scope

- Fixing the stall. That waits on what the samples show: the driver building on the dispatcher while consolidation and recompute run, or something in fresh's walk.
- Changing the default bound.

## Acceptance

- Both test cases pass, and fail without the sampler.
- The next real stall leaves a `_stall_` file, its reading is written into this body, and the fix is filed where it belongs.

(No comments on the issue at 2026-11-14.)

## Errors Encountered

| Error | Resolution |
|-------|------------|
