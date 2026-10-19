## Outcome

One failed group no longer costs every other group in a `study_area_run.sh` run its post-consolidate recompute.

- **Coverage splits instead of exiting.** `run_coverage`, in the new `data-raw/study_area_finish.sh`, sorts the run's groups by what the dispatcher's database says about the run_uid. A group counts as finished when its newest `log` row is this run's and closed, the same rule `schema_consolidate.R` uses, plus the driver's own finish signals. The four classes are:
  - rows from a finished build of this run;
  - no rows;
  - an earlier run's or partial rows;
  - rows lost at consolidate.
- **The recompute and the compare run over the first class only.** The rest are named, with recovery commands, and the run exits non-zero.
- **`--recompute-only --run-uid=<uid> [--wsgs=]`** finishes a run once its missing groups have been re-modelled under the same uid. It refuses a `--config` that the run's log rows do not name.

What was learned:
- **The plan review's blocker was real.** A forgotten `--config` would have recomputed all 241 groups of `fresh_default` under `bcfishpass` and stamped them with the run's uid.
- **Most of the review effort went into the recovery text.** Code-check rounds 1–3 each found the defect inside the previous round's fix of the kept-host advice. The mechanism: advice was computed from a set after the qualifier that gives the set its meaning had been dropped. The host's measured state lives only in `hosts_kept_report`. The fix was to stop re-deriving that advice and defer to `kept_hosts.tsv`. Round 4's 37-row enumeration of every printed instruction ended the loop.

## Measurement

- `fresh_default`, run_uid `20261017_004619-3f4c713b` (read-only):
  - The log names 241 groups and one config (`default`).
  - `run_coverage` puts 241/241 in the recompute class, with the newest-row rule, and 0 missing.
  - `run_config_check` refuses `bcfishpass`.
- `tests/testthat/test-study_area_finish.R`: 70 expectations on a scratch schema, with the real pool functions and an `Rscript` stub.
- **Mutants:**
  - restoring the exit on a missing group fails acceptance tests 1 and 2;
  - dropping the newest-row term fails the coverage test;
  - removing the empty-set skip fails acceptance test 2;
  - building the kept-host set from the bucket fails the kept-host test.
- **Other suites:**
  - `pool_probe.sh`: 37/37.
  - Hosts tests: 120/120.
  - Full suite: 3195 pass. The 4 failures are pre-existing: the golden-dams pin, which `CLAUDE.md` records as stale (8 pinned, 7 now), and `lnk_wsg_resolve` closure. No `R/` file changed on this branch.

## Deferred

These items are drafted as a follow-up issue, not filed:
- persist the run's group list when the buckets resolve, so `--recompute-only` sees groups that failed on cloud hosts;
- carry on to coverage after a consolidate refusal.

These are documented in RUNBOOK §8d, not fixed:
- `--recompute-only` takes no lock;
- `study_area_verify.sql` stays red for an open log row on the dispatcher;
- a soft-failed `date_end` cannot be rescued by `--recompute-only`.

Closed by: PR for #348 (branch `348-one-failed-group-skips-the-post-consolid`)
