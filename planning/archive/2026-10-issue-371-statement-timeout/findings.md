# Findings — study_area_run.sh: bound each modelling statement, so a runaway statement fails as a named group (#371)

## Issue context


## Problem

On 2026-10-23 (`20261023_074321-24d85e8c`) one dispatcher group, OKAN, sat inside a single SQL statement (fresh's near-river walk) from 09:19 UTC until the operator cancelled it at 13:30 UTC. A second, KTSU, took 65 min where it took 1.3 min on 2026-10-17. Nothing in the driver bounds one statement: a group's modelling ends when its last statement returns, and the cloud legs (finished by 12:27 UTC) waited idle on it. The driver had no way to say "this group is taking too long"; the operator found it by reading `pg_stat_activity`.

The same statement on the same working tables, re-run after the run, took 59 s (OKAN) and 3 s (KTSU) with the same plan, so the stall was not the SQL or the data. Whatever it was, a bound on statement time is what turns it from a four-hour hang into a named failure the run's existing machinery already handles (`[WARN] dispatcher WSG … failed (continuing)`, `--recompute-only --run-uid=` after a re-model, #348).

## Proposal

- `study_area_run.sh` sets `PGOPTIONS='-c statement_timeout=<N>'` for both modelling legs (local, and inside the ssh command string, as `LNK_GUARD_DOWNSTREAM` is), with a `--statement-timeout=<minutes>` flag defaulting to something like 30 min. RPostgres uses libpq, so `PGOPTIONS` reaches every connection the pipeline opens without a role or server change. The operator's hand fix on 2026-10-23 was `ALTER ROLE postgres SET statement_timeout = '30min'`, which reaches every session on the host and had to be reset afterwards; the env var reaches only the run.
- The recompute leg keeps a separate, larger bound (`wsg_recompute_one.R`'s longest group was 22.7 min at `-j8` on 2026-10-23), or none; say which in the header.
- The banner prints the bound beside the other run decisions, and a group that times out is named with the statement's first line in the run log.
- Measurement to set the default: the longest single statement on 2026-10-23 among the 240 groups that finished (take it from `log` per-group minutes as an upper bound; SETN 16.3 min total).

## Acceptance

- A deliberately slow statement (e.g. `pg_sleep` injected under a test flag, or a tiny `--statement-timeout=1`) fails one group, the run continues, the group is named in the INCOMPLETE summary, and `--recompute-only --run-uid=` finishes it after a re-model.
- A full run at the default bound completes with no group timing out.
- RUNBOOK §8d names the bound and the env var.

## Related

#361 (the run), #348 (a failed group costs only itself), #369 (consolidate on finish; both shrink the cost of one slow group).




## Test notes (Phase 1)

- The driver tests drop the plan's `010` case: the bound is only ever interpolated into a string (`${N}min`), never into `$(( ))`, so a leading zero cannot change its value; it is still normalised for the banner.
- Under `--recompute-only` the run's host logs carry the run_uid's timestamp (`${RUN_UID%-*}`), not the session's TS, so `run_timeouts()` reads those and reports only groups still missing; a group re-modelled since then is no longer named.
