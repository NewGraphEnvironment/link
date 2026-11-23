## Outcome

Backlog move 7 landed as 0.89.0: every `data-raw/` driver refuses to run without an explicit config (#278), the persist-writing drivers also refuse a non-`bcfishpass` bundle with no `LNK_SCHEMA`, `study_area_run.sh` prints a decisions block before its first write, a standalone `wsg_run_one.R` / `wsg_recompute_one.R` needs `LNK_RUN_LABEL` while its `run_uid` stays NULL (#281; owner's answer, so PUBLISH keeps refusing such builds), `state_clean.sh --tables=` / `--hosts=` drops named tables locally by default and checks every host's drop (#181), the nine legacy `wsgs_*` / `trifecta_*` scripts are deleted (#179 and #110 close as retired, #176 shrinks), and `data-raw/README.md` is corrected to noun-first with no renames (#166; every verb-first script is cited by path). Learned: a new refusal invalidates every previously valid invocation, and `/code-check` found them one site at a time (hints in R and SQL, bundle READMEs, usage headers, test helpers) until round 3 enumerated all 41 live sites. A mutant R driver that accepts a config models for real against the local fwapg: one mutation proof did, and left an open `fresh.log` row for DEAD (and possibly rewrote DEAD's `fresh.streams` rows) on the dispatcher's local database.

## Evidence

`planning/archive/2026-11-issue-475-drivers-config-label-legacy/review-round*.md`, `review-verdict.md` (3 rounds, ended on an enumeration of 41 sites). Tests: `tests/testthat/test-driver_config.R`, `test-state_clean.R` (local only; `data-raw/` skips in CI).

## Owed

- Post the closing comments on #179 and #110 and the shrink note on #176
- Hosts and anything outside this repo that call a retired script or omit a config (scheduled jobs, the cloud image's scripts, operator shell history) move to `study_area_run.sh` with an explicit `--config=`: named in the PR body for the operator
- Check DEAD in the dispatcher's local `fresh` after the mutation proof ran a real bcfishpass model of DEAD there (open `fresh.log` row from 2026-11-23 14:36 UTC); re-model DEAD under bcfishpass if its rows matter

Closed by: PR (this branch)
