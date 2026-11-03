# Findings — Province-wide `default` run at v0.78.2: re-model `fresh_default` for every change since 0.68.0 (#454)

## Issue context

**If we do it:** `fresh_default` becomes one build of all 241 groups at the code `fresh_default_minimal` was built at, in the same database. #444's parent table can then be built, and every re-model owed since 0.68.0 is paid at once.
**If we never do:** `fresh_default` stays at 0.68.0 (2026-10-23), behind seven modelling changes, and #444 has nothing to join to.

## Why now

`fresh_default` was last built at link 0.68.0 on fresh 0.42.0 (run `20261023_074321-24d85e8c`). Since then #326, #396, #399, #401, #402, #429 and #432 have each changed what `default` models, and each says its groups re-model at the next provincial `default` run. #441 built `fresh_default_minimal` at 0.78.1 on m4 (run `20261102_203300-60ab009d`). #444 joins full segments to the minimal segment they sit in, so it needs `fresh_default` built at the same code, species set and primitives load, in the same database.

## The run

- `--config=default --schema=fresh_default`, dispatched from m4 (where `fresh_default_minimal` is), with m1 as a worker and three cloud hosts (`job1`–`job3`), `--buckets-exact --recompute-jobs=8 --auto-install`, the default 30 min statement bound.
- Packed on measured minutes (`--minutes-schema`, `--host-names`, `--plan-out`), then `host_speeds_calibrate.R` on the run.
- No `--refresh-primitives`: the run reads the 2026-11-02 load the minimal build read. The two bchamp objects are HEADed against `data-raw/logs/hosts_ready_439/load_stamps.csv` just before launch.
- Run from a branch cut from `main` at v0.78.2, with no change on the gate's watched paths before launch.

## Before launch

- [ ] m1's `fresh_default` (the 0.68.0 build, 241 groups) renamed to `fresh_default_20261023`: a worker's schema must hold no rows for its bucket. It stays as the 0.68.0 reference.
- [ ] m4's `fresh_default` (30 development groups) is replaced by the run; nothing in it is kept.
- [ ] The pre-run gate (#372) passes: `pretest_run.sh --config=default --schema=fresh_default --history-schema=fresh_default_history` (m4's copy of the 241-group history; #450 would make the flag unnecessary).
- [ ] `BCFISHOBS_DIR` points at a clean clone (#451).
- [ ] No other active client on either database; the Tailscale path to m1 probed (RUNBOOK §8d).

## Acceptance

- [ ] Driver exit 0; `study_area_verify.sql` and `verify_extra.sql` pass at `expected_n=241`; `recompute_audit.R` passes.
- [ ] Every row carries `cut-full-top acc-v5 grad-seg q-fwapg`, one link SHA, fresh 0.52.0.
- [ ] No host kept, no droplet left.
- [ ] `research/study_area_run.md` gains the run; evidence in `data-raw/logs/default_run_<N>/` and `data-raw/logs/study_area_run/<TS>_*`; #377's runs row filled.
- [ ] The host-speed calibrator run and its update committed.

## What its numbers serve

#369, #371, #374, #375 and #376 each wait on a provincial `default` run's numbers; whether this run closes them is the operator's call. Not in scope: #259's `fit.R` re-fit and #261's re-run (named in the record as still owed), the `bcfishpass` schema's re-model.

Relates to #441, #444, NewGraphEnvironment/knowledge#120.


## Found at planning (2026-11-03)

See "Found at planning" in `task_plan.md`: the Tailscale path, both hosts' state, the fresh 0.53.0 install on m4, `fresh_default.log_pretest` absent on m4.

## Errors Encountered

| Error | Resolution |
|-------|------------|
