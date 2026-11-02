# rehearsal_418 — the real driver on six groups across four hosts, before the minimal run (#418, #441)

**2026-11-02, by hand.** #418's gated script (picker, `log_rehearsal`, launch refusal, seeded failures) is still owed;
this is its check list run once, at the code #441's run will use. `check.sh` was committed before the run and edited three times after it.
Its `recompute_audit.R` call was given the six arguments the script takes (it had three, from reading only the first
line of the script's usage), and the checks were run again (`check.txt`). Then, in review, the droplet check was made
to fail when `doctl` cannot list droplets; the audit row was made to fail on any of its four inputs missing or empty,
and on a summary with no pairs or a pair not ok; an unreadable kept-hosts file fails; a row checks that the logs'
timestamp names the run's `run_uid`; and the script writes its logs to a temporary directory unless `CHECK_OUT` names
one. `check.txt` comes from the version before those review edits; the driver's own burn rows (`run.log`) show both
cloud hosts burned. No threshold changed.

## The run

`study_area_run.sh --config=default_minimal --schema=zz418_rehearsal --workers=m1 --cy-workspaces=job1,job2
--buckets-exact --recompute-jobs=8 --auto-install --run-label=rehearsal-418`, with a `--pretest-note` naming the gate's
pass (`../pretest/20261102_102658_default_minimal/`, `fresh_default_minimal.log_pretest`, link `24b2cbb3`), from branch
`418-gate-rehearsal`. Run `20261102_112137-6a1461b2`: driver exit 0, critical path 14.1 min (`run.log`; the driver's own
files are `../study_area_run/20261102_112137_*`).

| host | groups | why |
|---|---|---|
| m4 (dispatcher) | SALR, MURT | SALR is the group LSAL and MUSK read; MURT has only paused species present |
| m1 (worker) | LSAL, LNRS | LSAL reads SALR on another host; LNRS holds the dam LEUT's downstream check needs |
| job1 | MUSK | reads SALR and LSAL, both on other hosts |
| job2 | LEUT | reads LNRS on another host, and LNRS reads it back |

Picked from `recompute_deps.R`'s line rule over FWA (7 dependency pairs inside the six) and the 241-group history's
minutes (each group 0.7 to 1.7 min there). `lnk_wsg_downstream_check()` passed for each against an empty schema except
LEUT, whose one unmodelled dam is in LNRS, which is in the run. **No Fraser main-stem group is in it, which #418's rule asks for.** TABR or CHWK (2.4 min in the history) would
have served; SALR stood in as the group others read, which is weaker: every Fraser group reads every group on the main
stem.

## Checks (`check.sh`, `check.txt`)

| check | result |
|---|---|
| driver exit | PASS (0) |
| `study_area_verify.sql`, `expected_n=6` | PASS (`verify.log`) |
| `study_area_verify_negative.sh` | PASS (`verify_negative.log`) |
| `recompute_audit.R` | PASS: 7 dependency pairs, 0 early (`recompute_audit.log`) |
| `phases.tsv` model rows on dispatcher, worker1, job1, job2 | PASS |
| no host kept; no cloud host left up | PASS |
| `outside_readers.tsv` written | PASS (empty: the schema held only the run) |

Each cloud host was consolidated and burned when its own leg ended. The driver's compare against bcfishpass reads 41 to
76 % on the three groups with a modelled species: a minimal network against the full reference, not a check. Outputs
were not compared with a last build: no `default_minimal` build of these six groups exists, and a `default` build differs by design.

## The first try (`try1_worker_url/`)

Run `20261102_110959-50380beb` stopped at the worker's prep: `worker_prep.sh` compared `git remote get-url origin`
with the run's https origin, and m1 rewrites `https://github.com/` to ssh (`url.<base>.insteadOf`), so the clone could
never match. Both cloud hosts were burned by the driver; nothing was modelled. The fix (this branch) reads
`remote.origin.url` and normalizes the ssh form as the driver does. `worker_prep.sh` is outside the gate's watched
paths, so the gate's record stands.

## Also

- `BCFISHOBS_DIR` pointed at a clean clone of `~/Projects/repo/bcfishobs` at its HEAD (`dd9a5e5d`), because that
  checkout holds uncommitted files that are not this work's; the stamped `bcfishobs_sha` is that HEAD.
- Teardown: `zz418_rehearsal` dropped on m4 and m1, the pre-run dump removed, the worker clone clean.
