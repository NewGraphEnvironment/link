# Plan review: move 5 (#473)

Plan agent, read-only, 2026-11-17 (spawned 01:03 UTC). Findings as returned; dispositions in task_plan.md.

## Blockers

- **B1.** #423 adds a column to the v1 contract, but `lnk_db_load()` takes its columns from the installed package (`.lnk_export_cols()`, R/lnk_db_load.R:69) and stops on any part, or existing table, with other columns (:85-90, :109-112: "A new column contract belongs in a new table (a new dataset version)"). New link cannot load the 2026-11-14 published parts until a republish, and a loaded `habitat.fwa_v1_segment` errors. Pick (a) v1 additive (read `datasets[].schema.cols` from the manifest, add the column to an existing table) or (b) a new dataset version (v2), and test against an old-contract tree and an existing table.
- **B2.** #464's "streams loaded" must mean FWA (`whse_basemapping.fwa_stream_networks_sp`), not the persist schema's `streams`; the latter would refuse every DS-first run (RUNBOOK §8c says the dependencies' FWA).

## Gaps

- **G1.** The closure's `tryCatch(..., error = function(e) character(0))` (:495-497) turns a failed closure into a pass; it must refuse.
- **G2.** `lnk_wsg_resolve()` calls `frs_wsg_drainage(conn, focal)` with default outlets (R/lnk_wsg_resolve.R:132), ignoring the check's `outlets`; call `frs_wsg_drainage(conn, aoi, outlets)` and species-filter in the check.
- **G3.** The test DB holds all 246 groups: test #464 with mocks (a closure holding a fake group `ZZZZ`, no dams), red today, green after.
- **G4.** Unloaded groups need their own result field (`wsgs_unloaded`), fix text and note wording, apart from `wsgs_missing` (unpersisted dams).
- **G5.** #461 does not reproduce on the full local fwapg (dam snap 0.34 s by EXPLAIN ANALYZE; drainage 0.01 s). Name the partial database and allow the fix to be a precondition. `outlets` is a lazy default forced inside the probe: force it before timing.
- **G6.** Equality proof too weak: compare status, dams (ids and order), `wsgs_missing`, note; run fail (a cfg whose schema has no `barriers`) and override; cover SLOC/KOTL under `default` (placeholders) and the xref'd dam; ideally sweep all 246 groups.
- **G7.** A cache conflicts with the guard being read-only. Compute the closure first and restrict `cabd.dams` to the closure groups' `fwa_watershed_groups_poly` plus 65 m before the snap.
- **G8.** `crt_registry_entry()` is not exported by crate; read `system.file("extdata/schemas/nge/habitat/fwa/v1/segment.yaml", package = "crate")` with `yaml::read_yaml`.
- **G9.** `contract_md5` hashes link's YAML path (R/lnk_scenario_export.R:874-875; test :631); prefer an md5 over names and types, and record crate's version in `exported_by`.
- **G10.** A crate tag URL from a dev install (x.y.z.9000) cites no tag: assert a released crate, or pin to the floor. Fill the registry row's `canonical_cols`.
- **G11.** `.lnk_manifest_previous()` carries other configs' old parts under one `datasets[].schema` (:1310-1355, :645-653); refuse carry-forward across a contract change, or re-export all configs.
- **G12.** `streams_md5`: list `cols_streams` explicitly (R/lnk_persist_init.R:11-33), order by `id_segment`, pin float text (`extra_float_digits`) or hash binary, hash per row then aggregate, decide missing columns, version-prefix (`v1:`). Verified: nothing rewrites `streams` after `.lnk_log_run_finish()`; consolidate's text COPY keeps EWKB and floats exact.
- **G13.** versionId: skipped group parts produce no put-object output; use `head-object --query VersionId --output text`; rewrite local manifest atomically before uploading it; the manifest cannot carry its own VersionId (RUNBOOK: pin it through `list-object-versions`); assert versioning `Enabled`.
- **G14.** `lnk_catalog()` drops `version_id` (R/lnk_catalog.R:52-59) and fetches by key only (`.lnk_part_fetch()`, `.lnk_s3_cp()`); expose it and fetch with `--version-id`.
- **G15.** PUBLISH gates in an R/ helper (`.lnk_publish_refusals(m)`) inside the pre-write block (:145-175); also cover the exporter's own `exported_by.link_dirty`, recompute rows (`log_recompute.run_uid` / `link_dirty`), `group_parts`, `fresh_dirty`.

## Ordering

- **O1.** crate's next release is 0.19.0 (0.18.0 is released). The YAML must be final before it is copied to crate; the crate PR merges and releases before link's floor bump passes CI.
- **O2.** Take #461's "before" baseline before reordering the closure ahead of the probe.

## Assumptions

- **A1.** The closure is focal + downstream groups (outlets and `fwa_downstream`, no table reads; works on a partial DB). It over-approximates along split main stems (NECR: TWAC and NARC), and is species-filtered, consistent with the dam filter.
- **A2.** `access_<sp>` in `fresh_default` takes 0, 1, 2 and NULL; -9 cannot reach a real part (export emits `log.species` only). A lifting recompute turns 0 into 1, not 2 (R/lnk_access.R:233-236).
- **A3.** `configs[].runs[]` already carries the four tokens (`SELECT *` from `log`); the new work is a config-level summary. All 241 local builds have `run_uid`, clean trees and tokens.

## Scope

- **S1.** #334's "test-looking `run_label`s" gate is dropped without a word; record it.

## Acceptance

- #461 needs a target and a definition of "same"; the consolidate-copy digest check needs a mechanism (a COPY round trip into a scratch schema) or moves to owed; Phase 3 also loads the old 2026-11-14 tree, an existing table, and a mixed-config root.
