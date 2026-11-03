# Review: PR 5 (#441 Phase 5), round 1

## Checklist read

- code-check.md, `## Mechanisms`, prose of every H3: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice.
- code-check-shell.md, headings for shapes this diff uses: git pathspec excludes; A failed `git fetch` leaves the comparison reading stale refs; A default `GIT_SSH_COMMAND` outranks the machine's own ssh choice; A variable in a sed replacement is parsed; `a && b || c` runs `c` when any step before the `||` fails; `for x in $(cmd | grep … || true)` hides a failing `cmd`; `grep -c` prints the count AND exits 1 when it is zero; Over Tailscale SSH to a Mac, `ssh` exits 0; A `git push` can land and still report failure; `git checkout <path>` restores from the index.

## Method

Read the diff, `worker_prep.sh`, `study_area_run.sh` near line 494, `test-worker_prep.R`, `recompute_audit.R`'s arguments and the driver's own call of it (`study_area_finish.sh:675`), `hosts_kept_report()`, `pretest.R`'s watched paths. Read every rehearsal and first-try log named. Queried m4's fwapg (read only): `fresh_default_history.log`, `fresh_default_minimal.log_pretest`, every schema's `log` for `config_name = 'default_minimal'`, the namespace list. Ran `pretest_check.R` at HEAD (rc 0). In scratch copies: the worker_prep tests against the script before and after 066fd518, and both scripts under an `insteadOf` rule.

## Claims (README, pretest.md, commit messages)

| # | claim | verdict | evidence |
|---|---|---|---|
| 1 | Run `20261102_112137-6a1461b2`, driver exit 0, critical path 14.1 min | ok | run.log `DRIVER_EXIT=0`, `critical path: 14.1 min` |
| 2 | Flags: config, schema, workers, cy-workspaces job1,job2, buckets-exact, recompute-jobs=8, run-label, pretest-note | ok (`--auto-install` not shown in any log) | run.log header |
| 3 | Host table (m4 SALR,MURT; m1 LSAL,LNRS; job1 MUSK; job2 LEUT) | ok | run_wsgs.tsv |
| 4 | Dependencies named per host (LSAL reads SALR; MUSK reads SALR and LSAL; LEUT/LNRS read each other) | ok | recompute_audit.tsv |
| 5 | 7 dependency pairs inside the six | ok | audit "7 dependency pairs in the run" |
| 6 | History minutes 0.7 to 1.7 per group | ok | history log: MUSK 0.70 .. MURT 1.68 |
| 7 | Downstream check passes for all but LEUT, whose one unmodelled dam is in LNRS | ok | run_job2.log: LEUT BLOCKED, Kenney Dam in LNRS |
| 8 | "No Fraser main-stem group is in it: the smallest takes 6.6 min" | **FAIL** | see finding 1 |
| 9 | Check table: exit, verify (expected_n=6), negative, audit (7 pairs, 0 early), phases on four hosts, no host kept/none up, outside_readers written and empty | ok | check.txt, verify.log, verify_negative.log, recompute_audit.log, phases.tsv, outside_readers.tsv header only, no kept_hosts.tsv |
| 10 | Each cloud host consolidated and burned when its own leg ended | ok | phases: job2 leg ended 11:33:13, consolidated and burned by 11:34:25; job1 leg ended 11:33:37, consolidated and burned by 11:35:22 |
| 11 | Compare 41 to 76 % on the three groups with a modelled species | ok | 41.3, 74.8, 76.4 |
| 12 | "no `default_minimal` build exists" | **FAIL (scope)** | see finding 2 |
| 13 | `check.sh` committed before the run | **incomplete** | see finding 3 |
| 14 | First try `20261102_110959-50380beb` stopped at worker prep on the URL compare; both cloud hosts burned; nothing modelled | ok | try1 run.log, prep_worker1.log, phases (no model row) |
| 15 | worker_prep.sh outside the gate's watched paths, so the record stands | ok | `PRETEST_LINK_PATHS` (pretest.R:109) excludes it; `pretest_check.R` at HEAD: rc 0 |
| 16 | BCFISHOBS at dd9a5e5d (that checkout has uncommitted files) | ok | run.log bcfishobs_sha dd9a5e5d2ddc; checkout HEAD dd9a5e5d, modified + untracked files |
| 17 | Teardown: zz418_rehearsal dropped on m4, dump removed | ok | no `zz418%` schema; no `/tmp/zz418*` |
| 17b | Teardown on m1, worker clone clean | not verified (no ssh to m1) | |
| 18 | Gate: link `1d00c04c..24b2cbb3`, fresh v0.42.0..v0.52.0 (fresh 245c8d8 = v0.52.0) | ok | range.txt, log_pretest row, fresh tag |
| 19 | 69 changed files; 4 unexercised | ok | counted |
| 20 | Bounds 3 x minutes, floor 5; statement bound ceil | ok | recomputed every row |
| 21 | Estimated 72.4 min; eleven picks each within bound, gate PASS | ok | sum 72.44; every "this run" below bound; log_pretest verdict `pass`, 11 groups |
| 22 | Fix commit: `get-url` applies insteadOf, so the m1 clone could never match | ok | try1 prep log shows `git@github.com:` form; reproduced with an insteadOf rule in scratch (old rc 1, new rc 0) |

