# Task: study_area_run.sh: bound each modelling statement, so a runaway statement fails as a named group (#371)

On 2026-10-23 (`20261023_074321-24d85e8c`) one dispatcher group, OKAN, sat inside a single SQL statement (fresh's near-river walk) from 09:19 UTC until the operator cancelled it at 13:30 UTC. A second, KTSU, took 65 min where it took 1.3 min on 2026-10-17. Nothing in the driver bounds one statement: a group's modelling ends when its last statement returns, and the cloud legs (finished by 12:27 UTC) waited idle on it.

Plan approved 2026-10-23 (plan mode, `/planning-init 371`).

## Context

On 2026-10-23 (`20261023_074321-24d85e8c`) OKAN sat in one statement (fresh's near-river walk) for 4 h 11 min and KTSU took 65 min instead of 1.3. Nothing in `data-raw/study_area_run.sh` bounds a statement, so the cloud legs idled and the operator found the stall in `pg_stat_activity`, then fixed it with a role-wide `ALTER ROLE … SET statement_timeout`. A bound turns the hang into a group failure that the #348 machinery already handles: the `[WARN] … failed (continuing)` line, the INCOMPLETE summary, then a re-model and `--recompute-only --run-uid=`.

## What exploration found

- **The modelling legs** are at `study_area_run.sh:1370-1375` (local loop) and `:1405` (the ssh string, which already exports `LNK_GUARD_DOWNSTREAM`, `LNK_HABITAT_GATE` and `LNK_RUN_UID` on both legs).
- **The recompute is already bounded.** `wsg_recompute_one.R:44-45` sets `statement_timeout = 10 min` and `lock_timeout = 1 min` on its connection, and RUNBOOK §6 (~l.490) explains why. A session `SET` overrides `PGOPTIONS`, so that bound holds whatever the env says.
- **Measured for the default** (`fresh_default.log`, the run's finished groups): the longest whole group is SETN at 16.3 min, then LNAR at 13.8 and BULK at 13.7. KTSU's 65.4 min is the stall itself. No single statement can exceed its group's total, so **30 min** gives at least 1.8× headroom over any statement of the run.
- **Naming the statement.** fresh's `.frs_db_execute()` is a bare `DBI::dbExecute()`, so a cancelled statement's error carries no SQL ("canceling statement due to statement timeout"). The SQL is still reachable from a calling handler, though: the DBI frames are still on the stack and hold it as `statement`. link's `.lnk_db_execute()` names it as `sql`.
- `.lnk_log_run_fail()` already leaves a failed group's log row open with notes. The `--recompute-only` path and `study_area_verify.sql` (6f, 6g) already handle a row like that.
- **Test harness:** `tests/testthat/test-study_area_finish.R` runs the bash libs and the driver against a scratch schema on local docker fwapg, with an Rscript stub on PATH.

## Decided at the gate (my recommendation; reject to change)

1. **The mechanism is `PGOPTIONS='-c statement_timeout=<N>min'`,** as the issue proposes. It is prefixed to the local leg's command and exported in the ssh string, appended to any `PGOPTIONS` the operator already set. It is not exported driver-wide, so the recompute keeps its own 10-minute `SET`. That is the header's answer to "separate, larger bound, or none": the recompute keeps its existing 10 min per statement, which is tighter, not looser, and was not hit on 2026-10-23.
2. **`--statement-timeout=<minutes>`, default 30.** It takes a positive integer (base-10 normalised, at most 1440) and refuses 0, so there is no unbounded mode. `--recompute-only` refuses it, as it refuses other dispatch flags.
3. **The bound is checked, not assumed.** `wsg_run_one.R` prints `SHOW statement_timeout` per group, so every host's log shows the bound actually in effect. That catches the both-legs trap (#227, #262) on its first group.
4. **Test hook `LNK_TEST_STALL_WSG=<WSG>`, on the local leg only.** `wsg_run_one.R` runs `SELECT pg_sleep(3600)` for that group before modelling. It refuses to do so unless a non-zero bound is in effect, so the hook can never hang a run.

## Phase 1: Tests first
- [x] `tests/testthat/test-lnk_timeout_statement.R`:
  - a frame-walk unit test: a nested function that holds `statement` / `sql` raises a timeout-shaped error, and the helper returns the first non-blank line, trimmed and capped. A non-timeout error returns NULL.
  - a live test (skip without local fwapg): `SET statement_timeout='200ms'` and `pg_sleep(2)` through `DBI::dbExecute`, and the helper names `SELECT pg_sleep`.
- [x] `test-study_area_finish.R`:
  - `run_timeouts()` names the groups and statements from fake `${TS}_run_*.log` files (dispatcher and cypher formats), and prints nothing when none timed out.
  - Driver arg tests: `--statement-timeout=0`, `abc`, `010` (which normalises to 10) and `>1440` are refused; `--statement-timeout` with `--recompute-only` is refused; the banner line shows the bound.

## Phase 2: Name a timed-out statement (R side)
- [x] `.lnk_timeout_statement(e, frames)` in `R/utils.R`. It returns `"<first line of SQL>"` when `e` is a statement-timeout cancel, and NULL otherwise. It walks frames innermost-first for a character `statement` or `sql`.
- [x] `data-raw/wsg_run_one.R`:
  - print `[wsg_run_one] <WSG> statement_timeout=<SHOW value>`;
  - wrap the stall hook and `lnk_pipeline_run()` in `withCallingHandlers(error=)`, which on a timeout prints `[wsg_run_one] <WSG> TIMEOUT after <bound>: <statement>` and then lets the error propagate (exit non-zero, the log row is left open as now);
  - add the `LNK_TEST_STALL_WSG` hook with its refusal guard.

## Phase 3: The driver
- [x] `study_area_run.sh`:
  - parse `--statement-timeout=` and validate it;
  - add `PGOPTIONS` on the local leg and inside the ssh string;
  - add a banner line (`statement:    30 min per modelling statement (PGOPTIONS, both legs); recompute 10 min (wsg_recompute_one.R)`);
  - document the flag and the recompute's bound in the header.
- [x] `study_area_finish.sh`: `run_timeouts()` greps the run's host logs for `TIMEOUT` lines. `run_finish_report()` prints them under INCOMPLETE as "timed out (statement bound N min): GROUP — statement".

## Phase 4: Docs
- [ ] RUNBOOK §8d: a new subsection, "A runaway statement fails its group (link#371)". It covers the bound, the env var, why `PGOPTIONS` and not a role setting, the 30-min measurement, the recompute's own bound, how a timeout reads in the log and the summary, and the finish path.
- [ ] RUNBOOK §6 (~l.490): one line saying the modelling legs are now bounded too.

## Owed at the end (reported, done after merge)
- [ ] A full provincial run at the default bound completes with no group timing out (acceptance criterion 2; it needs the next `default` run).

## Validation
- [ ] Tests pass (`devtools::test()`), lint is clean
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

**How each change is proved:**
- **`PGOPTIONS` reaches RPostgres.** Run `PGOPTIONS='-c statement_timeout=1234' Rscript -e` with `lnk_db_conn()` and `SHOW statement_timeout`, and expect `1234ms`. Then repeat without it as the control.
- **The mutations bite.** Remove the ssh-leg export and the SHOW line exposes it; neuter the helper and its test goes red; drop `run_timeouts()` from the report and the finish test goes red.
- **Acceptance 1, end to end, on the dispatcher only:**
  - Run from a worktree of the pushed branch (CLAUDE.md: edit nothing in a repo a run models from) into a scratch schema `fresh_371`.
  - Model two small groups with `--buckets-exact --statement-timeout=1 LNK_TEST_STALL_WSG=<one of them>`.
  - Expect: that group fails at about 1 min with a `TIMEOUT … pg_sleep` line, the other finishes, the INCOMPLETE summary names the stalled group and its statement, and the exit is non-zero.
  - Then re-model it by hand under the run_uid and run `--recompute-only --run-uid=`, which exits 0.
  - Drop `fresh_371` afterwards. The evidence goes to `data-raw/logs/statement_timeout_371/`.
