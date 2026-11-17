# Task: Backlog move 5: The habitat export's contract, and one-group runs that read downstream (#473)

**If we do it:** the export carries code 2, its column contract lives in crate, publishing refuses a build it cannot trace, and a one-group run reads its downstream groups' barriers or refuses. **If we never do:** a one-group run on a partial database ignores every dam downstream, and a consumer can pin a build nobody can reproduce.

## Context

Move 5 of `planning/backlog.md`: batch 6 (the habitat export's contract: #423, #333, #334; #465 already landed in PR #483) and batch 7 (the downstream check: #464, #461). It is one PR with one phase per batch. Move 2 (#470) merged as 0.84.0 (`acc-v6`) on 2026-11-17 and touched none of this move's files, so this branch is cut from that tip.

What exploration found:
- The export was published on 2026-11-14 at 0.82.0 to `s3://fresh-bc/habitat/fwa/v1/` (108 segment parts, 482 group parts), and fresh-bc **bucket versioning is already Enabled**. #334's "history" item is half done: S3 keeps versions, and the manifest does not name them.
- `.lnk_export_rows()` (`R/lnk_scenario_export.R:121`) already joins `streams_access` for `has_barriers_<sp>_dnstr`. The access code is one more column off the same join.
- `.lnk_manifest_write()` (`:636`) cites `inst/extdata/schemas/habitat_fwa_v1_segment.yaml` in link. crate (0.17.0) registers wet's discharge contracts as `nge/discharge/fwa/v1/*` `schema_only` rows, in the same YAML shape, so #333 is a copy.
- `lnk_wsg_downstream_check()` (`R/lnk_wsg_downstream_check.R`) takes CABD dams as candidates only through `JOIN fwa_stream_networks_sp`, so on a partial database an unloaded downstream group gives an empty set and `pass` (#464). The closure from `lnk_wsg_resolve(expand = TRUE)` (`fresh::frs_wsg_drainage()`, outlet points, no stream table) already names the downstream groups. Which step costs the 371 s (#461) is not known: candidates are the 65 m lateral KNN snap over every CABD dam (`.lnk_dams_matched_sql()`), `frs_wsg_drainage()`, and `frs_wsg_outlets()`.

## Decided at the gate (operator, 2026-11-17)

- Both batches in this PR (move 2 has merged).
- #423's column is the **integer `access` code** as persisted (0, 1, 2, -9), one per segment, config and species row. The manifest records each config's `acc` token, so a reader knows which rule made code 2.
- **The contract stays `habitat/fwa/v1`, additively** (after the plan review's B1): the loader reads each tree's columns from its manifest, loads an older part with `access` NULL, and adds the column to an existing table.
- #466 (receipt.json) stays on the provenance track. This move adds only the token summary and the crate schema URL to the manifest.
- #334 in this PR:
  - PUBLISH refuses a part whose builds have no `run_uid`, have `link_dirty` TRUE, or logged no thresholds. An override env var takes a written reason, which is recorded in the manifest.
  - A `streams_md5` column on `log`, written at run finish. The export compares it, and a build without one reports "no digest" rather than refusing.
  - The published manifest names each part's S3 `versionId`.
  - Public read is #334's only item left open, for the operator.

Settled by the session from the plan review (`review-plan.md`): #464 checks the downstream groups' **FWA** streams (B2); a closure error refuses (G1); the check computes its own closure from its `outlets` (G2); #334's "test-looking `run_label`" gate is dropped, since there is no definition of one and `run_uid` plus a clean tree cover what it was for (S1); crate's release is 0.19.0 (O1). #461 does not reproduce on m4 even on a six-group database built by the cloud loader (findings.md), so the fix makes the probe's cost independent of the cause.

## Phase 1: Batch 7, one-group runs that read downstream (#461, #464)
- [x] #461: measure. m4 full DB 0.20 s; m4 six-group DB from rtj's cloud loader 0.18 s; a no-index copy of the six groups costs ~316 s for the snap (findings.md). The 371 s does not reproduce here.
- [x] #461 baseline before any change (O2, G6): record `status`, `dams` (ids, order), `wsgs_missing`, `note` for all 246 groups under `default` on `fresh_default`, plus a fail path (a cfg whose schema has no `barriers`) and an override, on m4's full DB; and BULK on `fwapg473`.
- [x] #461: time each step into the result (`steps_s`: outlets forced first, closure, loaded check, probe, persisted lookup).
- [x] #461: compute the closure first with `frs_wsg_drainage(conn, aoi, outlets)` (species-filtered in the check), and snap only dams within 65 m of the downstream groups' `fwa_watershed_groups_poly` rows; with any of those polygons absent, snap every dam (as today). Re-run the baseline sweep: identical. Measure the probe on the six-group no-index emulation before and after.
- [x] #461: `wsg_run_one.R` and `wsg_recompute_one.R` print the check's own seconds beside the pipeline's.
- [x] #464: a mocked test first (closure holding an unloaded fake group, no dams): red today.
- [x] #464: before matching dams, confirm each downstream group of the closure has rows in `whse_basemapping.fwa_stream_networks_sp`. Unloaded groups go in `wsgs_unloaded`, with their own message (load the FWA streams), and fail / warn / override as today, the note naming them. A closure error refuses. Test green, and BULK refuses live on `fwapg473`, which holds none of LSKE, KLUM, KISP.
- [x] RUNBOOK §8c updated (the check refuses an unloaded downstream group; its timing).

## Phase 2: Batch 6, the export contract (#423, #333, #334)
- [ ] #423: add an `access` integer column to the contract after `has_barriers_dnstr`. Select it in `.lnk_export_rows()` from `streams_access.access_<sp>` (NULL where the table or column is absent); `.lnk_export_conform()` types it. Tests: 0/1/2 survive, the absent case is NA.
- [ ] #423 / B1: `lnk_db_load()` takes each tree's columns from its manifest (`datasets[].schema.cols`), loads a part lacking `access` with it NULL, and adds the column to an existing table; refuses only a column it cannot reconcile. Tests on an old-contract tree, an existing table, and a root carrying a config not re-exported (G11; refuse or carry per manifest).
- [ ] #423: each config entry in the manifest summarises its builds' four tokens (the runs already carry them, A3). Mixed tokens are listed, not refused. RUNBOOK notes a lifting recompute turns 0 into 1, not 2 (A2).
- [ ] #333 (crate, its own branch and PR): copy the final YAML to `inst/extdata/schemas/nge/habitat/fwa/v1/segment.yaml`, add the `schema_only` registry row with `canonical_cols`, NEWS, release 0.19.0.
- [ ] #333 (link): raise the `crate` floor; `.lnk_export_spec()` reads the YAML from the installed crate (`system.file()`, G8), keeps the type check, drops link's copy. The manifest cites crate's tagged URL at a released version (G10); `contract_md5` becomes an md5 over names and types, and `exported_by` records crate's version (G9). Group-part contracts stay in link.
- [ ] #334: `streams_md5` on `<schema>.log`: `v1:` + md5 of per-row md5s over `cols_streams` in order, by `id_segment`, at a pinned `extra_float_digits` (G12), written in `.lnk_log_run_finish()`. Prove it survives a COPY round trip into a scratch schema. The export reports `match` / `differs` / `no digest` per group; `differs` stops BUILD.
- [ ] #334: an R/ helper `.lnk_publish_refusals()` (G15), called in PUBLISH's pre-write block: refuses builds or recomputes without `run_uid`, `link_dirty` or `fresh_dirty` TRUE, `thresholds_logged` FALSE, or an exporter with `link_dirty`, over parts and group parts, unless `LNK_PUBLISH_ALLOW="<reason>"`, recorded in the manifest. Tests per refusal and the override.
- [ ] #334: PUBLISH asserts versioning `Enabled`, reads each part's `VersionId` with `head-object` (skipped parts too, G13), rewrites the local manifest atomically before uploading it; `lnk_catalog()` exposes `version_id` and fetches by it (G14); RUNBOOK says the manifest is pinned through `list-object-versions`, and a keep-the-last-N rule is the bucket owner's call.
- [ ] RUNBOOK §6d updated: the new column, tokens, crate contract, gates, digest, versionIds.

## Phase 3: Release
- [ ] NEWS, version bump (minor: new export column and log column), CLAUDE.md status block, `research/` where a measurement settles (#461's timing).
- [ ] BUILD an export locally from `fresh_default` (a few groups), read it back through `lnk_catalog()` / `lnk_db_load()`, check `access` against `streams_access` row for row on one group; load the published 2026-11-14 tree and into an existing table; the gates pass on it.
- [ ] Drop the scratch database `fwapg473`.

## Owed at the end (reported, done after merge)
- [ ] PUBLISH of the new export (operator's word); the next provincial run re-models to `acc-v6`, and its republish carries the new values and the first `streams_md5`.
- [ ] #334's public read: infrastructure-repo tofu after budget and anomaly alerts (operator).
- [ ] The pre-run gate runs again before the next provincial run (`R/` changed).

## Validation
- [ ] Tests pass (`devtools::test()`, `devtools::check()`, `lintr` per file against main)
- [ ] `/code-check` clean (once over the branch, three-round floor)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: #461's before/after equality on four groups, with the timing table; #464's red-then-green fixture test; export round trip (BUILD → `lnk_catalog()` → `lnk_db_load()`), checking the `access` column against `streams_access` row for row on one group; each PUBLISH refusal driven by a test with a stubbed `aws`; the digest equal on a group before and after a consolidate copy.

