# Task: study_area_run.sh: consolidate each cloud host when its own leg finishes, then burn it (#369)

`study_area_run.sh` waits for every leg (the dispatcher's and each cloud host's) before it consolidates anything, then consolidates every host in one call, then burns them. So a cloud host that finished early sits idle, paid, holding the only copy of its groups, until the slowest leg ends and the whole consolidate completes (about 3 host-hours on 2026-10-17, about 20 on 2026-10-23).

## What exploration found (shapes the phases)

- **The wait/consolidate/burn block** is `data-raw/study_area_run.sh:1528-1722`. Per-host pieces already exist in `data-raw/study_area_hosts.sh`: `host_wait`, `host_account`, `host_consolidate_bucket`, `host_release`, and `burn_cyphers`, which burns every unheld, unburned host, so calling it after one release burns that host only. `data-raw/study_area_finish.sh` has `consolidate_outcomes`, `consolidate_state_write` and `run_unconsolidated_from_state`. All of them assume one consolidate covering every source.
- **`CONSOLIDATING` is a single global.** `.hosts_settled` reads it for every host (`study_area_hosts.sh:176`).
- **`schema_consolidate()` judges a copy on whole-table counts** (`schema_consolidate.R:474-601`, `copy_empty`: post must be greater than pre over every row of each table). While the dispatcher deletes and re-inserts its own groups in the same tables, that test can fail a good copy. It has to count the bucket's rows only.
- **Lock contention to measure.** `lnk_persist_init()` runs once per group on the dispatcher. It calls `CREATE INDEX IF NOT EXISTS` on the persist tables (`R/lnk_persist_init.R:390-498`) and `.lnk_log_create_tables()`, which runs `ALTER TABLE … ADD COLUMN IF NOT EXISTS` on the log tables (`R/lnk_log.R:511`; ACCESS EXCLUSIVE). If either waits behind a consolidate `COPY` transaction or a `pg_dump`, the wait counts toward the 30 min statement bound (#371).
- **Test harness:** `tests/testthat/test-study_area_hosts.R` runs the libs in bash 4+ with stubs for ssh, psql, tofu and doctl on PATH and a mock `cypher_down.sh`. A stub `Rscript` fits the same pattern. Homebrew bash is 5.3.

## Decided at the gate

- **The backup is taken once, before the dispatcher leg starts** (operator, 2026-10-23). The cypher legs are launched first (they write only to their own databases), then the dump, then the dispatcher leg. The result is a true pre-run snapshot that nothing is writing to. #354's dump, by contrast, was taken after m1 had rebuilt 76 groups. Per-host consolidates pass `backup = FALSE`.
- **Test on little groups before merge** (operator, 2026-10-23): a small real multi-host run and a live negative run, in Phase 5. That costs about $0.50 to $1 of droplet time. The run decisions are stated before launch, per CLAUDE.md.
- **Run all phases without waiting for a go-ahead before the Phase 5 launches** (operator, 2026-10-24): fire up the cyphers, and poll so a run that hangs is caught.
- **Mechanism, decided here:**
  - The legs are waited on with `wait -n -p` (bash ≥ 5.1, so the driver's floor rises from 4). PID polling is avoided because PIDs get reused.
  - Consolidates run one at a time in the main shell, in the order the legs finish.
  - A per-host consolidate that dies without an outcome keeps that host, keeps its groups out of the recompute with their state left `in_flight`, and the run carries on and exits non-zero. Exiting there, as today, would orphan the legs still running.
  - `consolidate_state.tsv` gains a `state_utc` column, and the old 4-column header is still read.

## Phase 1: Measure before building
- [x] Lock experiment on local docker fwapg in a scratch schema: with one session holding an open `COPY` transaction into a table, does a second session's `CREATE INDEX IF NOT EXISTS` (index already present) block? Does `ALTER TABLE … ADD COLUMN IF NOT EXISTS` block? Repeat both against a running `pg_dump`. Record in findings.md.
- [x] Time `pg_dump -Fc --schema=fresh_default` (to the scratchpad, deleted afterwards): the minutes the backup adds to the dispatcher leg.
- [x] From `data-raw/logs/provincial_361/`, read each source's copy minutes and its longest single-table `COPY` out of the 2026-10-23 consolidate log, and compare them with the 30 min bound.
- [x] If the `CREATE INDEX IF NOT EXISTS` check blocks: `lnk_persist_init()` checks `to_regclass()` for the index before issuing it, with a test. If it does not block, record why no change is needed.

## Phase 2: `schema_consolidate()` safe beside a writing dispatcher
- [ ] Judge `copy_empty` on the bucket's rows (`WHERE watershed_group_code IN (bucket)`), through a SQL builder with its own test in `test-schema_consolidate.R`.
- [ ] Extract `schema_consolidate_backup(schema)`. `schema_consolidate(backup = TRUE)` calls it, so existing callers are unchanged, and the driver calls it on its own.

## Phase 3: Per-host consolidate in the libs (tests first)
- [ ] `CONSOLIDATING` holds the workspace being copied, or nothing. `.hosts_settled <ws>` and `.hosts_unsettled_why` judge only that host as mid-copy.
- [ ] `consolidate_outcomes <tsv> <ws>` reads one source's row and accumulates `CONS_FAILED` and `CONS_EXCLUDED` across calls.
- [ ] `consolidate_state_write` writes every host from per-host `CY_CONS_STATE` / `CY_CONS_UTC` (`in_flight`, `ok`, `failed:<stage>`) with `state_utc`. `run_unconsolidated_from_state` reads both headers.
- [ ] New `host_finish_leg <ws>` in `study_area_hosts.sh`: account, then consolidate one source (Rscript, `backup = FALSE`), then outcomes, state, `host_release` and `burn_cyphers`, with per-host `account`, `consolidate` and `burn` phase rows. An empty bucket is skipped and the host kept. An outcome-less failure works as decided above.
- [ ] New `legs_wait`: waits with `wait -n -p` over the dispatcher's and the cyphers' PIDs, calls `host_finish_leg` for each cypher as it ends, and records the dispatcher's end. Raise `hosts_bash()` in the tests to 5.1.
- [ ] Tests:
  - per-host step with a stub `Rscript` writing outcomes;
  - **negative:** a refused source (`dest_log_newer`) gives a `kept_hosts.tsv` row with the burn command, and the other host is still burned;
  - an outcome-less failure;
  - **a real race:** fake legs of 1 s and 6 s, where the mock `cypher_down.sh` must have burned the short one before the long one ends;
  - a trap during host a's copy sees a unsettled and b settled;
  - an old-header state file is still read.

## Phase 4: Wire the driver
- [ ] Order: launch the cypher legs, then the backup (`schema_consolidate_backup`, failure fatal before the dispatcher writes anything; the cyphers stay held), then the dispatcher leg, then `legs_wait`, then the dispatcher's `host_account` and `run_wsgs_write`. Remove the single consolidate and burn blocks.
- [ ] Phase rows: check that `phases_report` and the critical path handle per-host `consolidate` / `burn` rows, plus a run-wide `backup` row (a new phase name in the phases lib and `test-study_area_phases.R`).
- [ ] Update the structural tests: the driver R snippet in `test-study_area_finish.R:646`, and the drv checks in `test-study_area_phases.R`. Then `bash -n` and shellcheck if installed.
- [ ] Update the driver header (burn on each leg's end, the backup timing and why, `--keep-cyphers` = consolidate on finish without burning), and the bash ≥ 5.1 check.

## Phase 5: Live check on little groups (operator's ask)
- [ ] **Run A:** dispatcher plus job1 and job2, from a worktree. Config `default`, scratch schema `fresh_smoke369`, `--buckets-exact`. Pick small groups from the 2026-10-23 minutes so that job1 ends first, job2 second and the dispatcher last. State the decisions, then launch.
- [ ] Check Run A:
  - each cypher is burned within minutes of its leg's end (`phases.tsv`, doctl);
  - `consolidate_state.tsv` has `ok` rows whose `state_utc` falls inside the dispatcher's model window;
  - there is no `kept_hosts.tsv`;
  - `study_area_verify.sql -v schema=fresh_smoke369 -v expected_n=<N>` and `verify_extra.sql` pass;
  - the overlapping dispatcher groups' minutes are compared with the same groups' 2026-10-23 minutes.
- [ ] **Run B (negative):** one cypher, with a future-dated log row for one of its groups seeded in `fresh_smoke369`. Expect `dest_log_newer`, the host kept with a `kept_hosts.tsv` row and burn command, and a non-zero exit. Then burn it by its listed command and confirm doctl shows it gone.
- [ ] Evidence goes in `data-raw/logs/consolidate_on_finish_369/`, with a README. `fresh_smoke369` is kept until merge and dropped on the operator's word.

## Phase 6: Docs and release
- [ ] RUNBOOK §8d: "Which host may be burned" (per-host consolidate and burn, `CONSOLIDATING` per host, the outcome-less rule) and "Where a run's time went" (the per-host rows and `backup`). Also the backup timing and the reason.
- [ ] CLAUDE.md status, NEWS, and the version bump as the last commit.

## Owed at the end (reported, done after merge)

- [ ] On the next provincial `default` run: idle cloud minutes per host, consolidate rows inside the modelling window, and the dispatcher groups that overlapped a copy against their 2026-10-23 minutes. Fill #377's runs row.

## Validation

- [ ] Tests pass (`devtools::test()`)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification:
- bash unit tests with stubs prove the per-host logic, the negative case and the race ordering.
- The Phase 1 lock experiment proves the dispatcher is not blocked, or the fix that stops it.
- Run A proves the timing on real droplets, and Run B proves a refused host is kept and listed.
