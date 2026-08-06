# Task: Run provenance log on persist schema (#127)

`<persist_schema>` tables accumulate rows across many runs but carry **no provenance**.
Given a network in the DB you cannot say which config produced it, what that config
actually said at the time, which primitive vintage it was built from, or when it was
written. Blocks #236 (DV-as-BT scenarios land indistinguishable in the same schema).

Mirrors `bcfishpass.log` + FK'd children that snapshot **actual parameter values**.

**Scope:** core only. `schema_consolidate.R` support is a follow-up PR (needs live fleet).

## Design decisions locked in planning

1. **`run_id text`, not `bigserial`** — `schema_consolidate.R` COPYs literal values
   between hosts whose sequences both start at 1 → PK violation → silent history loss.
   Generated R-side `<host>-<UTC ms>-<6 hex>`. Also avoids a `RETURNING` round-trip that
   would break the `.lnk_db_execute` mocking pattern.
2. **`ALTER TABLE … ADD COLUMN IF NOT EXISTS` at init** — `CREATE TABLE IF NOT EXISTS`
   silently no-ops on a drifted table, and config columns are the entire point. Bundles
   already differ (bcfp `dimensions.csv` 30 cols vs `default*` 32).
3. **`config_hash` hashes the resolved file set**, not `lnk_config_verify`'s declared set
   — `config.yaml` itself is absent from the `provenance:` block, so `schema`,
   `break_order`, `gradient_classes` would fall outside a verify-derived hash.
4. **Input provenance is read, not recomputed.** `bcdata.log` covers only `bc2pg`
   downloads (4 PSCIS tables) — **not FWA**. `fwa_stream_networks_sp` has empty
   `pg_stat_user_tables` entirely. Its real provenance is the **fwapg repo SHA**
   (loaded by fwapg's `load.sh` from bchamp objectstore parquet). Record what exists,
   NULL what doesn't. **No `count(*)` anywhere.**
5. **Dictionary-driven column lists** (updated for #233 / v0.44.3): drive both
   `cols_log_parameters_fresh` and `cols_log_dimensions` off
   `inst/extdata/configs/dictionary_parameters_fresh.csv` (19 rows) and
   `dictionary_dimensions.csv` (32 rows). Note `dimensions_columns.csv` no longer exists.
6. **Snapshot values stored as `text`** — provenance, not compute inputs; preserves the
   `""` vs `NA` distinction the CSVs use; immune to type drift.

## Phase 1 — primitives + hashing (no DB, unit-testable)

- [x] `DESCRIPTION`: move `digest` Suggests → Imports
- [x] `R/utils.R`: `.lnk_host()` honouring `LNK_HOST_ALIAS`; retrofit `lnk_baseline_append.R:88`
- [x] `R/utils.R`: `.lnk_wsg_persisted_all(conn, cfg)` (loose index scan + information_schema guard)
- [x] `R/lnk_log.R` (new): `.lnk_config_hash(cfg)`, `.lnk_run_id()`, `.lnk_fwapg_sha()`
- [x] `R/lnk_stamp.R`: `.lnk_pkg_git_dirty(pkg)`; extend `lnk_stamp()` additively
- [x] `tests/testthat/test-lnk_log.R`: hash stability/sensitivity, run_id format+uniqueness, host env var

## Phase 2 — DDL

- [ ] `R/lnk_log.R`: `cols_log`, `cols_log_input`; dictionary-driven
      `.lnk_cols_log_parameters_fresh()` / `.lnk_cols_log_dimensions()`
- [ ] `R/lnk_log.R`: `.lnk_log_align_columns()`, `.lnk_log_create_tables()`
- [ ] `R/lnk_persist_init.R`: wire in at all three sites (cols, CREATE, drift-check list)
- [ ] Tests: 4 CREATEs, `run_id text` PK, `text[]` cols, ADD COLUMN per column,
      dictionary covers the **union** of all bundle headers (bundles differ)

## Phase 3 — write path

- [ ] `.lnk_log_inputs()` — one batched `pg_class`/`pg_stat_user_tables`/`bcdata.log`
      LEFT JOIN, `bcdata.log` behind an information_schema probe; soft-fails
- [ ] `.lnk_log_config_snapshot()` — existence guard + `ON CONFLICT DO NOTHING`; shape
      guard warns and inserts intersection
- [ ] `.lnk_log_run_start()` (loud) / `.lnk_log_run_finish()` / `.lnk_log_run_fail()` (soft)
- [ ] Tests: open/finish/fail row shapes, dedupe on second snapshot, soft-fail on throw

## Phase 4 — wire into `lnk_pipeline_run`

- [ ] Three params (`run_label`, `notes`, `log`), three call sites, `on.exit()` + flag
- [ ] **Same commit:** update the exact-`calls`-vector mock list in `test-lnk_pipeline_run.R`
- [ ] Test: mid-phase throw → `log_fail` fired, `log_finish` not, error still propagates

## Phase 5 — read helper + docs

- [ ] Export `lnk_log_read(conn, cfg, aoi, latest)`
- [ ] `RUNBOOK.md`: audit query, no-backfill rule, env vars
- [ ] `NEWS.md` + DESCRIPTION bump (final commit)

## Validation

- [ ] `devtools::test()` green; `lintr::lint_package()` clean
- [ ] Live single-WSG smoke (PINE, already modelled → exercises re-run path)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
