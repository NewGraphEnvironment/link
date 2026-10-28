# Review round 3: #406 `--jobs` for habitat_variants_build.R (branch diff vs 88923b52, data-raw/ only, through 288e1217)

## Checklist read

All four indexes read; each heading's index line checked against the diff.

- **code-check.md**: full prose of all 14 H3s under `## Mechanisms`, table rows skipped. The ones
  applied hardest: "A guard that fails toward pass" (the reserved-value channel paragraph),
  "A guard's scope, escape hatches, and remedies" (run the remedy for every input the clause can
  receive), "Zero-length, empty, and unset", "A wrapper's exit is not the work", "One fact
  derived twice". The 23 stand-alone / Security / Spreadsheets headings checked from their
  index lines only.
- **code-check-r.md**: read in full: "`on.exit()` at a script's top level never fires";
  "Postgres row order is never fixed…"; "`tryCatch()` nests its handlers"; "Forked
  `parallel::mclapply()` workers segfault…"; "`c()` dispatches on its first argument";
  "Rscript reads a script as it runs"; "`[[` on a named ATOMIC vector with an absent key".
  The rest checked from index lines.
- **code-check-shell.md**: index lines checked against run.sh (`set -euo pipefail`, `cd` inside
  `( … && … )`, no `grep -c`, no ssh, no trap). None read in full this round.
- **code-check-spatial.md**: read in full: "GDAL reserves 3,276 MB per process…, and PSOCK
  workers outlive their master". The rest checked from index lines.

## Mechanism

