## Outcome

Mapping_code tunnel decouple + portable build + `<type>_<role>` rename sweep. Shipped as v0.40.0 across 7 atomic commits (one per phase) on branch `187-mapping-code-build-decoupled-from-tunnel`. Closes link#187.

Key architectural deliverables:

1. **`lnk_mapping_code()` exported** — portable schema-aware build wrapping the existing `lnk_pipeline_mapping_code()` pure data transform. Explicit `table_<role>` args mean it works against working OR persist schema with no code change. Callable standalone to rebuild `streams_mapping_code` against persist data with the tunnel down — the QGIS bcfp-symbology use case that motivated the issue.

2. **Persist `streams_access` + `streams_mapping_code` + `streams_habitat_long_vw` view** — added to `lnk_persist_init()` + `lnk_pipeline_persist()`. Per-species columns generated dynamically from the bundle's species set. The long-form habitat view is the `UNION ALL` shape `lnk_mapping_code()` consumes (per-species split tables already hold the data; VIEW costs zero storage).

3. **`lnk_pipeline_run(mapping_code = TRUE)` phase** — new optional phase between `lnk_barriers_unify` and `lnk_pipeline_persist`. Calls `lnk_barriers_views` over working `<schema>.barriers` (tunnel-free, link-canonical), `lnk_pipeline_access`, `lnk_mapping_code`. Methodology shift surfaced during the work: ACCESS now uses link's own per-species barriers (via the `blocks_species` predicate from link#152) instead of bcfp's barriers tables staged via the tunnel. Parity diff vs `bcfishpass.streams_mapping_code` becomes more meaningful (real link-vs-bcfp divergence surfaces; artificially suppressed before).

4. **`lnk_compare_wsg` refactored** — build delegated to `lnk_pipeline_run`; only the diff stays in compare. `.lnk_compare_wsg_mapping_code_diff()` rewritten to read from `<persist_schema>.streams_mapping_code`. Two orphan helpers deleted (~200 lines simpler).

5. **Rename sweep with deprecation shims**:
   - R API: `with_mapping_code` → `mapping_code` (`lnk_compare_wsg`, `lnk_pipeline_run`).
   - R API: `<role>_species` → `species_<role>` (`lnk_pipeline_mapping_code` × 3 params).
   - CLI: `--with-mapping-code` → `--mapping-code` (5 shell scripts + 1 R driver).
   - Old names accepted for one release with `.Deprecated()` / stderr warnings. Removal in v0.41.0.

Bugs caught and fixed by `/code-check` rounds during implementation:
- Phase 2: Phase 1's `cols_streams_access_base` included two conditional columns that `lnk_pipeline_access` only writes when remediations/observations are passed → INSERT would have failed → dropped.
- Phase 4: missing roxygen `@param`s for new args.
- Phase 5: stale tests referenced deleted helper → rewrote to mock the diff function.
- Phase 6: local result var `mapping_code` shadowed the renamed param → renamed to `mc_stats`. Body refs still used old `<role>_species` names → caught + fixed.

Tests: 1119 PASS / 0 FAIL throughout. `devtools::check()`: no new warnings vs v0.39.1 baseline.

Follow-up filed:
- **#189** — Data-drive species residence categorization from `dimensions.csv`. Unblocks custom species mixes (sea-run cutthroat, Dolly Varden, future regional studies) without monkey-patching function defaults.

Live smoke (`bash data-raw/wsgs_run_m4_offline.sh --wsgs=PARS --mapping-code`) deferred to next operational run — pre-merge `devtools::check()` + 1119-test suite + 6 atomic-commit code-check rounds are the in-band acceptance.

Closed by: commit `970b293` (Release v0.40.0) / PR #TBD
