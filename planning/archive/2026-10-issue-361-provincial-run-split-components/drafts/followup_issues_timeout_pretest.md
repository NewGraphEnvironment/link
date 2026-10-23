# Two follow-up issue drafts (NOT filed; for the operator's review)

---

## Draft A — study_area_run.sh: a statement timeout per modelling statement, so a runaway statement fails as a named group

### Problem

On 2026-10-23 (`20261023_074321-24d85e8c`) one dispatcher group, OKAN, sat inside a single SQL statement (fresh's near-river walk) from 09:19 UTC until the operator cancelled it at 13:30 UTC. A second, KTSU, took 65 min where it took 1.3 min on 2026-10-17. Nothing in the driver bounds one statement: a group's modelling ends when its last statement returns, and the cloud legs (finished by 12:27 UTC) waited idle on it. The driver had no way to say "this group is taking too long"; the operator found it by reading `pg_stat_activity`.

The same statement on the same working tables, re-run after the run, took 59 s (OKAN) and 3 s (KTSU) with the same plan, so the stall was not the SQL or the data. Whatever it was, a bound on statement time is what turns it from a four-hour hang into a named failure the run's existing machinery already handles (`[WARN] dispatcher WSG … failed (continuing)`, `--recompute-only --run-uid=` after a re-model, #348).

### Proposal

- `study_area_run.sh` sets `PGOPTIONS='-c statement_timeout=<N>'` for both modelling legs (local, and inside the ssh command string, as `LNK_GUARD_DOWNSTREAM` is), with a `--statement-timeout=<minutes>` flag defaulting to something like 30 min. RPostgres uses libpq, so `PGOPTIONS` reaches every connection the pipeline opens without a role or server change. The operator's hand fix on 2026-10-23 was `ALTER ROLE postgres SET statement_timeout = '30min'`, which reaches every session on the host and had to be reset afterwards; the env var reaches only the run.
- The recompute leg keeps a separate, larger bound (`wsg_recompute_one.R`'s longest group was 22.7 min at `-j8` on 2026-10-23), or none; say which in the header.
- The banner prints the bound beside the other run decisions, and a group that times out is named with the statement's first line in the run log.
- Measurement to set the default: the longest single statement on 2026-10-23 among the 240 groups that finished (take it from `log` per-group minutes as an upper bound; SETN 16.3 min total).

### Acceptance

- A deliberately slow statement (e.g. `pg_sleep` injected under a test flag, or a tiny `--statement-timeout=1`) fails one group, the run continues, the group is named in the INCOMPLETE summary, and `--recompute-only --run-uid=` finishes it after a re-model.
- A full run at the default bound completes with no group timing out.
- RUNBOOK §8d names the bound and the env var.

### Related

#361 (the run), #348 (a failed group costs only itself), #369 (consolidate on finish; both shrink the cost of one slow group).

---

## Draft B — A scoped pre-run gate: model the groups that stress each rule changed since the last provincial run

### Problem

Each provincial run is the first time some newly landed code meets every group. On 2026-10-23 the near-river walk (link 0.67.0 / fresh 0.42.0, #364) had been built and scored on ADMS, BULK, CHWK, CLWR and SQAM; the run was its first contact with OKAN and KTSU, and the dispatcher lost about five hours to those two groups while three cloud hosts idled. Whether or not the walk itself was the cause (see the #361 record), the pattern is general: a rule's cost and its correctness are driven by an input the test groups did not carry (here, lake connector length and lake-centreline density), so a happy-path group set cannot find it before the ten-hour run does.

Operator, 2026-10-23: "Provincial runs should prob be pretended with scoped tests to be sorted we have a working system before running for 10hrs to find out."

### Proposal

A pre-run gate, run on the dispatcher before `study_area_run.sh` spends anything, that models a small set of groups chosen by the inputs that drive the code changed since the last run, and refuses the launch when any of them fails or takes more than k× its last-run minutes.

- **Picking the groups is the method, not a fixed list.** For each rule or pipeline step changed since the last run's link SHA (`git log <last_run_sha>..HEAD -- R/`), name the input that drives its cost or its branches, and take the 2 or 3 groups at the extreme of that input from the database (e.g. longest connector run per group for the near-river walk; most PSCIS crossings per group for the pick; most dams for the placeholder rule). Record the pick and its query in `data-raw/logs/provincial_<issue>/pretest.md`.
- **The time bound is per group against its own history**: the group's newest `log` minutes in the persist schema, times a factor (3× is a start; KTSU was 50×).
- **Where it runs**: m1, into a scratch schema (`fresh_pretest_<issue>`), with the run's config and flags, under a statement timeout (Draft A), so a stall is a failure within minutes, not a wait.
- **What it is not**: a parity or correctness test. The variants harness and `habitat_validate.R` keep that job. This gate asks only "does every changed path run to completion at a sane cost on the groups most likely to break it".

### Acceptance

- `data-raw/pretest_run.sh --since=<sha> --config=default` (name open) prints the changed files, the inputs chosen, the groups picked, models them into the scratch schema, and exits non-zero on a failure or a time bound breach.
- Re-run against link 0.68.0 with `--since=<0.66.6 sha>`: it must pick OKAN or QUES (longest connectors) for the near-river walk, and the result on them is recorded.
- `study_area_run.sh` header and RUNBOOK §8d say the gate precedes a provincial run.

### Related

#361, #364 (the walk), #367 (the pick), Draft A.
