# Progress — mapping_code tunnel decouple + lnk_mapping_code portable build + rename sweep (#187)

## Session 2026-05-19

- Plan-mode exploration: read `R/lnk_pipeline_mapping_code.R`, `R/lnk_compare_wsg.R:540-620`, `R/lnk_persist_init.R`, `R/lnk_pipeline_persist.R`, `R/lnk_pipeline_run.R`. Grepped 7-file rename surface.
- Plan iterated three times with user on design decisions:
  - **Option B (explicit `table_<role>` args)** picked over schema-aware on YAGNI + convention + build-out resilience.
  - **`lnk_mapping_code`** (no `_build` suffix) per noun-only precedent.
  - **Drop `bcfp_species`** everywhere — it was compare-leakage.
  - **B1 (VIEW)** for long-form habitat, not B3 (materialized) — data already exists in per-species tables.
  - **`species_<role>` param naming** per `<type>_<role>` convention; rename existing `lnk_pipeline_mapping_code` params with deprecation shim.
  - **Persist both streams_access + streams_mapping_code** — enables ad-hoc rebuild.
- Filed link#189 (data-drive species residence from dimensions.csv).
- Created branch `187-mapping-code-build-decoupled-from-tunnel` off main (current at `99795da` v0.39.1).
- Scaffolded PWF baseline.
- Next: Phase 1 — schema additions to `lnk_persist_init`.
