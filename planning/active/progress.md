# Progress — link#65

## Session 2026-04-29

- Reviewed issue #65 body vs current `lnk_config()` state — surfaced overlap
- Weighed Path A (parallel function), B (unify into lnk_config), C (split manifest from data)
- Chose Path C, single PR, v0.18.0 bump (no backwards-compat shim — zero external consumers)
- Updated #65 body with resolution preamble + acceptance criteria; preserved original below
- Branched `65-config-manifest-data-split`
- Wrote PWF baseline (this file + task_plan + findings)
- Next: Phase 1 — DESCRIPTION + crate verification + pre-refactor parity baseline

### Pre-refactor baseline captured (2026-04-29)

`tar_make()` on 5 WSGs × 2 configs against link v0.17.0 (post-#77 csv-sync state):

- Run time: 18m 45s
- Rollup: 357 rows
- **Digest (parity gate):** `sha256:a82de9928809b9751213e08916c476b4ee3f99286bc9ea2dc53f9659eeb92097`
- Log: `data-raw/logs/20260429_01_baseline_pre_65_tarmake.txt`

Post-refactor `tar_make()` must reproduce this exact digest. Any drift = refactor introduced behaviour change; investigate before merge.

### Phase 2-6 done (2026-04-29)

- Both `inst/extdata/configs/{bcfishpass,default}/config.yaml` rewritten to new schema (top-level `rules:`/`dimensions:`, flat `files:` map keyed by filename stem)
- `R/lnk_config.R` rewritten manifest-only with `extends:` resolver
- `R/lnk_load_overrides.R` new — dispatches via `crate::crt_ingest()` for canonical_schema entries, falls through to extension-based local read otherwise
- All 8 pipeline-phase R files migrated to take `loaded` alongside `cfg`
- Test suite: 608 passing, 0 failing
- Lints clean (only repo-conventional style notes)

### Phase 6.5: crate-side type-cast fix (2026-04-29)

First post-refactor `tar_make()` errored on ELKR with `fwa_upstream(...)` function-not-found. Root cause: crate's handler emits readr-default `numeric` types for columns declared as `integer` in the canonical schema YAML. Local DB columns then end up `double precision`, fwa_upstream's integer-typed signature fails to dispatch.

**Initial patch (rejected as scab):** hand-coded a `bcfp_uhc_cast_canonical()` helper inside the `internal_bcfp_user_habitat_classification` handler that listed columns to cast. User flagged this — the schema YAML already declares types; crate should be reading them.

**Proper fix:** schema-driven type enforcement at the `crt_ingest()` core. Generic; reads `canonical.cols[].type` from the schema YAML and coerces handler output. Every registered (source, file_name) pair gets type enforcement for free; handlers stay focused on shape transforms.

**Naming:** initial draft used `apply_canonical_types(df, schema)` + `coerce_to_canonical()` helper — verb-first names violating soul's `noun_verb-detail` convention (which `registry_load.R` already follows in crate). Renamed to **`schema_apply(df, schema)`** to mirror `registry_load`'s shape and dropped the helper (one call site, inline switch is clearer).

Tests added: `test-schema_apply.R` (6 tests). Total crate tests: 45 passing.

**Crate change set (separate PR in crate repo):**
- `R/schema_apply.R` (new) — schema_apply()
- `R/crt_ingest.R` — 1-line addition: call `schema_apply(result, schema)` after handler returns
- `R/internal_bcfp_user_habitat_classification.R` — clean (no per-handler type code; hand-coded helper removed)
- `tests/testthat/test-schema_apply.R` (new)
- `man/schema_apply.Rd` (regenerated)

### Re-running tar_make for parity verification

- Run 1: `data-raw/logs/20260429_03_post_65_tarmake.txt` — crate `0.0.0.9000` (with my schema_apply pre-Convention-C). Digest **matched** baseline.
- Run 2: `data-raw/logs/20260429_04_post_65_tarmake_crate_v002.txt` — crate `0.0.2` (Convention C; `crt_schema_validate` + `crt_schema_apply`). Digest **matched** baseline.

Both runs produce bit-identical `sha256:a82de9928809b9751213e08916c476b4ee3f99286bc9ea2dc53f9659eeb92097` rollup. Refactor is parity-preserving against v0.17.0.

### crate side: Convention C re-implementation (2026-04-29)

Process slip: Claude (link session) committed `schema_apply` directly in the crate repo without comms-first design alignment. Crate-Claude flagged this. Outcome:

- Local crate branch `65-schema-driven-types` (commit `6764fd9`) abandoned (never pushed)
- crate session re-implemented as Convention C (`crt_*` prefix on all symbols, family-namespaced) and shipped as v0.0.2 ([crate#5](https://github.com/NewGraphEnvironment/crate/pull/5) closing [crate#4](https://github.com/NewGraphEnvironment/crate/issues/4))
- crate v0.0.2 adds `crt_schema_validate` (NEW required-cols check) on top of Claude's original schema_apply scope
- link picks up v0.0.2: DESCRIPTION bumped to `crate (>= 0.0.2)`, comms thread closed

### Attribution scope

Filed [link#78](https://github.com/NewGraphEnvironment/link/issues/78) — NOTICE / per-bundle LICENSE-bcfishpass / README acknowledgements. Out of scope for #65; deferred to its own PR.
