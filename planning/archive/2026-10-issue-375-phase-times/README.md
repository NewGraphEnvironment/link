## Outcome

`study_area_run.sh` now writes `<TS>_phases.tsv`, one row per phase per host as each phase ends (`data-raw/study_area_phases.sh`): prep, refresh, model, account, consolidate, burn, coverage, views, recompute and compare. A phase that did not run gets a `skipped` row. The summary prints the table, the critical path and the longest model leg, and `--recompute-only` writes its own file under the run's uid. Every later speed item on #377 reads its numbers from this file. Each model and prep leg writes its own row from an outer wrapper, because the legs are waited on in turn and a wait's return is not a leg's end. That wrapping was where the review found its defects: the plan review found that a kill duplicated rows and that the burn's return value means nothing (`burn_cyphers` returns its caller's `$?`). Code-check round 1 found errexit off on the left of `|| mrc=$?` (a failed `cd` stopped failing the leg), and round 3 found that the wrappers held the driver's stdout open, so after a kill a `| tee` stayed open for the whole leg.

## Measurement

- A dispatcher-only run (NBNK, EUCH, `default`, scratch `fresh_375`) wrote one row per phase. The critical path was 2.2 min and the model leg 1.6 min, exit 0. The `model` row (03:30:43 to 03:32:21 UTC) brackets the two `log` builds (03:30:45.7 to 03:32:22.0), and the `recompute` row (03:32:24 to 03:32:36) brackets `log_recompute` (03:32:26.4 to 03:32:36.0). Each row agrees with the database to the second.
- File mtimes cannot check the rows, because the EXIT trap's address redaction rewrites every log at exit. The database is the independent check.
- A SIGTERM 22 s into `model` produced a `failed` row from the trap and exit 143. The leg ran on and wrote its own `ok` row 63 s later with the same start.
- Wrapper EOF on bash 5.3, measured with `| cat` around a 3 s leg: the old shape gave 0 s, the new unredirected shape 3 s, and the shipped shape (wrapper redirected to its leg log) 0 s. The run was repeated at `ecf1c3fc` through `| tee` with the same rows.
- The review took 1 plan review and 4 code-check rounds. Rounds 2 and 4 were clean, each listing every context the wrapping changes, and no round found a defect inside an earlier fix.

## Evidence

`data-raw/logs/phases_375/` (its README indexes it).

## Owed

- Acceptance criterion 2: the next provincial run's `phases.tsv` committed with its evidence, and its #377 runs row filled from it. #375 stays open for it, as #371 did.

Closed by: PR (opened next) for #375; #375 stays open for the owed item.
