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
- [x] Judge `copy_empty` on the bucket's rows (`WHERE watershed_group_code IN (bucket)`), through a SQL builder with its own test in `test-schema_consolidate.R` (review G7).
- [x] Refuse a source, before anything is deleted, when a table only the source has is a persist table (review B2).
- [x] Log each table's copy seconds (review A1); a `verify = FALSE` argument skips the final whole-schema count print (G7).
- [x] Extract `schema_consolidate_backup(schema)`, which checks pg_dump's exit code and the dump's size (B1). `schema_consolidate(backup = TRUE)` calls it, so existing callers are unchanged, and the driver calls it on its own.

## Phase 3: Per-host consolidate in a new lib, `data-raw/study_area_legs.sh` (tests first)
- [x] `CONSOLIDATING` holds the workspace being copied, or nothing. `.hosts_settled <ws>` and `.hosts_unsettled_why` judge only that host as mid-copy.
- [x] `consolidate_outcomes <tsv> <ws>` reads one source's row and accumulates `CONS_FAILED` and `CONS_EXCLUDED` across calls.
- [x] `consolidate_state_write` writes every host from per-host `CY_CONS_STATE` / `CY_CONS_UTC`, with `state_utc` appended as the fifth column. `run_unconsolidated_from_state` reads both headers. An outcome-less failure stays `in_flight` (review G2, S2).
- [x] `burn_cyphers` considers only hosts whose leg ended (`CY_LEG_DONE`) until every leg has ended, so a mid-run burn never reports a modelling host as kept. The trap considers all (G1).
- [x] `host_finish_leg <ws>`, in the main shell:
  - account, accumulating `complete_fail`, then `run_wsgs_write`;
  - write the state `in_flight`, then consolidate one source (Rscript, `backup = FALSE`, `verify = FALSE`, per-host log and outcome files), then outcomes, state, `host_release` and `burn_cyphers`;
  - per-host `account`, `consolidate` and `burn` phase rows;
  - an empty bucket skips the copy but still goes through release (O3);
  - an outcome-less failure sets `CY_CONS_FAIL=no_outcome`, is added to `CONS_FAILED` and `CONS_EXCLUDED`, gets no release, and the run carries on;
  - every exit becomes carry-on (G2–G5).
- [x] `legs_wait`: a pending list over `wait -n -p` (B4). A cypher whose finished set overlaps the dispatcher's bucket waits in a deferred queue until the dispatcher leg ends (B3). Declare the maps at the top level (G8). `hosts_bash()` is raised to 5.1 with a minor-version check (G10).
- [x] Tests (the helper sources the hosts, finish, phases and legs libs):
  - the per-host step with a stub `Rscript`;
  - **negative:** a refused source gives a `kept_hosts.tsv` row with the burn command, and the other host is still burned;
  - an outcome-less failure;
  - **a real race:** legs of 1 s and 6 s, where the short one is burned before the long one ends;
  - two legs ending during one copy, and the dispatcher ending first, with exactly one consolidate per host;
  - a deferred overlap;
  - a trap mid-copy sees that host unsettled and the other settled;
  - a mid-run burn does not list a modelling host;
  - an old-header state file is still read.
  - Update test-study_area_hosts.R:734-750 and test-study_area_finish.R:646 and :687-713 (G9).

## Phase 4: Wire the driver
- [x] Before the spin: `lnk_persist_init` the dispatcher's schema (`cfg$species`, no force_recreate; B1, B2), then the backup in the background through spin and prep. The dispatcher leg waits for it, and a failure is fatal before any dispatch (O1). Only when cyphers are in the run (A4).
- [x] Then launch the cypher legs and the dispatcher leg, then `legs_wait`, then the dispatcher's `host_account` and a final `burn_cyphers`. Remove the single consolidate and burn blocks.
- [x] Phase rows: a `backup` phase name in the phases lib, per-host `consolidate` / `burn` rows, and `phases_report` printing the consolidate tail (last consolidate end minus last model end; AC1), with `test-study_area_phases.R`.
- [x] Update the structural tests, then `bash -n` and shellcheck if installed (shellcheck is not installed on m1; `bash -n` clean on all five scripts).
- [x] Update the driver header (burn on each leg's end, the backup timing and why, `--keep-cyphers` = consolidate on finish without burning) and the bash ≥ 5.1 check.

## Phase 5: Live check on little groups (operator's ask)
- [x] **Run A:** dispatcher plus job1 and job2, from a worktree. Config `default`, scratch schema `fresh_smoke369`, `--buckets-exact`. Pick small groups from the 2026-10-23 minutes so that job1 ends first, job2 second and the dispatcher last. State the decisions, launch, and poll against a deadline.
- [x] Check Run A (all held except the verifiers: Run A failed on `link_sha` NULL from the worktree, fixed; they pass on Run C):
  - each cypher's burn ends before the dispatcher's model row ends (AC2);
  - `consolidate_state.tsv` has `ok` rows with `state_utc` inside the dispatcher's model window;
  - there is no `kept_hosts.tsv`;
  - `study_area_verify.sql -v schema=fresh_smoke369 -v expected_n=<N> -v run_uid=<uid>` and `data-raw/logs/provincial_246/verify_extra.sql` pass (AC3);
  - the overlapping dispatcher groups' minutes are compared with their 2026-10-23 minutes.
- [x] **Run B (negative):** one cypher in its own schema `fresh_smoke369b` (G11), with a future-dated log row for one of its groups seeded. Expect `dest_log_newer`, the host kept with a `kept_hosts.tsv` row and burn command, and a non-zero exit. Then burn it by its listed command and confirm doctl shows it gone.
- [x] Evidence goes in `data-raw/logs/consolidate_on_finish_369/`, with a README. Both scratch schemas are kept until merge and dropped on the operator's word.

- [x] **Run C** (added after Run A's provenance defect): Run A again at the final code into `fresh_smoke369` over Run A's builds; `study_area_verify.sql` PASS at `expected_n=18`, `verify_extra.sql` clean.

## Phase 6: Docs and release
- [x] RUNBOOK §8d: "Which host may be burned" (per-host consolidate and burn, `CONSOLIDATING` per host, the outcome-less rule, deferred overlaps, half-copied groups and what the recompute settles; A2) and "Where a run's time went" (per-host rows, `backup`, the consolidate tail). The backup timing and its real use (log history and pre-run rollback; A3).
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
