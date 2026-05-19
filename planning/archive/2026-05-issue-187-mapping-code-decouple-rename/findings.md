# Findings — mapping_code tunnel decouple + lnk_mapping_code portable build + rename sweep (#187)

## Issue context

`streams_mapping_code` build coupled to `lnk_compare_wsg` tunnel path. Build itself (`lnk_pipeline_mapping_code()`) is tunnel-independent — pure data transform. Coupling is structural, not technical. Mapping_code lands in working schema, not persist — QGIS bcfp views need persist.

## Codebase confirmation (2026-05-19)

- `R/lnk_pipeline_mapping_code.R:81` — function signature: pure data transform on `access`, `habitat`, `feature_code`, `presence`. No tunnel deps.
- `R/lnk_compare_wsg.R:540-616` — inline assembly (lnk_pipeline_access call + habitat pivot + feature_code query + lnk_pipeline_mapping_code call). This is what extracts into `lnk_mapping_code()`.
- `R/lnk_compare_wsg.R:594` — hardcoded `bcfp_species` enumeration. Goes away (uses function defaults / species args).
- `R/lnk_compare_wsg.R:618-620` — `.lnk_compare_wsg_mapping_code_diff` is the tunnel-bound piece (queries `bcfishpass.streams_mapping_code`).
- `R/lnk_persist_init.R:11/36/57` — existing `cols_streams` / `cols_habitat` / `cols_barriers` pattern. Add `cols_streams_access` + `cols_streams_mapping_code` to the family.
- `R/lnk_pipeline_persist.R:50-99` — existing DELETE-WHERE-WSG + INSERT pattern for streams / streams_habitat_<sp> / barriers. Extend to streams_access + streams_mapping_code.
- `R/lnk_pipeline_run.R:1-40` — phase order documented. New `mapping_code = TRUE` phase inserts between phase 8 (species) and phase 9 (persist_init).
- Working schema has long-form `streams_habitat` (id_segment, species_code, spawning, rearing). Persist has per-species split (`streams_habitat_<sp>`). VIEW `streams_habitat_long_vw` (UNION ALL across per-species) unifies the shape.

## Design decisions (plan review with user)

### Function name: `lnk_mapping_code` (not `lnk_mapping_code_build`)

Noun-only per `lnk_thresholds` / `lnk_config` / `lnk_source` precedent in link. Build action implicit. Reads as "the mapping_code for these inputs."

### Function args: explicit `table_<role>` (Option B), not schema-aware (Option A)

Picked B over A on:
1. **YAGNI**: A's "savings" are 4 lines of boilerplate per caller; B's clarity gain is permanent.
2. **NGE `table_<role>` convention** already established (`lnk_match`, `lnk_pipeline_access`, `lnk_load`).
3. **Build-out resilience**: schema-aware bakes layout into function body; explicit args isolate.

User-quoted rationale: "Much easier to code and less likely to snag the build out to this core functionality."

### Persist `streams_access` AND `streams_mapping_code`

User: "Access persistence no doubt. For sure." Enables true portability of `lnk_mapping_code` to persist schema (ad-hoc rebuild from persist data, no full pipeline re-run).

### Drop `bcfp_species` everywhere

User: "bcfp_species? What does bcfp have to do with this?" Right — that name was leakage from `lnk_compare_wsg`'s purpose. The build doesn't care about bcfp. Function uses `species_resident` + `species_anadromous` + `species_spawn_only` pass-through (matches existing `lnk_pipeline_mapping_code` semantics).

### B1 (VIEW) for long-form habitat, not B3 (materialized)

User: "What cols would be on B3? Is that data also elsewhere?" — yes, the data is already in per-species tables. B3 (materialized long-form) would 100% duplicate. B1 (VIEW) is strictly better.

### `species_<role>` naming per `<type>_<role>` convention

User: "Name params species_* as per our convention." Extends documented `col_<role>` / `table_<role>` / `exp_<role>` family. Rename `lnk_pipeline_mapping_code`'s existing `resident_species` / `anadromous_species` / `spawn_only_species` params with deprecation shim.

### Species residence data-drive deferred to #189

User: "Also file that issue in fresh and link (or wherever it needs to be) to get the species_* derived dynamically." Filed as link#189. Tour-driven motivation: sea-run cutthroat, Dolly Varden, future species mixes.

## Architecture target

```
lnk_mapping_code(conn, table_access, table_habitat, table_streams, aoi,
                  table_to = NULL, presence = NULL,
                  species_resident = c("bt","wct"),
                  species_anadromous = c("ch","cm","co","pk","sk","st"),
                  species_spawn_only = c("cm","pk"))
  └─ Queries table_*, pivots habitat, calls lnk_pipeline_mapping_code, writes table_to

lnk_pipeline_run(..., mapping_code = FALSE)
  └─ when TRUE: lnk_pipeline_access + lnk_mapping_code inserted before persist_init phase

lnk_compare_wsg(..., mapping_code = FALSE)
  └─ delegates build to lnk_pipeline_run; reads diff from <persist_schema>.streams_mapping_code
```

## Rename sweep surface (7 in-tree files)

`R/lnk_compare_wsg.R`, `R/lnk_pipeline_mapping_code.R`, `data-raw/wsgs_run_host.R`, `data-raw/wsgs_run_pipeline.sh`, `data-raw/wsgs_dispatch.sh`, `data-raw/wsgs_run_m4_offline.sh`, `data-raw/trifecta_smoke.sh`, `data-raw/README.md`. Logs immutable.

## Out of scope (filed)

- link#189 — Data-drive species residence from dimensions.csv (filed 2026-05-19).
- link#175 — `lnk_compare_mapping_code` family member (unblocked by this PR).
- link#176 — `lnk_compare_wsg` → `lnk_compare_run` rename.
