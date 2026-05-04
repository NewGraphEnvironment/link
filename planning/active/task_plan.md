# Task: DB hygiene — drop working schemas after persist; drop worker schemas after consolidation (#118)

Today's `default_extrabreaks` provincial trifecta filled cypher's 96 GB disk and crashed its `fresh-db` container mid-run. Two coupled causes:

1. **Schemas accumulate.** Cypher carried `fresh` (Sun, ~25 GB) + `fresh_default` (yesterday, ~25 GB) + partial `fresh_default_extrabreaks` (today, ~30 GB) + ~60 `working_<wsg>` schemas (~10–15 GB) — none ever dropped after consolidation.
2. **Extras inflate per-row counts ~2.8×.** Capacity planning for `default` doesn't survive an `extras` overlay.

Workers are dispatched as one-shot ETL — once `pg_dump → scp → pg_restore` lands data on M4, the worker copy is dead weight.

**Approach:** orchestrator-level cleanup (in `compare_bcfishpass_wsg.R` + `consolidate_schema.R`), not in-package. Issue body's first option (drop in `lnk_pipeline_persist`) breaks the compare script's rollup query, which reads `<schema>.streams` + long-form `<schema>.streams_habitat` AFTER persist runs. Keep `lnk_pipeline_persist` scoped to one job; orchestrator owns the lifecycle.

## Phase 1: working_<aoi> cleanup in `compare_bcfishpass_wsg.R`

- [x] Add `cleanup_working = TRUE` parameter to `compare_bcfishpass_wsg()` signature.
- [x] After the rollup tibble is built and `stamp` is captured, before `return(out)`, add a `DROP SCHEMA <working> CASCADE` block guarded by `if (isTRUE(cleanup_working))`.
- [x] Brief comment explaining the cleanup contract: working schema's job done once rollup is computed and persistent rows are written.
- [x] Verify nothing else after the rollup query needs the working schema.
- [x] ADMS smoke. Rollup `identical()` TRUE vs pre-cleanup baseline; `working_adms` confirmed dropped post-run.
- [ ] `/code-check` on staged diff (after Phase 2 since both touch `data-raw/`).

## Phase 2: source schema drop in `consolidate_schema.R`

- [x] Add `keep_source = FALSE` parameter to `consolidate_schema()`.
- [x] After successful per-source `pg_restore` (rc == 0L), run `DROP SCHEMA <schema> CASCADE` against the SOURCE host via the same SSH/docker-exec pattern used for `pg_dump`.
- [x] Failure path: leave source schema in place if `pg_restore` failed (rc-guarded inside `if (!isTRUE(keep_source))`; warn-but-don't-fail on drop rc != 0).
- [x] Document the new default in roxygen.
- [ ] Manual smoke: deferred to next real consolidation (cypher needs fwapg reload first; defer with M1 only when doing a small test).
- [ ] `/code-check` on staged diff (with Phase 1).

## Phase 3: capacity planning note in `data-raw/README.md`

- [x] Add "Disk capacity per worker host" section: per-bundle footprint, extras 2.8× multiplier, 60 GB safe floor, cypher incident reference.
- [ ] Cross-link from `data-raw/logs/README.md` (combine with Phase 5 release commit).

## Phase 4: end-to-end regression

- [x] ADMS smoke (Phase 1): rollup `identical()` to pre-cleanup baseline, working_adms confirmed dropped.
- [ ] Multi-WSG single-host run + manual consolidation rehearsal — deferred to next real provincial run (cypher's fwapg needs reload first; 4-WSG smoke would be ~6 min wall but doesn't exercise consolidation since M4 is single-host).
- [x] Suite: 736 PASS / 0 FAIL.

## Phase 5: release

- [x] `NEWS.md` 0.29.0 entry (DB hygiene + cleanup contracts).
- [x] `DESCRIPTION` 0.28.0 → 0.29.0.
- [ ] PR body references #118 + SRED cross-ref.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
