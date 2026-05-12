## Outcome

Shipped `<persist_schema>.barriers` — a province-wide unified barriers table with `blocks_species text[]` predicate — and routed `barrier_sources$anthropogenic` + `barrier_sources$dams` in `lnk_pipeline_access` to VIEWs over it. **PARS BT mapping_code parity closed from 60.64% → 98.63% (+38 pp).** Dams in upstream-of-PARS WSGs (Bennett in PCEA, Peace Canyon / Site C in UPCE) now resolve correctly via FWA-topology walks across the province-wide table; per-WSG `WHERE watershed_group_code = 'PARS'` scoping is gone for the affected sources.

Three new exports: `lnk_barriers_unify` (4-source UNION ALL into per-WSG staging), `lnk_barriers_views` (per-species + per-source `_unified`-suffix VIEWs over the persist table), plus DDL/persist extensions to `lnk_persist_init` + `lnk_pipeline_persist`. Architecture mirrors the existing `streams` / `streams_habitat_<sp>` persistence pattern (single `cols_barriers` source of truth, idempotent DELETE-WHERE-WSG + INSERT). Source-typed working-schema tables emitted by `lnk_barriers_emit` are kept intact — useful primitives, no removal. Per-species local-only barriers (replacing the bcfp-tunnel staging in `barriers_per_sp`) is deferred to a follow-up: the unified `blocks_species` predicate doesn't capture per-species minimal-position semantics.

Phase A results (6 WSGs, source log `data-raw/logs/202605111557_phase_a_FINAL_link152.txt`): ADMS 99.00-99.99, BULK 99.18-99.78, WILL 98.86-99.93, PCEA 99.93/100, UPCE 99.91/100, PARS 98.63/100. All in-WSG species ≥99% maintained on the non-PARS WSGs; PARS BT residual non-cross-WSG drift only.

Closed by: Release v0.35.0 (commit f7e5f96) / PR #TBD