## Findings

- **[severity: bug]** data-raw/logs/rehearsal_418/README.md:23 — "No Fraser main-stem group is in it: the smallest takes 6.6 min" is wrong. 14 groups touch the Fraser main stem (`wscode_ltree = '100'`), and in `fresh_default_history.log` their newest minutes run TABR 2.41, CHWK 2.44, MFRA 2.80, TWAC 2.91 ... LFRA 6.61 ... SETN 16.27. 6.6 is LFRA alone. Under the line rule every Fraser group reads every group touching line 100, so TABR or CHWK is as much "the group others read" as LFRA, at 2.4 min, inside the 0.7 to 2.4 min budget the other picks sit in. The stated reason for leaving the Fraser out does not hold; either the sentence names LFRA specifically (and why it alone mattered) or the rehearsal's choice needs another reason.
  - **Rule:** none (claim against evidence)
- **[severity: fragile]** data-raw/logs/rehearsal_418/README.md:40 — "no `default_minimal` build exists" is false as written: m4 holds `default_minimal` builds of BULK, COTR, MORK, SETN in `zz415_minimal` (#415 proof) and of the gate's eleven picks in `fresh_pretest_default_minimal`. None is of the six rehearsal groups, which is what the sentence needs; say "no `default_minimal` build of these six groups exists".
  - **Rule:** none (claim against evidence)
- **[severity: fragile]** data-raw/logs/rehearsal_418/README.md:4 — says `check.sh` was committed before the run, but the copy that produced `check.txt` was edited after it (73f0220c changes the `recompute_audit.R` call from 3 to 6 arguments; at 3 arguments the script stops with usage, exit 2, so the committed-before version could only report FAIL on that row). The README and the commit message are silent on the edit. The edit fixes an argument list, not a threshold, so no result was fitted, but a reader trusting "committed before the run" is told something the history does not show. One sentence saying it was fixed after the run and re-run.
  - **Rule:** none (claim against evidence)
- **[severity: fragile]** data-raw/logs/rehearsal_418/check.sh:46 — `left=$(doctl compute droplet list ... | grep -c '^cypher-' || true)`: if `doctl` fails (token expired, API down, not on PATH), `grep -c` reads nothing and prints `0`, `|| true` absorbs the status, and the row reports `cloud hosts burned PASS`. The error path and the "none left" path are the same value. On this run the driver's own burn rows ("0 tofu resources", `burn clean`) confirm the result, so check.txt is not wrong; the check itself cannot fail on an unreadable answer. Capture doctl's output and status first, FAIL when it errors, then count.
  - **Rule:** code-check.md "A guard that fails toward pass"; code-check-shell.md "`for x in $(cmd | grep … || true)` hides a failing `cmd`"
- **[severity: fragile]** data-raw/worker_prep.sh:87-88 / tests/testthat/test-worker_prep.R — the fix has no test. Run against the test file in a scratch copy, the script before 066fd518 and after it both pass all 20 expectations, so reverting the fix leaves the suite green. The case is cheap to reach in the existing harness: set `GIT_CONFIG_GLOBAL` to a file with `url."<world>/origin".insteadOf = https://github.com/NewGraphEnvironment/link.git` and pass that https URL as `WORKER_PREP_ORIGIN`; measured in scratch, the old script exits 1 ("origin is '<path>/origin', not the run's ..."), the new one 0. Add that case, plus a `git@github.com:` configured URL normalised to match, beside the existing different-repo refusal (line 77), which still holds.
  - **Rule:** code-check.md "Restore the bug and prove the guard fires"

## worker_prep.sh change, URL forms

- `git clone "$ORIGIN"` stores the URL as given in `remote.origin.url`, with insteadOf applied only when fetching (measured), so a fresh clone always matches.
- An existing clone configured as `git@github.com:<path>` now matches `https://github.com/<path>`; the path is kept, so a clone of another repository still differs and is refused (measured with `git@github.com:Other/link.git`). The existing test at line 77 (a different local origin) still refuses.
- `ssh://git@github.com/...` and a `.git` suffix mismatch are not normalised on either side; both fail closed (a refusal), not open. Not a finding.
- The driver still reads its origin with `git remote get-url` (study_area_run.sh:494), which applies the dispatcher's own insteadOf rules, while the worker now reads the configured URL. They agree for the `git@github.com:` rewrite (both normalise it); a dispatcher rule to any other form (e.g. `ssh://`) would send that form to workers. Pre-existing, not introduced here; noted, not a finding.
