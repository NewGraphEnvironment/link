# Findings — study_area_run.sh counts finished groups from log text (#347)

## Issue context

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

## Proposal

- **Count completion from the database, not the log.** For each host, read `<schema>.log` for this `run_uid` (one row per finished group, with `date_completed` set) over the same ssh the consolidate uses. The log text stays for diagnosis only.
- **Never burn a host whose work is not consolidated.** When a host's finished set (from the DB) is larger than what consolidate took, keep it and say so at the end, as `--keep-cyphers` does.
- **Quieter logs:** `configs/default/overrides/cabd_blkey_xref.csv` has no final newline, so every group's log carries an `incomplete final line` warning. It is noise, not the cause.

## Acceptance

- A host log with every `done` marker mid-line still reports the host complete (fixture).
- A host with an unconsolidated finished group is not burned (mocked `cypher_down.sh`).
- Restore the anchored match and the fixture fails.


## Errors Encountered

| Error | Resolution |
|-------|------------|

## Facts measured in plan mode (2026-10-17)

- "Finished" is a `<schema>.log` row with the run's `run_uid` and `date_end` NOT NULL. The issue says `date_completed`; no such column. `date_end` is set by `.lnk_log_run_finish()` after persist (`R/lnk_pipeline_run.R:322`).
- A SKIP group (`wsg_run_one.R:56`) writes no log row, so its only signal is the log text. It holds nothing to consolidate.
- Probe over the live DB (local, `fresh_default`, run_uid `20261017_004619-3f4c713b`): 241 finished, the run's group count. psql 18.3 locally, 17.5 in `fresh-db`; both support `\if` / `\gset`.
- Droplet name per workspace: `cypher` for `default`, else `cypher-<ws with _ -> ->` (rtj `env/do/dev/cypher/main.tf:25-26`).
- Pre-existing: `CYPHERS_UP=1` is set only after every `tofu output droplet_ip` succeeds, so a failed spin of one workspace exits with the others' droplets unburned.

## Mutation table (Phase 1-2)

Each mutant run with `LNK_TEST_HOSTS_LIB=<copy>`; the real lib untouched.

| mutant | change | tests failing |
|---|---|---|
| m1 | anchor `host_log_reported`'s grep at `^` | 2 (mid-line fixture vs anchored match; mid-line SKIP) |
| m2 | `host_finished` ignores the sentinels | 2 (unknown never complete; unknown keeps host) |
| m3 | `host_release` ignores unconsolidated groups | 1 (host with unconsolidated group not burned) |
| m4 | `burn_cyphers` ignores `CY_HOLD` | 3 |
| m5 | count finished from the log with main's anchored `sed` (the issue's "restore the anchored match") | 5, including "every done marker mid-line is complete" |

Order note: the lib was written before the tests first ran, so "red first" was shown by mutation (m5 is main's counting rule), not by a run on main.

## Plan review folded in (2026-10-17)

`review-plan.md` holds the Plan agent's findings and their disposition. The release rule changed because of B1/G1, both verified in code: `.lnk_log_run_finish()` is soft (a persisted group can keep `date_end` NULL), and a lost `LNK_RUN_UID` leaves every row's `run_uid` NULL, so the DB finished set can undercount. Now: consolidate bucket = DB ∪ log done; a host is released only when its session exited 0 and, after consolidate, its DB has no `streams` rows for any group it ran or finished (consolidate deletes what it copied from the source, schema_consolidate.R:420-450). Hosts whose DB did not answer are left out of consolidate and kept. A failed burn is not marked burned; it is retried by the trap and listed as kept.

## Mutation table (after the review)

| mutant | change | tests failing |
|---|---|---|
| m1 | anchor `host_log_reported` at `^` | 5 |
| m2 | `.hosts_query` ignores the sentinels | 3 |
| m3 | `host_release` ignores streams rows left | 2 |
| m4 | `burn_cyphers` ignores `CY_HOLD` | 6 |
| m5 | count finished from the log with main's anchored `sed` (the issue's "restore the anchored match") | 9, including "every done marker mid-line is complete" |
| m6 | consolidate bucket drops log done | 2 |
| m7 | `host_release` ignores the session exit status | 1 |
| m8 | a burn is marked done whatever tofu/doctl say | 2 |
| m9 | release probe asks only about the bucket | 1 |

A first m1 pattern did not apply (escaping) and scored 0; `cmp` flagged it UNCHANGED and it was rebuilt with a literal replace.

## Live checks (2026-10-17, local fwapg)

- `host_finished local`, `fresh_default`, run_uid `20261017_004619-3f4c713b`: 241.
- The cypher route's remote half, `docker exec -i fresh-db psql`, run locally without ssh: both sentinels, 241 rows.
- `host_remaining local ADMS,ZZZZ`: `ADMS`. A schema that does not exist: known, 0 rows.
- `study_area_run.sh --preflight-only --config=default --schema=fresh_default --cy-workspaces=job1,job2`: lib sourced, no unbound variables, doctl leg and droplet check pass (no cypher droplets up); fails only on the unpushed branch and dirty tree, as it should.
- Not checked live: the ssh leg to a real cypher (needs a spin). The tests assert the ssh argv and stdin.

## CSV newline (Phase 5)

`lnk_load_overrides(lnk_config(<bundle>))` warned `incomplete final line` once per bundle before, 0 after. `config_hash` (first 12 hex) moves: bcfishpass c48ed74006b3 → ab24041706fe, default 7e9dffa4a5b8 → f505e76f5cfd, default_extrabreaks eb8ca82a1b4b → ff3ba0976103, default_rearbreaks 460282710911 → 38cfd720db23. Operator call: accounting, not a gate.

## Full suite (2026-10-17, at 5da51c9d)

`devtools::test()`: FAIL 5 | WARN 1 | PASS 3058. `test-lnk_db_conn.R:10` and `test-lnk_wsg_resolve.R:143,154` need the `:63333` tunnel (connection refused). `test-lnk_pipeline_prepare.R:964-965` (golden dams, 8 expected, 7 found) fails the same on a clean `origin/main` worktree, as CLAUDE.md records. The new file: 66 pass; with the lib absent, 20 skip.

## Follow-ups drafted, not filed

- config_hash checks as accounting, not gates (operator, 2026-10-17).
- consolidate deletes the destination's earlier `log` / `log_recompute` rows for every group in a bucket (schema_consolidate.R:279-286). Measured: DUNC, KOTL, LARL, SLOC, PINE, PARS each hold one `log` row, from run 20261017_004619-3f4c713b.

## /code-check round 1 (review-round1.md)

Three findings, all verified in code and fixed:
1. `kept_hosts.tsv` `groups` listed what consolidate had already taken and deleted from the host, for every keep reason but "rows left"; the recovery text then said to consolidate them, and `schema_consolidate` DELETEs the dispatcher's bucket before it copies (schema_consolidate.R:283-287). Now the report measures what is still on each kept host (`groups_measured`), and the recovery text says to consolidate only measured groups.
2. A missing `<schema>.streams` read as "nothing left" and released the host. Every dispatched cypher has it (cypher_prep.sh:334), so it is now unknown for `host_remaining`; a missing `log` stays "closed nothing".
3. Under `--keep-cyphers` a host held for cause showed only "--keep-cyphers" and the run could exit 0. The reason now carries the cause, and `KEPT_CAUSE_N` drives the exit status.

Mutants m10 (strict ignored), m11 (report not measured), m12 (cause hidden by the flag): each caught. Tests 78 pass.
