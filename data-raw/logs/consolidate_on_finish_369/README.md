# consolidate_on_finish_369 — each cloud host consolidated and burned when its own leg ends

Evidence for link#369, 2026-10-24. Three small runs on real droplets, from a
worktree on the pushed branch `369-run`, into scratch schemas (`fresh_default`
untouched). Each `run_<X>/` holds the driver's `<TS>_*` logs, the launch script
exactly as launched, its stdout (`run_<X>.log`) and the start stamp. Host
addresses are redacted in every file.

| run | run_uid | code | schema | hosts and groups | what it shows |
|---|---|---|---|---|---|
| A | `20261024_072631-73621c49` | `8d0a1822` | `fresh_smoke369` | dispatcher 12; job1 NBNK; job2 MBNK, KEEC, KAKC, PITR, VICT | each cypher burned while the dispatcher still modelled |
| B | `20261024_075836-321a58e2` | `a414d72b` | `fresh_smoke369b` | dispatcher LNRS; job1 MILL, LPET; a future-dated MILL log row seeded | a refused host is kept and listed with its burn command |
| C | `20261024_081550-2f4228dd` | `6d783202` | `fresh_smoke369` (over Run A's builds) | as Run A | Run A at the final code; both verifiers pass |

## Run A and Run C: the timing

| | job1 burned | job2 burned | dispatcher model ended | consolidate tail |
|---|---|---|---|---|
| A | 07:38:45 UTC | 07:44:59 | 07:51:30 | 0.0 min |
| C | 08:29:16 | 08:35:43 | 09:03:43 | 0.0 min |

Each cypher was consolidated within seconds of its leg ending (0.5 min for one
group, 0.9 min for five) and burned about half a minute later. Both cyphers
were gone 6 to 34 minutes before the dispatcher leg ended. `<TS>_consolidate_state.tsv`
has one `ok` row per group, with `state_utc` inside the dispatcher's model window,
and no run wrote `<TS>_kept_hosts.tsv`. Run C's `verify.log` reads
`PASS: run 20261024_081550-2f4228dd -- 18 WSG(s), all modelled, recomputed,
settled, segmented and provenanced`, and `verify_extra.log` ran clean.

**Overlap cost** (`run_A/run_A_overlap_minutes.tsv`): the four dispatcher groups
that modelled during a copy ran 1.02–1.37× their 2026-10-23 minutes (median
1.11); the eight that did not ran 0.68–1.73× (median 1.19). At copies of one
and five groups no slowdown is visible. The provincial-scale measurement is
owed to the next `default` run.

**Run C's dispatcher leg took 37.7 min against Run A's 15.8**, all of it in one
group: EUCH took 21.9 min against 1.09 (`run_C/dispatcher_minutes_vs_run_A.tsv`).
It started at 08:36:19, after both copies and burns had finished, and a
four-worker observation query from another session on the same database started
at 08:37:48 beside a long-running tuning job. Not caused by #369; the same shape
as the 2026-10-23 OKAN stall (another session loading the database).

## What the runs found

- **Run A's `study_area_verify.sql` failed** on provenance only: the 12
  dispatcher rows had `link_sha` NULL. `.lnk_read_git_head()` read a worktree's
  branch ref beside its private `HEAD` instead of in the common dir or
  `packed-refs`. Fixed (with relative `gitdir:` pointers, found in review);
  Run B's dispatcher row carries `link_sha a414d72b`, and Run C passes.
- **The dispatcher's accounting claimed the cyphers' groups.** Accounted after
  the copies, its log holds their rows. Fixed: groups a consolidate was attempted
  for are left out unless the dispatcher's own bucket has them.
- **Run B's compare failed for a reason outside #369**: LNRS models only RB,
  which the bcfishpass reference does not carry, so a run whose only compared
  group is LNRS has nothing to compare.
- **The launcher's stdout is outside the driver's redaction**, which covers
  `<TS>_*` only. The copies here were redacted by hand.

## Run B: the refused host

`run_B/20261024_075836_kept_hosts.tsv` names job1 with reason `consolidate failed
at stage dest_log_newer; finished groups left on the host`, groups `LPET,MILL`,
`groups_measured` `yes`, and the burn command. The state record reads
`failed:dest_log_newer` for both; coverage classed them `not_consolidated`; LNRS
was still recomputed; the run ended INCOMPLETE. The listed burn command was then
run by hand (`run_B/run_B_manual_burn.log`), and doctl showed no job droplet.
