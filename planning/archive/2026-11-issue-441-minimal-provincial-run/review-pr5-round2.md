# Review: PR 5 (#441 Phase 5), round 2

## Checklist read

- code-check.md, `## Mechanisms`, prose of every H3 (table rows skipped): A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice.
- code-check-shell.md, headings for shapes check.sh or worker_prep.sh uses: `grep -c` prints the count AND exits 1 when it is zero; `for x in $(cmd | grep … || true)` hides a failing `cmd`; `a && b || c` runs `c` when any step before the `||` fails; A default `GIT_SSH_COMMAND` outranks the machine's own ssh choice; Over Tailscale SSH to a Mac, `ssh` exits 0; git pathspec excludes; `git checkout <path>` restores from the index.

## Method

Read 018c141a, the branch diff, `worker_prep.sh`, `test-worker_prep.R`, `recompute_audit.R` (whole), `hosts_kept_report()`, the driver's doctl and audit calls, every committed check.sh version (5258c1ab, 73f0220c, 018c141a), the run's `phases.tsv`, `outside_readers.tsv`, both audit logs, `verify.log`, `verify_negative.log`, #418's body. Queried m4's fwapg read-only: history minutes for the six and TABR/CHWK/LFRA; every schema's `log` for `default_minimal` builds of the six (0 rows); `zz418%` schemas (none).

## The fix's test, proved by restoring the defect

In a `git worktree` at 018c141a, `NOT_CRAN=true testthat::test_file("tests/testthat/test-worker_prep.R")`, failures counted from the returned object:

| variant of worker_prep.sh line 87-88 | new test's failures | others |
|---|---|---|
| as committed | 0 of 5 | 0 |
| B: exact prior bytes (`git show 066fd518^`, `git remote get-url origin`, no normalisation) | 3 | 0 |
| C: `git config --get` kept, ssh normalisation line deleted (the ssh-form case alone) | 1 | 0 |
| D: `git remote get-url` with the normalisation kept | 3 | 0 |

So the test catches the old line, and catches the ssh-form case on its own (C). The `Other/link.git` refusal still holds under every variant. Worktree removed; checkout untouched.

The doctl fix, run as an extracted snippet against a stub `doctl`: auth failure -> FAIL, doctl absent -> FAIL, no cypher droplet -> PASS, one `cypher-job1` -> FAIL. Droplet names (`cypher-job1`, `cypher-job2`) match `^cypher-` (up/burn logs), and check.sh asks the same doctl context the driver does.

## Enumeration (failing rows only)

README claims checked: header and post-run edit sentence, run command and run id, host table, pick rationale and minutes, downstream check, the Fraser sentence and TABR/CHWK minutes (2.41, 2.44), check table rows, consolidate/burn per host, compare 41-76 %, "no `default_minimal` build of these six groups" (0 rows on m4), try1 account, the fix's normalisation matching study_area_run.sh:496, gate record standing (no `PRETEST_LINK_PATHS` or gate-rule file changed since 24b2cbb3), BCFISHOBS, teardown on m4 (m1 not verifiable from here). check.sh checks: driver exit, verify.sql, verify negative, recompute_audit, phases per host, kept hosts (absence = none kept: `hosts_kept_report` removes the file when none), doctl, outside_readers.

| # | item | verdict | evidence |
|---|---|---|---|
| R1 | README:4-6 "after it, its `recompute_audit.R` call was given the six arguments ... and the checks were run again" as the only post-run change | **FAIL (incomplete)** | finding 1 |
| R2 | README:5 "(it had three, from a stale usage line)" | **FAIL** | finding 2 |
| C4 | check.sh:25-32 recompute_audit row with a missing consolidate_state / launched file | **FAIL toward pass** | finding 3 |

## Findings

- **[severity: fragile]** data-raw/logs/rehearsal_418/README.md:4-6 — the fix for round 1's finding 3 discloses one post-run edit of `check.sh` and the same commit makes a second one. 018c141a rewrites the doctl check (lines 46-51), after `check.txt` was produced (check.txt and the 73f0220c commit at 04:37; check.sh edited at 04:44), and the README still reads as though the audit call was the only change since the run. The committed `check.sh` is therefore not the script that produced `check.txt`, and the doctl row in `check.txt` came from the version that could not tell a failing doctl from no droplets. It cannot be re-run (`zz418_rehearsal` is dropped, so `verify.sql` and the audit have nothing to read). One clause: the doctl check was also hardened after the run (018c141a), and `check.txt` is the 73f0220c version's output; the driver's own burn rows (`burn clean`, 0 tofu resources) are the evidence for that row.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression drops a condition; the fix reproduces the defect one axis over); none otherwise (claim against evidence)
- **[severity: fragile]** data-raw/logs/rehearsal_418/README.md:5 — "(it had three, from a stale usage line)": the usage comment is not stale. `recompute_audit.R:34-36` lists all six positionals plus `[out.tsv] [fallback.txt]` across two continuation lines, unchanged since 2026-10-26 (blame: 689a726e, 73fcf579, 68aa0d0a), and the script's own `stop()` usage (line 51) lists six too. No three-argument form exists in RUNBOOK, CLAUDE.md, tests or the driver. The three-argument call came from reading only line 34; say that, or drop the parenthesis.
  - **Rule:** none (claim against evidence)
- **[severity: fragile]** data-raw/logs/rehearsal_418/check.sh:25-32 — only `deps.tsv` is guarded (`[ -s ]`). `recompute_audit.R` reads a missing `consolidate_state.tsv` as "no remote host landed" (lines 73-79) and a missing `recompute_launched.tsv` as "nothing launched" (80-84); every dependency on a remote host then gets `dep_never_landed` (152-153), which exits 0 (line 210). That is the driver's design, where it knows whether remote hosts ran; in check.sh the run had three remote hosts that must have landed, so a wrong `TS`, a renamed file or a missing copy turns the row into PASS with "7 dependency pairs: 0 ok, N whose dependency never landed". This run's record is right (both audit logs read `7 ok, 0 whose dependency never landed`), and the README quotes that line, so check.txt is not wrong; the check cannot fail on the missing input. Guard the two files with `[ -s ]` beside deps, or require the log's `ok` count to equal its pair count. Same shape, smaller: nothing ties `<TS>` to `<run_uid>`, though `phases.tsv` carries `run_uid` in column 1 to check against.
  - **Rule:** code-check.md "A guard that fails toward pass" ("What the guard reads": treat unreadable as a third state); code-check.md "Zero-length, empty, and unset are three different things"