R1 and R2 are one assumption: **the end of the build's process is the end of a group's work, so
one handle (the master, then the worker's R pid) identifies and stops it**. A group's pass is
really held by three processes (master, worker R, worker's backend), and the master can end
while the other two keep writing. R1's duplicate group and R2's NA digest are the second
assumption: **a sentinel on a shared channel carries a decision** (one name means one task;
NA means "no check"). The two enumerations below walk where each reaches.

## (a) What one group's pass creates or holds

Measured in a scratch dir (no database): a 3-worker PSOCK cluster, `outfile = ""`, worker 1
`pskill()`s itself at 1 s, workers 2 and 3 sleep 15 s then write a file, all inside
`tryCatch(clusterApplyLB(...), finally = stopCluster(cl))` as the build has it.
`clusterApplyLB` raised `error reading from connection` at 1 s, `stopCluster()` returned without
error, the master exited at about 6 s, and workers 2 and 3 wrote their files at 15 s, after the
master had gone.

| resource | outlives a killed master | outlives a killed worker | header remedy covers it |
|---|---|---|---|
| worker R process | yes: finishes its current group (every remaining step, persist included), then exits when it cannot send | n/a (it is the one killed); the **other** workers outlive the master, which exits at once (below) | "kill those R pids": yes for a killed build; **not stated for the worker-death exit** |
| PSOCK socket | no (closed with the master) | no | n/a |
| worker's backend, its statement | yes, until it next writes to the client | yes, same | `pg_terminate_backend()` / check `pg_stat_activity`: yes for a killed build only |
| backend's open transaction (`copy_access`'s `dbWithTransaction`) | rolled back on terminate | same | yes |
| autocommit statements already run (discharge join, classify, connect, persist DELETE/INSERT, ANALYZE, gate) | committed | committed | "re-run the variant before scoring it": yes for a killed build |
| session temp tables (gate overlay, fresh's `pg_temp` work tables) | until the backend ends | same | yes (terminate drops them); per-worker sessions, so no cross-group name collision |
| working-schema tables (`working_<prefix><wsg>.streams_habitat`, `streams_breaks`, `streams.mad_m3s`) | yes, left at the variant's classification | same | yes: the next run's base pass re-classifies and re-checks the digest |
| persist-schema rows of the variant, keyed by group | yes, partial | yes, partial | "re-run the variant": yes for a killed build |
| built.csv / variant_timing.csv rows | none of the variant's groups recorded (persist_init row only); older rows for those groups remain | **none recorded**, including groups that already returned clean | header says the opposite for a failing group ("recorded first") |
| log lines | orphans keep writing into the inherited build.log fd; a relaunch with `>` truncates the same inode under them | same | yes, provided the orphans are killed first |

## (b) Sentinels the new code decides on

| sentinel | decides | can a real input take it? |
|---|---|---|
| `want` NA | no base-digest check | no longer for the base: an NA base digest is refused at lookup (R2 fix). Non-base: always NA, as intended |
| `sp` NULL | base pass: all species, no persist/copy/gate | only the base. `sp_v` for a variant is length 1 and never NA (write_bundle stops on a species not in the thresholds) |
| `cl` NULL | serial loop | only `jobs == 1`; consistent with `jobs > 1L` |
| `out$error` NA | the group passed | no: `conditionMessage()` of a raised error is a string (`stop("")` gives `""`, which reads as a failure) |
| `out$finished` NULL / `out$tm` `c()` | unset until success | read only on success; `list(finished = NULL)` keeps the element, so `$` does not partial-match |
| `failed` `character(0)` | no stop | the all-pass case, correct |
| `n_seg` NA | sorts last | only when the base `streams` table is gone, and then every group fails its own existence check |
| `wsgs_v` empty | zero tasks, a `pass_wall` row, "0 groups" | yes (a species with no role in `--wsgs`); serial behaved the same before the change |
| `jobs` default `1L` in `record_timing()` | base-run rows | correct by design (the base is serial) |
| `old$jobs <- "1"` | pre-#406 timing rows | correct |
| analyze.R: a "done in" line present | which groups' step sums are checked | see finding 2 |

## Findings

- **[severity: fragile]** data-raw/habitat_variants_build.R:66-79 (header) with :1060-1063 and
  :1145-1149. The orphan remedy and the claim "A group that fails stops the build after the
  others return; every group whose checks passed is recorded first" cover a group whose R code
  raises, which `variant_pass()` catches. They do not cover a **worker that dies** (OOM, a
  segfault in a driver, or an operator killing one worker, which is the header's own remedy
  applied a step early). Then `clusterApplyLB()` raises `error reading from connection` at
  once, the `finally` stops the cluster, and the master exits non-zero (measured above: master
  gone at about 6 s, the other workers still writing at 15 s). So: (1) nothing is recorded,
  not even groups that had already returned clean; (2) the error names no group and no worker;
  (3) every other worker is still running its group, with its backend, after the build has
  exited. The header gives the "kill these R pids and terminate these backends before
  relaunching" step only for "a build killed mid-variant", so an operator who sees a build
  that *exited* with an error relaunches straight into the concurrent-writer case R1 and R2
  closed. Fix (wording is enough, given the accepted manual-remedy design): say the orphan
  remedy applies to any variants build that ends other than by finishing or by the "variant
  … failed in …" stop, including an `error reading from connection`; optionally wrap the
  `clusterApplyLB()` call so such an error re-prints the `workers <R pid>:<backend pid>` line
  and the remedy before it propagates.

- **[severity: fragile]** data-raw/logs/variants_parallel_406/analyze.R:38-41. The step-sum
  check `merge(done, s)` with `nrow(chk) != nrow(done)` checks only the groups that have a
  "done in" line. A group in `variant_timing.csv` whose line is missing from `build.log` (a
  lost or garbled worker line, or a log not from the run that wrote the timing rows) is never
  checked, and the script passes. The header says it stops "if any pass's seven in_total steps
  do not sum, per group". That is a guard narrower than its claim, which fails toward pass.
  Fix: also require `nrow(done) == nrow(s)` (each pass's groups in both), or
  `setequal(paste(done$variant, done$watershed_group_code), paste(s$variant, s$watershed_group_code))`.

Nothing else fell out of the enumerations. Everything else checked out: the serial path's
equivalence; the dispatch and the order results are recorded in; the per-worker connections;
the pid logging (a worker opens no second connection: no `dbConnect` / `frs_db_conn` in the
classify, connect, persist or gate code paths outside roxygen examples); the gate overlay temp
table, dropped `on.exit`; digest.R / compare.R (key coverage, the perturbation check, the
negative control); and run.sh.
