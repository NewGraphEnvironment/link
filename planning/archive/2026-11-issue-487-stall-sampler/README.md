## Outcome

A stalled statement now leaves a record of what it waited on (#487). `wsg_run_one.R` starts
`data-raw/wsg_stall_sample.R` beside each group. From a second connection, the sampler
(`.lnk_stall_watch()`, `R/lnk_stall.R`) waits until the group's backend has been on one
statement for N minutes. N is `--stall-sample-after`; unset, it is 10 min, or half the bound
when that is shorter. From then on it writes one `[wsg_stall] <WSG>` line per backend at each
check into the group's log: the leader, its parallel workers, and each session
`pg_blocking_pids()` names, with the host's load and the active backends. The driver
(`run_stalls`) splits the lines into `<TS>_stall_<WSG>.tsv` and names each file in the
summary and under `statement bound hit`. The sampler ends with its group and cannot fail it.

Most of what was learned came from review, and all four rounds traced to one mechanism: each
decision had been made where its deciding input was not known.
- **Round 1:** the driver judged the default threshold against the bound and refused
  `--statement-timeout=1..10`.
- **Round 2:** the fix's 0.5 min default was named by a proxy (bound above threshold) that
  rarely held; it became a marker the sampler creates with its first row.
- **Round 3:** the default lived in the driver, so the pre-run gate and printed re-models
  missed it, and the sampler spaced its checks without knowing the bound. The threshold moved
  into `wsg_run_one.R`, the bound is passed to the sampler, and the line names the log lines
  rather than a file the group cannot vouch for.
- **Round 4:** an enumeration of 25 places where one stage concludes what another decides, all
  holding.

The plan review (`review-487.md`) caught two further gaps before they shipped. The gate did not
watch new data-raw scripts (`PRETEST_LINK_PATHS`). Host logs are grepped unanchored, so a
blocker's query text could have faked a `done` marker.

Mechanics: RUNBOOK §8d, "A stalled statement leaves samples".

## Measurement

- **The whole chain, in a driver run** (`20261115_001427-474338b7`, m1, EUCH stalled under a
  2 min bound): four `PgSleep` rows from 00:17:43 to 00:18:28Z, its statement having started
  at 00:16:41Z. The file was named on the TIMEOUT-following line, in the summary and under the
  statement. NBNK finished in 0.7 min, under the 1 min threshold, and wrote no rows.
- **How long the sampler outlives its group:** a re-model through a pipe closed 1.2 s after
  the group's R process exited, inside the 2 s parent poll. That is how long an ssh leg would
  be held.
- **Short bounds:** under a 1 min bound and the derived 0.5 min default, two rows landed
  inside the 30 s window. A 5 min threshold under a 1 min bound turns the sampler off, with a
  line saying why.
- **Suite:** the full suite and `check` failed only on 3 tests that need the `PG_*_SHARE`
  tunnel, which was down; nothing in them changed.
- **Not measured:** a remote leg. A worker run is refused before spend while m1 and m4 hold
  different modelled crossings.

## Evidence

`data-raw/logs/stall_sample_487/` (its README); code-check rounds in this directory
(`review-487.md`, `review-round*.md`).

## Owed

- The next real stall leaves a `_stall_` file; its reading goes into #487's body and the fix
      is filed where it lives (#487 acceptance 2; the issue stays open).
- The pre-run gate runs again before the next provincial run (`R/`, `wsg_run_one.R`,
      `pretest_inputs.csv` changed).

Closed by: PR for branch `487-record-what-a-stalled-statement-is-waiti` (release v0.83.0); #487 stays open for its second acceptance line.
