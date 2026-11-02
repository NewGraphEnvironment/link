# Review: PR 5 (#441 Phase 5), round 3 (enumeration)

## Checklist read

- code-check.md, `## Mechanisms`, prose of every H3 (table rows skipped): A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice.
- code-check-shell.md, headings for shapes check.sh / worker_prep.sh use: `grep -c` prints the count AND exits 1 when it is zero; `a && b || c` runs `c` when any step before the `||` fails; `for x in $(cmd | grep … || true)` hides a failing `cmd`; awk `==` compares version strings as numbers; A failed `cd` lets every later command run in the directory you were already in; Paths; `if ! cmd; then rc=$?` captures the negation.

## Method

Read 428e0b7c, the branch diff, README.md, check.sh at every commit (5258c1ab, 73f0220c, 018c141a, 428e0b7c), check.txt, verify.log, verify_negative.log, recompute_audit.log, run.log, try1_worker_url/, the driver's committed `study_area_run/20261102_112137_*` files (44 tracked), `recompute_audit.R`, `hosts_kept_report()`, `pretest.R`'s `PRETEST_LINK_PATHS`, the default bundle's presence overlay and `species_modelled.csv`. m4 fwapg read-only: `fresh_default_history.log` minutes for the six and TABR/CHWK; `log` of every schema on m4 for the six (no `default_minimal` row); `zz418%` schemas (0).

Drove `recompute_audit.R` (real copy) against stub inputs with schema `fresh_default` (read-only; it holds no rows of this run), and drove `check.sh` (real copy) in a temp tree under the scratchpad with stubs for `study_area_verify.sql` (`\echo === verify: OK ===`), `study_area_verify_negative.sh` (exit 0) and `doctl` (on PATH), and copies of the run's six driver files. Nothing in the repo or on the database was written. `NOT_CRAN=true testthat::test_file("tests/testthat/test-worker_prep.R")`: 25 expectations, 0 failed, 0 errors.

### Stub results (audit called directly)

| inputs | audit exit | audit line |
|---|---|---|
| real files, schema without this run's rows | 1 | 7 pairs, 2 EARLY |
| deps.tsv header only | **0** | 0 dependency pairs, 0 EARLY |
| run_wsgs.tsv header only | **0** | 0 dependency pairs, 0 EARLY |
| consolidate_state.tsv header only | 1 | 7 EARLY |

### check.sh scenarios (non-PASS rows printed)

