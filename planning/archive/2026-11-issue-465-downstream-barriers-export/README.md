## Outcome

A one-group run on a machine that holds only some watershed groups can now read, from the habitat export, every persisted `barriers` and `barrier_overrides` row its downstream access walk reads. The export carries both tables one part per group per config (`group_parts`), the line-rule dependency map (`dependencies`, the query moved into `R/lnk_wsg_deps.R` and shared with `recompute_deps.R`), each config's `scope` and `barrier_holders`, and per-build input identities: CABD and PSCIS by a content md5 the loader now records (`provenance.source_artifact.content_md5`, carried into `log_input`), snapshotted province-wide only for builds whose md5 the exporting database still holds; observations and modelled crossings by version id. `lnk_downstream_files()` lists what a target needs; `lnk_downstream_load()` checks, loads and records it. Exploration corrected the issue twice (the walk reads overrides too; the outlet path misses readers), and the plan review reversed the first snapshot design (per-group slices of CABD and PSCIS cannot be cut outside a run, and the builds ran on five hosts' loads), which the operator re-decided at the gate. Released as 0.80.0.

## Measurement

- Line rule moved into `R/`: `recompute_deps.R` output byte-identical before and after (`line` 2,211 pairs over 208 groups; `all` `d4a9fdda…`).
- Every `fresh_default` barrier (7,749,648) and override (44,069) row sits on a line its own group touches in FWA: the line rule covers what a walk reads.
- Round trip on m1, BULL with 11 dependencies (closure: 2): export-loaded = SQL-copied control = provincial build, md5 over 20,791 rows in `streams`, `streams_access`, `streams_mapping_code`. Without the downstream rows 341 segments lose `has_barriers_dams_dnstr` and 94 BT/WCT mapping codes change; no `access_*` moves. Without overrides nothing moves for BULL, because it holds its own copies (268; 60 dependency rows within 1 m of one) — so the overrides round trip rests on the unit tests.
- Wrong turns kept: the first override probe joined on exact measure and found none below any target (override positions sit within 1 m of their barrier: 1,681 of 44,069 exact); two e2e tries stopped on a loader report bug and an unquoted env value.
- Defects the tests found: `duckdb::duckdb_register()` reads an `integer64` column's bits as a double (703016261 → 3.5e-315, silent), so `bigint` goes as text; the "not read" rule keyed on the table rather than the input; `.lnk_table_exists()` cannot see `pg_temp`.
- `/code-check branch`: 4 rounds (2 fragile; 1 bug inside round 1's fix + 1 fragile; 1 bug + 1 fragile on the named mechanism; clean), ended on a 43-place enumeration. Mechanism: a guard took its scope from what the producer listed while the consumer asked about a wider set; a full provincial build makes the lists agree.

## Evidence

`data-raw/logs/downstream_export_465/` (its README indexes the line-rule identity, the superset check and the e2e arms).

## Owed

- The first PUBLISH carrying the new datasets (outward-facing; on the operator's word)
- The pre-run gate runs again before the next provincial run (`R/` changed)
- Follow-up issue: load input snapshots into the primitive tables
- #464 reads the same dependency rule (comment there, not done here)
- Follow-up issue: a partial-database arm (only the target's and its dependencies' FWA)
- Re-snapshot primitives on the provincial hosts before the next run so builds carry the CABD / PSCIS content md5

Closed by: PR for #465 (branch `465-export-persisted-barriers-and-input-snap`)
