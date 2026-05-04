# Task: DB hygiene — drop working schemas after persist; drop worker schemas after consolidation (#118)

Today's `default_extrabreaks` provincial trifecta filled cypher's 96 GB disk and crashed its `fresh-db` container mid-run. Two coupled causes:

1. **Schemas accumulate.** Cypher carried `fresh` (Sun, ~25 GB) + `fresh_default` (yesterday, ~25 GB) + partial `fresh_default_extrabreaks` (today, ~30 GB) + ~60 `working_<wsg>` schemas (~10–15 GB) — none ever dropped after consolidation.
2. **Extras inflate per-row counts ~2.8×.** Capacity planning for `default` doesn't survive an `extras` overlay.

Workers are dispatched as one-shot ETL — once `pg_dump → scp → pg_restore` lands data on M4, the worker copy is dead weight.

**Approach:** orchestrator-level cleanup (in `compare_bcfishpass_wsg.R` + `consolidate_schema.R`), not in-package. Issue body's first option (drop in `lnk_pipeline_persist`) breaks the compare script's rollup query, which reads `<schema>.streams` + long-form `<schema>.streams_habitat` AFTER persist runs. Keep `lnk_pipeline_persist` scoped to one job; orchestrator owns the lifecycle.

## Phase 1: working_<aoi> cleanup in `compare_bcfishpass_wsg.R`

- [ ] Add `cleanup_working = TRUE` parameter to `compare_bcfishpass_wsg()` signature.
- [ ] After the rollup tibble is built and `stamp` is captured, before `return(out)`, add a `DROP SCHEMA <working> CASCADE` block guarded by `if (isTRUE(cleanup_working))`.
- [ ] Brief comment explaining the cleanup contract: working schema's job done once rollup is computed and persistent rows are written.
- [ ] Verify nothing else after the rollup query needs the working schema.
- [ ] ADMS smoke. Confirm rollup byte-identical to v0.28.0 baseline, and `\dn working_adms` returns 0 rows post-run.
- [ ] `/code-check` on staged diff.

## Phase 2: source schema drop in `consolidate_schema.R`

- [ ] Add `keep_source = FALSE` parameter to `consolidate_schema()`.
- [ ] After successful per-source `pg_restore` (rc == 0L), run `DROP SCHEMA <schema> CASCADE` against the SOURCE host via the same SSH/docker-exec pattern used for `pg_dump`.
- [ ] Failure path: leave source schema in place if `pg_restore` failed.
- [ ] Document the new default in roxygen + the data-raw README inventory entry.
- [ ] Manual smoke: run with a small synthetic schema on one host, verify source dropped.
- [ ] `/code-check` on staged diff.

## Phase 3: capacity planning note in `data-raw/README.md`

- [ ] Add "Disk capacity per host" section: per-bundle footprint, extras 3× multiplier, recommended minimum free disk per worker (60 GB safe floor), today's cypher incident as cautionary tale.
- [ ] Cross-link from `data-raw/logs/README.md`.

## Phase 4: end-to-end regression

- [ ] M4-only single-host provincial run on `default` bundle (no trifecta needed) — verifies Phase 1 cleanup. Acceptance: zero `working_*` schemas post-run; rollup RDS byte-identical on a small WSG sample (ADMS, BABL, BULK).
- [ ] Manual consolidation rehearsal on M1: pg_dump small schema → restore on M4 → verify M1's source schema dropped. Verifies Phase 2.
- [ ] Defer full 3-host trifecta verification until next planned provincial run (cypher needs fwapg reload anyway).
- [ ] Stamped log under `data-raw/logs/<TS>_link118_regression.txt`.

## Phase 5: release

- [ ] `NEWS.md` 0.29.0 entry (DB hygiene + cleanup contracts).
- [ ] `DESCRIPTION` 0.28.0 → 0.29.0.
- [ ] PR body references #118 + SRED cross-ref (`Relates to NewGraphEnvironment/sred-2025-2026#24`).

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