| scenario | result |
|---|---|
| deps.tsv header only | **REHEARSAL: PASS** (audit row PASS, "0 dependency pairs") |
| run_wsgs.tsv header only | **REHEARSAL: PASS** |
| phases.tsv header only | run_uid row PASS (vacuous), every model row FAIL -> FAIL |
| wrong run_uid (try1's) | run_uid row FAIL, audit FAIL |
| doctl exits 1 | burned row FAIL |
| doctl lists `cypher-job1` | burned row FAIL |
| outside_readers.tsv missing | FAIL |
| kept_hosts.tsv with one host | FAIL |
| consolidate_state.tsv missing | audit row FAIL "missing or empty" |
| phases.tsv unreadable | run_uid and model rows FAIL |
| kept_hosts.tsv unreadable (mode 000) | **no host kept PASS** (`[: : integer expected`) |
| `OUT/verify.log` pre-seeded `SENTINEL` | overwritten with this invocation's output |

## Enumeration (failing rows only)

README claims checked, all hold except the rows below: post-run edit disclosure, the three-argument origin (usage line 34 lists three), check.txt from the pre-review version (12 lines, no run_uid row), burn rows in run.log (job1, job2 `burn clean`), no threshold changed (`-gt 1`, `-ge 1`, `= 0` unchanged since 5258c1ab), the run command (run.log header: default_minimal, zz418_rehearsal, worker1, job1 job2, exact buckets, -j 8, rehearsal-418, override note naming 24b2cbb3), run id, driver exit 0 (`DRIVER_EXIT=0`), critical path 14.1 min, host table (run_wsgs.tsv and consolidate_state.tsv), the reads in the "why" column (the seven pairs in recompute_audit.tsv), MURT only RB (paused), LNRS holding Kenney Dam for LEUT (run_job2.log), 7 pairs, 0.70 to 1.68 min, TABR 2.41 / CHWK 2.44, no Fraser main-stem group, audit line, outside_readers header-only, consolidate-and-burn per leg, compare 41.3 / 74.8 / 76.4 %, no `default_minimal` build of the six on m4 (gate picks none of them), try1 (FATAL text, both burned, nothing modelled), the fix matching study_area_run.sh:496, worker_prep.sh outside `PRETEST_LINK_PATHS`, bcfishobs_sha dd9a5e5d, m4 teardown. m1 teardown and the m1 insteadOf rule not verifiable from here.

| # | item | verdict | evidence |
|---|---|---|---|
| R1 | README:4 "edited twice after it" | **FAIL** | three post-run commits change check.sh: 73f0220c (audit args), 018c141a (doctl), 428e0b7c (inputs, run_uid) |
| R2 | README:7-8 "the audit's other two inputs and the run's `run_uid` were made checks of their own" | **FAIL** | 428e0b7c newly guards three inputs (run_wsgs, consolidate_state, launched), and they are folded into the `recompute_audit.R` row, not rows of their own; only the run_uid is its own row |
| C1 | check.sh:33-41 audit row, deps.tsv or run_wsgs.tsv header only | **FAIL toward pass** | finding 1 |
| C2 | check.sh:6 "Reads only" | **FAIL** | finding 2 |
| C3 | check.sh:56-57 kept_hosts.tsv unreadable | **FAIL toward pass** | finding 3 |

worker_prep.sh changed lines (86-88) and the new test: no failing row. `git config --get` on a multi-valued or absent url yields "" and refuses (fails closed); a clone always stores the URL it was given, so the configured value is the pre-rewrite one.

## Findings

- **[severity: fragile]** data-raw/logs/rehearsal_418/check.sh:35-41 — round 2's fix guards the audit's inputs with `[ -s ]`, which is true for a file holding only its header. `recompute_deps.tsv` and `run_wsgs.tsv` both carry headers, and with either one header-only `recompute_audit.R` finds 0 dependency pairs and exits 0 (measured: "6 recomputed groups, 0 dependency pairs in the run ... 0 EARLY", rc 0), so `check.sh` prints `recompute_audit.R PASS` and `REHEARSAL: PASS` (driven in a temp tree with the run's other files). `-s` is a stand-in for "holds rows". The record is right (the real log reads 7 pairs, 7 ok), but the check cannot fail on that input. Assert on the audit's own line instead: pair count equal to the pairs expected inside the run (or at least > 0) and `ok` equal to the pair count; or require more than one line in each headed input.
  - **Rule:** code-check.md "Zero-length, empty, and unset are three different things"; code-check.md "A guard that fails toward pass" (a loop over a computed list, where an empty list runs zero times and exits 0)
- **[severity: fragile]** data-raw/logs/rehearsal_418/check.sh:6 — the header says "Reads only", but lines 18, 22 and 40 write `verify.log`, `verify_negative.log` and `recompute_audit.log` into `data-raw/logs/rehearsal_418/`, the files the README cites as the record, and `study_area_verify_negative.sh` creates and drops `zz_lnk_verify_negative` on the database. With `zz418_rehearsal` dropped, re-running `check.sh` (for instance to see its new rows) overwrites the committed evidence with failure output (a pre-seeded `verify.log` was overwritten in the temp tree). Correct the comment, and write the logs to an out directory given as an argument (or refuse when they exist).
  - **Rule:** code-check.md "A guard that fails toward pass" ("Where the guard sits": a comment stating a property is an unexecuted claim)
- **[severity: fragile]** data-raw/logs/rehearsal_418/check.sh:57 — an unreadable `kept_hosts.tsv` passes: `[ -s ]` is true, `$(wc -l < "$kept")` fails to empty, `[ "" -gt 1 ]` errors (exit 2), and the `else` branch says `no host kept PASS` (measured with mode 000). Unlikely for a file the driver writes, but it is the unreadable state the round asks about. Read the count first and branch on the read's status.
  - **Rule:** code-check.md "A guard that fails toward pass" ("What the guard reads": treat unreadable as a third state)
- **[severity: fragile]** data-raw/logs/rehearsal_418/README.md:4,7-8 — the disclosure added for round 2 miscounts: `check.sh` was changed in three commits after the run (73f0220c, 018c141a, 428e0b7c), not "twice"; and 428e0b7c guards three more audit inputs (`run_wsgs.tsv` as well as the consolidate state and launch files), all inside the existing `recompute_audit.R` row, so "the audit's other two inputs ... were made checks of their own" is wrong on both the count and the shape. Only the run_uid became a row of its own.
  - **Rule:** none (claim against evidence)
