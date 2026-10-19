# Code-check round 3 — branch 348 (git diff c902ea97...HEAD)

Reviewer: subagent, 2026-10-18. Read the branch diff, study_area_finish.sh,
study_area_hosts.sh and the driver's arg parsing, discharge gate, recompute-only
branch, dispatch legs, accounting, consolidate, release and tail, both RUNBOOK
sections, rounds 1-2 and the plan review.

Verified by running:
- `test-study_area_finish.R` (NOT_CRAN=true): 12 tests, 0 failed, 0 error, 0 skipped.
  Working tree clean before and after (nothing was edited in the repo).
- Two direct calls of `hosts_kept_report` followed by `run_finish_report` (bash 5,
  `set -euo pipefail`, both libs sourced, `host_split` stubbed to the measured state, no
  DB). Scripts: `<scratchpad>/r3/unsettled.sh`, `<scratchpad>/r3/unmeasured.sh`. Output is
  quoted in finding 1.

## Mechanism

The recovery advice is computed from a set **after the qualifier that makes the set mean
something has been dropped**, or from a set taken at another time or in another process.
`hosts_kept_report` decides what `CY_UNCONS` / `CY_PARTIAL` / `CY_DOUBT` mean through its
local `measured` (yes / unsettled / no), and it never publishes that state. So any consumer
of the three maps reads "finished", "failed" and "unknown" where the producer meant "finished
when probed, may change", "may still be building", or "every candidate, not measured".
Round 1 (whole set → re-model), round 2 (the bucket used as a proxy for the measured sets)
and finding 1 below (measured sets used without their `measured` state) are three steps
down the same slope. Findings 2-4 are the same shape with other sources: an exit flag from
the accounting (database-only finished set) read where coverage is the truth, a recompute
expected set from the dispatcher log printed where the run's own set is in scope, and the
pool's exported environment absent from a printed command.

The way to end it is to have each printed instruction read the same object as the instruction
it must agree with: publish `CY_MEASURED[$ws]` from `hosts_kept_report`, and branch the
report on it.

## Findings

