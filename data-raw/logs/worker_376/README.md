# worker_376 — a persistent worker beside the dispatcher

Evidence for link#376, 2026-10-25. Three runs on real hosts: the dispatcher
and one persistent worker (`worker1`, a macOS host reached over Tailscale SSH;
its identity is in the private infrastructure repo). No cloud host. Each run
modelled six groups into the scratch schema `fresh_worker376`, dropped on both
hosts afterwards; `fresh_default` was untouched. `--config=default
--buckets-exact`: the dispatcher CHIR, KHTZ, MAHD; `worker1` HORS, NECR, SEYM.
Each `run_<x>/` holds the driver's `<TS>_*` logs and its stdout (`run.log`).
Host addresses and every name of the worker are redacted in every file (the
driver's own redaction, plus one line of `run_a/run.log` and `run_b/run.log`
redacted by hand: `lnk_preflight_parity`'s summary, which the driver printed
unredacted until `7a62dc76`).

| run | run_uid | code | what it shows | exit |
|---|---|---|---|---|
| A | `20261025_141501-22012cb4` | `003f221e` | both legs model, the worker is accounted, consolidated and released (burn row skipped), the recompute runs over 6/6; both verifiers pass at `expected_n=6` | 0 |
| B | `20261025_142731-1c7447ff` | `003f221e` | `LNK_TEST_STALL_WSG=HORS --statement-timeout=2`: HORS cancelled in its `pg_sleep` on the worker and named under "statement bound hit", NECR and SEYM consolidated, the worker released, no `kept_hosts.tsv` | 1 |
| C | `20261025_144042-5c8409a5` | `7a62dc76` | the worker's loop shell and its `R` process SIGKILLed mid-HORS (14:42:12 UTC): the leg log holds no `__LNK_LEG_END__`, the leg reads exit 1, the worker is kept and listed in `kept_hosts.tsv` (`groups_measured = unsettled`, no droplet, address or burn command) | 1 |

`run_a/attempt_1/` is Run A's first launch, stopped at pre-flight before any
spend: the dispatcher's fwapg checkout held another session's untracked
planning file. The relaunch set `FWAPG_DIR` to a clean clone of the same
commit (`1a2f338e`), so the stamped `fwapg_sha` describes a clean tree at the
commit that is checked out.

## The premise, measured on the worker (2026-10-25 05:16 UTC)

`ssh <worker> 'exit 3'; echo $?` prints **0**. `( exit 3 ); echo __LNK_RC__=$?`
prints `__LNK_RC__=3`, stdout is byte-exact and stderr separate. In Run C the
leg's status was 1, `remote_leg_status`'s code for a missing end marker: ssh
reported 0 for a session whose loop had been killed, and only the marker
caught it.

## Minutes

| group | host | Run A (min) | 2026-10-23 run (min, m1) |
|---|---|---|---|
| CHIR | dispatcher | 1.3 | 2.6 |
| KHTZ | dispatcher | 2.0 | 2.9 |
| MAHD | dispatcher | 1.9 | 3.3 |
| HORS | worker | 1.9 | 2.6 |
| NECR | worker | 2.2 | 2.9 |
| SEYM | worker | 2.4 | 3.6 |

Run A's critical path 11.5 min; the worker's consolidate 1.9 min for three
groups. Both hosts ran faster than on 2026-10-23, which ran under another
session's load, so that day is no baseline for a speed ratio. Three groups each
do not settle one either: the worker's `--host-speeds` value is owed to the
next provincial run (link#377).

## The dispatcher under another session's load (Runs B and C)

In Run B, under a 2 min bound, the dispatcher's three groups were cancelled in
real statements (`frs_near_river_walk` twice, a barrier aggregate once); in
Run C, under the default 30 min bound, KHTZ and MAHD were cancelled after 30
min in `frs_near_river_walk`, a statement that took under 2 min per group in
Run A. Meanwhile another session ran heavy queries on the dispatcher's database
(`pg_stat_activity`: `CREATE TABLE scratch41.c9 …`, load average 5 to 6). It is
the 2026-10-23 OKAN shape (CLAUDE.md, "Another session's database load still
stalls single groups"), on the dispatcher, not the worker; the worker's groups
were unaffected in all three runs.

## Prep of the worker before Run A (operator-approved)

- fresh 0.39.0 → 0.42.0 at the pin, by `worker_prep.sh`'s `install-fresh`
  stage (the `--auto-install` path): `RemoteSha e9793047`, the dispatcher's.
- `snapshot_bcfp.sh --with-bcfp-views --force` on the worker, under a login
  shell (`bash -lc`: `psql`, `ogr2ogr` and `bcdata` are not on a non-interactive
  ssh PATH there), by load_all from the driver's clone: 14.5 min, after which
  the vintage gate passes on load stamps. The worker's primitives are from
  2026-10-25, the dispatcher's from 2026-10-23.
