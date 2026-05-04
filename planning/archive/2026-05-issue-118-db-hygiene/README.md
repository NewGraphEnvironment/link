## Outcome

Two-tier orchestrator-level cleanup landed: `compare_bcfishpass_wsg(cleanup_working = TRUE)` drops `working_<aoi>` CASCADE after the rollup tibble is built; `consolidate_schema(keep_source = FALSE)` drops the source schema on each remote host after a successful pg_restore. Both default-on with explicit opt-out flags. `data-raw/README.md` documents per-worker disk capacity (60 GB safe-floor for one in-flight bundle) with the 2026-05-04 cypher disk-full incident as the cautionary tale. Bit-identical bcfp parity preserved on ADMS smoke (rollup `identical()` to pre-cleanup baseline).

Approach choice during plan-mode review: rejected the in-package option (drop in `lnk_pipeline_persist`) because the rollup query reads working schema in long-form AFTER persist returns, and the persistent schema is wide-per-species (`streams_habitat_<sp>` without `species_code`). In-package drop would have forced a rollup rewrite to wide format. Issue body's parenthetical alternative ("or as the final step of `compare_bcfishpass_wsg`") was the cleaner shape.

Verification deferred: cross-host consolidation rehearsal (M1 → M4 source-drop) needs cypher's fwapg reloaded first; small ADMS-only smoke through M1 will catch any regression at the next real provincial run.

Closed by: PR [#120](https://github.com/NewGraphEnvironment/link/pull/120) (squash `56e99f3`), v0.29.0.
