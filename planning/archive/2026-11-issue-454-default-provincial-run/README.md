# #454: province-wide `default` run at v0.78.2

## Outcome

`fresh_default` on m4 is one `default` build of all 241 groups at link `4dfbfa49` (0.78.2) on fresh 0.52.0, run_uid `20261103_163715-269b585a`, built from m4 with m1 as a persistent worker and three cloud hosts. It pays, for `default`, every re-model owed since the 0.68.0 build (#326, #396, #399, #401, #402, #429, #432), at the code and primitives load `fresh_default_minimal` was built at, in the same database, which is what #444 needs. Two things differed from the plan as first written. The gate command the issue named cannot run (`--history-config` must be a config the bundle extends, and `default` extends nothing); the Plan review caught it, and the gate ran with no history flags against a `fresh_default.log` seeded from `fresh_default_history.log`. Auto mode refused both schema changes: the operator ran m1's rename, and m4's old schema was renamed (`fresh_default_dev_20261103`) instead of dropped. The record is `research/study_area_run.md`, "The province-wide `default` run (2026-11-03, 241 groups; #454)".

## Measurement

- Gate (at `68a6196f`): 11 of 11 picks within bound; QUES 15.5 min against its 0.68.0 9.3 (bound 28.0), the rest 0.35 to 0.80 of their last minutes.
- Run: 237.2 min launch to done, prep 10.5. Legs m1 109.8 min (55 groups), m4 121.9 (52), job2 159.2 (45), job3 175.5 (44), job1 178.6 (45), against 197.2 to 198.1 projected each at the learned speeds. So packed on learned speeds, m4 and m1 still ended their modelling 57 and 69 min before the last cloud leg; the calibrator's second update moved m1 1.183 → 1.310, m4 1.107 → 1.181, cloud 0.947 → 0.910 (run-wide ratio 0.753).
- Consolidate m1 42.9 min, cloud 11.7 to 14.0; job1 waited 10.0 min after its leg while the driver finished job3. Recompute 156.2 min summed, 82 launched early, 46 of them before the last leg ended, tail 15.6 min past the last consolidate (the 2026-10-23 replay's was 60.6).
- `fresh_default`: 5,546,370 segments (0.49 of the 0.68.0 build's 11.39 M; 1.11 times `fresh_default_minimal`'s 4.99 M), 19 GB. QUES the longest group at 27.0 min on job3; no statement hit the 30 min bound.
- `check.sh` all PASS (verify and negative cases at 241, audit 2,191 of 2,191 pairs), `verify_extra.sql` exit 0, tokens `cut-full-top acc-v5 grad-seg q-fwapg` with one fresh and one link sha on all 241 of the run's rows (the 242 seeded history rows stay in `log`, token columns NULL). The launcher `exec`s the driver, so its exit status was read from its own summary, not from an exit line.
- The two builds' `link_sha`s differ (`193cb8aa` 0.78.1, `4dfbfa49` 0.78.2; no change under `R/`, `inst/`, tests or the drivers but `DESCRIPTION`'s version), so #444's guard as worded refuses the pair; noted on #444.

## Evidence

`data-raw/logs/default_run_454/` (launch, packing, checks, `run.log`), `data-raw/logs/study_area_run/20261103_163715_*`, `data-raw/logs/pretest/20261103_153249_default/`, `data-raw/logs/host_speeds*.tsv`.

## Owed

- #444's parent table, now buildable.
- The calibrator's third run (#163's three-run acceptance) on the run that follows.
- #259's `fit.R` re-fit and #261's `predictors.R` / `correlations.R` re-run on this run's minutes (named in the record as still owed).
- fresh 0.53.0 back on m4 for whoever installed it, if they still need it.
- Also: `fresh_default_dev_20261103` on m4 can be dropped; the `fresh` (`bcfishpass`) schema's re-models wait for a provincial `bcfishpass` run.

Closed by: PR (this branch, `454-default-run`)
