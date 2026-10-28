# Task: A scoped pre-run gate: model the groups that stress each rule changed since the last provincial run (#372)

## Problem

Each provincial run is the first time some newly landed code meets every group. On 2026-10-23 the near-river walk (link 0.67.0 / fresh 0.42.0, #364) had been built and scored on ADMS, BULK, CHWK, CLWR and SQAM; the run was its first contact with OKAN and KTSU, and the dispatcher lost about five hours to those two groups while three cloud hosts idled. Whether or not the walk itself was the cause (see the #361 record), the pattern is general: a rule's cost and its correctness are driven by an input the test groups did not carry (here, lake connector length and lake-centreline density), so a happy-path group set cannot find it before the ten-hour run does.

Operator, 2026-10-23: "Provincial runs should prob be pretended with scoped tests to be sorted we have a working system before running for 10hrs to find out."


## Decided at the gate

- **Enforced, not just documented** (operator, 2026-10-28). The gate writes a record to
  `<schema>.log_pretest`, beside the run logs. `study_area_run.sh`'s `preflight_local()` refuses a
  run unless a passing record matches HEAD's link SHA (clean tree), the config and the installed
  fresh SHA. `--pretest-note="<why>"` skips the check, with the reason printed and logged, the same
  pattern as `--preflight-note`.
- **Every changed file must be accounted for.** The changed-file → input map is a tracked CSV
  (`data-raw/pretest_inputs.csv`: repo, path regex, input, why). An input is a query, or one of two
  special values. `any` means every pick runs this file, and when nothing else is picked the
  fastest group is used. `none` means the file is off the modelling path (validator, compare,
  export). A changed file that matches no row makes the gate refuse (exit 2). A test checks that
  every file in link's `R/` matches a row, so the map cannot fall behind link. fresh files are
  checked only when the gate runs.
- **The bound is k × the group's newest finished minutes in `--schema`'s log,** with k = 3 by
  default and a floor of 5 min (a 0.5 min group would otherwise be bounded by noise). Each group's
  statement timeout is `min(--statement-timeout, ceil(bound))`, so a stall fails within the bound
  rather than after 30 min. The host that measured the history is printed beside it. Minutes
  measured on a cloud host make the bound looser on m1, never tighter.
- **`--config` and `--schema` are required, with no defaults** (the run-decision rule). Picks
  are restricted to groups with a finished row in that schema's log, which guarantees each one
  has a history value and is modelable under the config.
- **The acceptance re-run "against 0.68.0":** pick with `--since=<v0.66.6 sha> --until=v0.68.0`
  (fresh diff v0.39.0..v0.42.0), and model the picks at HEAD. Modelling at 0.68.0 itself would
  need fresh 0.42.0 installed over the shared library. A separate real gate runs over
  `1d00c04c..HEAD` for the next provincial run.
- **Out of scope:** the recompute (#261's walk cost). The gate models groups and nothing more, as
  the issue scopes it.

## Phase 1: helper library, map, tests

- [x] `data-raw/pretest.R` (pure functions, sourced by the scripts and the tests):
  - the changed files for link (`git diff --name-only <since>..<until> -- R/ inst/extdata/configs/<config>/`)
  - the changed files for fresh (the `Remotes:` pin at each end; `git -C <fresh repo> diff --name-only` between the tags; refuse when a tag is missing locally)
  - matching files to map rows, and reporting the unmatched ones
  - the bound per group
  - the verdict per group (`pass`, `failed`, `bound`, `no_row`)
- [x] `data-raw/pretest_inputs.csv` seeded for every file in link's `R/` and for the fresh files changed v0.39.0..v0.44.0. Inputs: `near_river_conn`, `segments`, `observations`, `crossings`, `dams`, `any`, `none`. The CSV's `why` column records each row's reasoning
- [x] `tests/testthat/test-pretest.R`:
  - every `R/` file matches a row
  - an unmapped file is reported
  - `any` and `none` behave as defined
  - bound arithmetic, including the floor
  - verdict classes
  - restore each defect and watch the test fail

## Phase 2: input queries and the pick

- [x] One query per input under `data-raw/pretest/<input>.sql`, each returning `(watershed_group_code, value)` for every group. Each is checked against the DB (top rows printed); `near_river_conn` reproduces fresh's `conn_max` SQL
- [x] `data-raw/pretest_pick.R`: changed files, then inputs, then the top `--per-input` groups (default 2) among groups with history, then the union. It writes `<out>/picks.tsv` and the pick section of `<out>/pretest.md` (changed files, input per file, each query's text and top rows, the picks, the estimated minutes). It exits 2 on an unmapped file

## Phase 3: the gate driver

- [ ] `data-raw/pretest_run.sh --config= --schema= [--since=<sha>] [--until=HEAD] [--per-input=2] [--k=3] [--floor-min=5] [--statement-timeout=30] [--out=]`:
  - prints the run decisions first
  - `--since` defaults to the newest run_uid's `link_sha` in `<schema>.log`
  - refuses bash < 5.1
  - refuses a dirty tree unless it is pick-only
  - drops and recreates the scratch schema `fresh_pretest_<config>`, refusing any other name
  - models the picks one at a time through `wsg_run_one.R` (`LNK_LOAD=loadall`, `LNK_SCHEMA`, `LNK_GUARD_DOWNSTREAM=warn`, `LNK_HABITAT_GATE=0`, the per-group `PGOPTIONS` bound)
  - reads each group's minutes from the scratch schema's `log` and prints the verdict table
- [ ] It writes one `<schema>.log_pretest` row per gate run: `run_at`, link_sha, `link_dirty`, fresh_sha, config, since, until, k, groups, verdict, notes. It creates the table if it is absent and leaves existing tables alone, with no DDL on the run's tables. Exit codes: 0 pass, 1 a group failed or breached its bound, 2 refused
- [ ] `--pick-only`, which writes no record. A stall test: `LNK_TEST_STALL_WSG=<pick>` must end the gate with exit 1, naming the group within its bound

## Phase 4: enforcement in study_area_run.sh

- [ ] `preflight_local()` reads `<schema>.log_pretest` and requires a passing row with HEAD's link SHA, `link_dirty` false, the run's config and the installed fresh SHA. Otherwise it is FATAL and names the gate command to run
- [ ] `--pretest-note="<why>"`: an empty value is refused, the banner prints an `OVERRIDE:` line, and the note reaches `LNK_RUN_LABEL` or the log notes, as `--preflight-note` does. `--preflight-only` runs the check too
- [ ] Test the check with a passing row, no row, a SHA mismatch, a dirty row and a note, against a scratch table. Restore each defect and watch the test fail

## Phase 5: acceptance runs and evidence

- [ ] Pick-only: `--since=<v0.66.6 sha> --until=v0.68.0 --config=default --schema=fresh_default`. QUES must be picked for the walk; record the picks
- [ ] Model those picks at HEAD and record the verdicts and minutes, QUES included
- [ ] A real gate, `--since=1d00c04c` at HEAD: picks, verdicts and minutes, with a passing record written
- [ ] The negative case: the stall hook exits 1, and `study_area_run.sh --preflight-only` refuses without a record and passes with one
- [ ] `data-raw/logs/pretest_372/`: `pretest.md` plus a README indexing it, logs redacted

## Phase 6: docs and release

- [ ] RUNBOOK §8d gets "The pre-run gate (link#372)" (how picks are made, the map, the bound, the record, the override), and §8d's opening says the gate comes first
- [ ] `study_area_run.sh` header: the gate precedes a provincial run, and `--pretest-note`
- [ ] A CLAUDE.md status entry with the facts not worth re-deriving, and the #377 runs-row note
- [ ] NEWS and the version bump as the final commit


## Folded in from the plan review (planning/active/review-plan.md)

- [ ] B1: `pretest_record_check()` in pretest.R; a record holds while every file changed since its SHA maps to `none`
- [ ] B2/A6: `--since` default is the oldest link_sha among the history's newest finished rows; the check requires since to cover them
- [ ] B3: `--pretest-note` writes an `override` row
- [ ] G1: pathspec R/, inst/extdata/, DESCRIPTION, data-raw entry points; coverage test over inst/extdata
- [ ] G2: `unexercised` special input
- [ ] G3: scratch tables LIKE the persist's
- [ ] G6: wall-clock watchdog at the bound
- [ ] G7: refuse during a live run
- [ ] G8: `--minutes-schema`, `--minutes-exclude`

## Owed at the end (reported, done after merge)

- [ ] At the next provincial run (#377's runs row), run the gate first. Record its picks and its minutes beside that run's own minutes for the same groups, which tests whether k = 3 is right

## Validation

- [ ] Tests pass (`devtools::test()`), lintr clean
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each part is proved:
- The pick is proved by the acceptance re-run selecting QUES.
- The bound and the failure paths are proved by the stall hook and by mutated tests.
- Enforcement is proved by `--preflight-only` refusing, then passing.
- Map completeness is proved by the `R/` coverage test.

The acceptance gates run from a `git worktree` of the branch, so no edit lands in a tree that a
run models from.

