# Plan review (#308), 2026-10-14 — Plan agent, returned as reply text and filed here

Findings (ranked) and their disposition. The review is relayed in full in the session transcript; this file keeps the actionable list.

| id | finding | disposition |
|---|---|---|
| B1 | Thresholds logged only for DUNC's hash; `fresh` has no thresholds table, so ratios NA for 4/5 default and 39/39 bcfishpass groups | Kept NA, made explicit: `thresholds_logged` per hash in the manifest, a sentence in the YAML, and the pilot reports it. Re-running groups is an operator choice outside this PR |
| B2 | PUBLISH "delete keys the manifest no longer names" would delete `provenance/`, `config/` and other configs' parts | Delete only under `segment/`; `provenance/` and `config/` put-if-absent; export carries forward configs it does not re-export from the previous manifest in `root` |
| G1 | `streams_habitat_<sp>.accessible` predates the cross-WSG recompute; the recompute rewrites `streams_access` only | Add `has_barriers_dnstr` (from `streams_access.has_barriers_<sp>_dnstr`, the output that ships) beside `accessible`; add `log_recompute` rows to runs and provenance. **Decision to confirm in the PR** (column contract) |
| G2 | Unmodelled species emitted as all-FALSE conflates "not modelled" with "modelled, none" | Rows only for the species each group's run logged; a logged species with no habitat rows is refused |
| G3 | Issue's manifest field `model` silently dropped | Per-run `model` from the bundle's method table when the bundle hash matches, else null |
| G4 | Latest-row semantics; `notes` is not a failure marker on its own (override justifications land there, #227) | Keep newest-row rule (any config), refuse open rows and other-config rows; check `schema_persist`; carry `link_dirty` (PUBLISH gate on dirty/test labels is the follow-up with the run_uid gate) |
| G5 | `wsgs = NULL` undefined | Already "finished builds of the config"; manifest now lists `skipped` groups with reasons |
| G6 | Multi-schema segmentation | Already refused (one schema per group); `shared_segmentation` only across configs. No default for `configs` (none in code) |
| G7 | run_uid provenance must be the whole dispatch | Already so (`WHERE run_uid = …` over the schema's log) |
| G8 | `source_artifact` is this database's current record, not the run's | Labelled as such in the manifest (`source_artifact_scope`) |
| G9 | `config/<hash>/` must hold every hashed file | Already: `.lnk_config_files()` is the hash's own list; test re-hashes each file |
| G10 | Loader tests would write the real table | `table =` argument |
| A1–A4 | Discharge agreement scoped to an unchanged table; ratios against CSV thresholds not rule overrides; `accessible_ratio_gradient` semantics; species case | Documented in the YAML notes; key parser enforces upper-case species |
| O1 | duckdb Suggests too late | Done in Phase 2 |
| O3 | Fill subquery per (WSG, species) | Accepted for now; noted |
| AC1 | Pilot check against the same join is circular | Compare against `lnk_rollup_wsg()` |
| AC2 | Extra tests | Added where the behaviour exists |