- **[severity: bug]** data-raw/study_area_finish.sh:398-424 (with study_area_hosts.sh:491-519,
  where `measured` stays local). The consolidate / check / re-model split ignores whether
  the kept host was measured, and the kept-host block printed just above it (and
  `hosts_kept_report`, and RUNBOOK §8d) says to act on `groups` **only where
  `groups_measured = yes`**. Two reproduced cases:
  - **measured=no** (round 1's scenario: the database did not answer at accounting and
    still does not at report time). `hosts_kept_report` sets `CY_UNCONS` to the whole
    candidate set, so every missing group in that bucket is printed as `consolidate these
    from the host ..., do NOT re-model them: AAAA,BBBB,CCCC,DDDD`, beside `host did not
    answer; candidates (NOT measured)` and `where it says no, find out what is left first`.
    The candidate set includes the host's failed builds. For one that is also `COV_STALE`
    (DDDD: an earlier run's valid rows on the dispatcher), consolidating the host's partial
    build deletes those rows and copies the partial ones: `dest_log_newer` does not refuse
    it, because the source's newest log row (this run's, open) is newer than the
    dispatcher's (the earlier run's). That is a loss of valid data, reached by following
    the line of the report that names the group.
  - **measured=unsettled** (the documented case for `host_release`: the ssh session dropped,
    exit 255, while the remote loop kept building). `CY_PARTIAL` is "NOT finished when
    probed (may still be building)" and the kept block says "Re-measure once nothing runs
    there", but the report puts it under `Re-model each of these under this run_uid: CCCC,DDDD`.
    DDDD, not yet started on the host, gets the same advice. If the operator re-models them
    and the host then finishes them, consolidating that host's `groups` is refused whole
    (`dest_log_newer`: the dispatcher's re-model is newer), which also blocks the host's
    other finished groups. The finished-when-probed groups are printed as "consolidate these"
    even though the same report says only where `groups_measured = yes`.
  The RUNBOOK §"A missing group costs only itself" sentence ("or that the host could not be
  measured for ... consolidate it from the host, do not re-model it") contradicts §8d ("only
  where `groups_measured` is `yes`") the same way.
  Fix: have `hosts_kept_report` record `CY_MEASURED[$ws]` (declared with the other maps). In
  the report, for a held host whose state is not `yes`, list every missing group of its
  check set (bucket ∪ finished ∪ done ∪ uncons) as "on a kept host that is not measured or
  not settled: re-measure there first; neither consolidate nor re-model yet", and apply the
  current consolidate / doubt / re-model split only to hosts with `yes`. Align the RUNBOOK
  sentence.

- **[severity: fragile]** data-raw/study_area_finish.sh:429-433, the `RUN_INCOMPLETE` branch
  with an empty `COV_MISSING`. `RUN_INCOMPLETE` starts from `complete_fail`, which
  `host_account` sets from the database-only finished set, while coverage adds the `done`
  markers and the consolidated buckets. Scenario: on a cypher the soft `date_end` UPDATE
  fails for group G (`.lnk_log_run_finish`). Accounting marks G missing (complete_fail=1),
  the `done` marker puts G in `CY_BUCKET_DONE`, G is consolidated, and coverage counts it
  (`N/N run WSGs have rows from a build this run finished`). The run then exits 1 with "only
  the WSGs it finished were consolidated ... Re-run the missing ones", and names none: there
  are none, and the line contradicts the coverage line printed above it. Also reachable when
  buckets overlap (`DUP`) and the other host finished the group. It fails closed, but the
  instruction is wrong, and re-running is the wrong recovery (G is complete; only its log
  row is open, which `--recompute-only` cannot rescue either, as documented). Fix: when
  `COV_MISSING` is empty, say that coverage found every group finished and that the host's
  accounting disagreed (see its `note:` lines: done in the log, not closed in the database),
  instead of telling the operator to re-run.

- **[severity: fragile]** data-raw/study_area_finish.sh:381-382 (and study_area_hosts.sh:537-538,
  study_area_run.sh:1465-1466). The kept-host block's `--recompute-only` command has no
  `--wsgs=`, so its expected set is the dispatcher log's. The missing-group block printed
  under it in the same report passes `--wsgs=$RUN_WSGS`. A group that failed on a cypher
  that was released and burned (its `CY_PARTIAL`; the round-2 fix routes it to re-model) has
  no dispatcher log row. Following the kept-host command before that re-model ends `=== study_area_run done
  ===`, exit 0, with the group missing; following the other command names it. The general
  limit of the log-derived set is an accepted tradeoff, but here the report has `RUN_WSGS` in
  scope and prints the weaker command beside the stronger one. Fix: append
  `--wsgs=$RUN_WSGS` in run_finish_report's kept-host block. hosts_kept_report and the
  consolidate-failure banner have no `RUN_WSGS` yet. They could pass
  `DISP_BUCKET ∪ CY_BUCKET[*]`, or say "add --wsgs=<the run's groups>".

- **[severity: fragile]** data-raw/study_area_finish.sh:457-458 and
  data-raw/study_area_hosts.sh:539. The one-group recompute command (`LNK_SCHEMA=...
  LNK_LOAD=loadall Rscript data-raw/wsg_recompute_one.R <WSG> <config>`) carries neither
  `LNK_RUN_UID` nor `LNK_RUN_LABEL`. The pool's jobs inherit both from the driver's exports
  (study_area_run.sh:389-390), and `.lnk_log_recompute_start()` defaults them from the
  environment (R/lnk_log.R:1239), so a recompute done by hand from the printed line writes
  that group's newest `log_recompute` row with `run_uid` NULL. That row describes what
  ships. This is the residual instance of round 1's `--run-label` finding: round 1 fixed the
  `--recompute-only` lines and not these. Fix: prefix `LNK_RUN_UID=$RUN_UID
  ${RUN_LABEL:+LNK_RUN_LABEL=$RUN_LABEL }` on both.

- **[severity: fragile]** data-raw/study_area_run.sh:639-671 (`--recompute-only`), against
  `run_finish_report`'s held-host split. In `--recompute-only` `CY_WS_ARR` is empty, so
  every missing group is printed as "Re-model each of these". Scenario: a full run keeps host
  `a` with BBBB finished there (its `${TS}_kept_hosts.tsv` says to consolidate BBBB). The
  operator re-models the report's re-model list and runs the printed `--recompute-only`
  before consolidating `a`. That run's report says to re-model BBBB. Doing so wastes the
  build and makes a later consolidate of `a` refused whole (`dest_log_newer`). The earlier
  TSV survives on disk (`--recompute-only` never calls `hosts_kept_report`). Fix: in
  `--recompute-only`, grep `$LOG_DIR/*_kept_hosts.tsv` for rows with this run_uid, and list
  their `groups` apart ("on a host an earlier session of this run kept: consolidate, do not
  re-model"). At minimum, print one line pointing at those files.

## Enumeration: every recovery instruction, its source, and its source of truth

| # | Where | Instruction | Computed from | Should agree with | Verdict |
|---|---|---|---|---|---|
| 1 | finish:367-379 | kept hosts: consolidate `groups` only where measured=yes, never partial | text, `KEPT_CAUSE_N` | TSV / hosts_kept_report / RUNBOOK §8d | agrees |
| 2 | finish:373-379 | recompute each kept group + upstream (or every group) | `RECOMPUTE_RAN` at report time | hosts_kept_report's text | agrees with the trap re-print; the explicit-burn banner (driver:1484, before the recompute) says "did NOT run: recompute EVERY group". The trap re-prints it with `RECOMPUTE_RAN=1`, so the last banner agrees. Superseded, harmless |
| 3 | finish:381-382 | `--recompute-only` (no `--wsgs`) | expected = dispatcher log | `RUN_WSGS` / row 9 | **disagrees** (finding 3) |
| 4 | finish:386-391 | class lists | `COV_*` | coverage | agrees (it is the source) |
| 5 | finish:408-411 | consolidate from host, do not re-model | `COV_MISSING ∩ ∪held CY_UNCONS` | hosts_kept_report `measured`, RUNBOOK §8d | **disagrees** for measured=no / unsettled (finding 1) |
| 6 | finish:412-415 | unknown provenance: check first | `∪held CY_DOUBT` | hosts_kept_report | agrees for yes; on unsettled the kept text says it may change (folded into finding 1) |
| 7 | finish:416-417 | re-model | remainder, incl. `CY_PARTIAL` and groups absent from the host | hosts_kept_report: unsettled partial = "may still be building, re-measure" | **disagrees** on unsettled (finding 1) |
| 8 | finish:421-423 | re-model command env | `RUN_UID`, `RUN_LABEL`, `SCHEMA`, guard=warn | the dispatch legs' env (driver:1320, 1354) | agrees; SHA / bcfp-version exports fall back (plan review Gap 9, accepted) |
| 9 | finish:427-428 | `--recompute-only --wsgs=$RUN_WSGS` | `RUN_WSGS` | the run's expected set | agrees |
| 10 | finish:430-432 | "host did not account ... re-run the missing ones" | `complete_fail` (accounting, DB-only) | coverage | **disagrees** when COV_MISSING is empty (finding 2) |
| 11 | finish:436-439 | compare re-run | `COMPARE_CSV`, `ALL_WSGS`, `CONFIG`, `LNK_SCHEMA` | run_finish_compare's call | agrees |
| 12 | finish:456-458 | one-group recompute | `SCHEMA`, `CONFIG` | pool env (`LNK_RUN_UID`/`LABEL` exported) | **disagrees** (finding 4) |
| 13 | finish:189-191 | recompute SKIPPED: nothing to settle | `ALL_WSGS` empty | coverage | agrees |
| 14 | hosts:505-519 | per-host measured / unsettled / not-answered text | `measured`, `CY_UNCONS/PARTIAL/DOUBT` | itself (the source of truth) | agrees |
| 15 | hosts:521-529 | consolidate only `groups`, measured=yes, never partial | text | RUNBOOK §8d | agrees |
| 16 | hosts:530-536 | recompute kept + upstream / every group | `RECOMPUTE_RAN` at call time | row 2 | agrees per call (see row 2 on timing) |
| 17 | hosts:537-538 | `--recompute-only` (no `--wsgs`, `--config=<config>`) | dispatcher log | the run's buckets | **disagrees** (finding 3; no `RUN_WSGS` in scope here) |
| 18 | hosts:539 | one-group recompute | `SCHEMA` | pool env | **disagrees** (finding 4) |
| 19 | hosts:541 | burn commands | `$@` (kept list) | the TSV | agrees |
| 20 | hosts:373-375 | preflight: consolidate an earlier kept droplet, then burn | workspace match | `*_kept_hosts.tsv` | agrees |
| 21 | driver:1463-1467 | consolidate failed: no group recomputed; `--recompute-only` once consolidated | text; dispatcher log | trap's hosts_kept_report ("did NOT run: every group") | agrees with the trap. Lacks `--wsgs` (finding 3); it exits before coverage, which is the accepted follow-up |
| 22 | driver:657-665 | `--wsgs` subset WARN; "pass --wsgs= to have it named" | `RO_LOGGED` vs `RO_EXPECT` | the run's log groups | agrees |
| 23 | driver:639-671 → finish:398-424 | the `--recompute-only` report's split | `CY_WS_ARR` empty, so every missing group is re-modelled | an earlier session's `*_kept_hosts.tsv` for this run_uid | **disagrees** (finding 5) |
| 24 | RUNBOOK 1248-1253 | recovery code block: `LNK_RUN_UID=<uid> LNK_SCHEMA=<schema> ... wsg_run_one.R` | doc | report row 8 (adds guard=warn, run label) | **disagrees** mildly. Without `LNK_GUARD_DOWNSTREAM=warn`, a group whose downstream neighbour is also missing stops at the guard (the default is error). It fails loud, and adding the two env vars to the block fixes it |
| 25 | RUNBOOK 1276-1280 | "could not be measured for ... consolidate it, do not re-model" | doc | RUNBOOK §8d "only where `groups_measured` is `yes`" | **disagrees** (finding 1) |

No other issues: the coverage SQL and set arithmetic, the arg-parsing refusals, the config
check, the moved pool functions and the exit-status paths still read correct after round 2.
