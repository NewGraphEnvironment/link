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
- #466 (receipt.json) stays on the provenance track. This move adds only the `acc` token and the crate schema URL to the manifest.
- #334 in this PR:
  - PUBLISH refuses a part whose builds have no `run_uid`, have `link_dirty` TRUE, or logged no thresholds. An override env var takes a written reason, which is recorded in the manifest.
  - A `streams_md5` column on `log`, written at run finish. The export compares it, and a build without one reports "no digest" rather than refusing.
  - The published manifest names each part's S3 `versionId`.
  - Public read is #334's only item left open, for the operator.

## Phase 1: Batch 7, one-group runs that read downstream (#461, #464)
- [ ] #461: time each step of `lnk_wsg_downstream_check()` (outlets, closure, dam probe, persisted lookup) into its return value (`steps_s`). Measure on one group on the local fwapg and on a partial-database case, and record which step dominates in findings.md.
- [ ] #461: make the dominant step fast (an index-friendly rewrite, a precomputed input, or a cache keyed on what it reads), with pass / fail / override unchanged. Prove it: the same result on BULK, PARS, SLOC and BULL before and after, plus the existing tests.
- [ ] #461: `wsg_run_one.R` and `wsg_recompute_one.R` print the check's own seconds beside the pipeline's.
- [ ] #464: first a test that fails today. A database fixture lacking a downstream group passes now and must refuse.
- [ ] #464: before matching dams, confirm each group on the focal group's downstream path (the closure's downstream members) has streams loaded. A group with none refuses and is named; `on_fail` and `override` work as now; the note lands in the run log. Make the test green.
- [ ] RUNBOOK §8c updated (the check refuses an unloaded downstream group; its timing).

## Phase 2: Batch 6, the export contract (#423, #333, #334)
- [ ] #423: add an `access` integer column to `habitat_fwa_v1_segment.yaml` after `has_barriers_dnstr`. Select it in `.lnk_export_rows()` from `streams_access.access_<sp>` (NULL where the table or column is absent); `.lnk_export_conform()` types it. Tests: a 2 survives, -9 survives, and the absent case is NA.
- [ ] #423: each config entry in the manifest carries the `token_acc` (and the other three tokens) of its builds, read from `log`. Mixed tokens across one config's builds are listed, not refused.
- [ ] #333 (crate, its own branch and PR): copy the YAML to `inst/extdata/schemas/nge/habitat/fwa/v1/segment.yaml`, add the `schema_only` registry row, NEWS, release (0.18.0).
- [ ] #333 (link): raise the `crate` floor; `.lnk_export_spec()` reads the spec from crate (`crt_registry_entry()` / the installed YAML), keeps `.lnk_export_conform()`'s type check, and drops link's copy of the YAML. The manifest's `datasets[].schema` cites crate's tagged URL. The group-part contracts (`cols_barriers`, …) stay in link.
- [ ] #334: `streams_md5` on `<schema>.log` (`.lnk_log_specs()`, aligned by `.lnk_log_align_columns()`). It is an md5 over the group's persisted `streams` rows in a stated order, written in `.lnk_log_run_finish()`. Check that `schema_consolidate.R`'s COPY reproduces it on the dispatcher. The export recomputes it per group and reports `match` / `differs` / `no digest`; `differs` stops BUILD.
- [ ] #334: PUBLISH (`data-raw/habitat_publish.R`) refuses a part whose groups' builds lack `run_uid`, are `link_dirty`, or have `thresholds_logged` FALSE, unless `LNK_PUBLISH_ALLOW="<reason>"`, which the manifest records. Test each refusal and the override.
- [ ] #334: after upload, read each part's `VersionId` (`put-object` output) into the published manifest, and RUNBOOK §6d says how a consumer pins one. A keep-the-last-N lifecycle rule is noted as the bucket owner's call.
- [ ] RUNBOOK §6d updated: the new column, tokens, crate contract, gates, digest, versionIds.

## Phase 3: Release
- [ ] NEWS, version bump (minor: new export column and log column), CLAUDE.md status block, `research/` where a measurement settles (#461's timing).
- [ ] BUILD an export locally from `fresh_default` (a few groups) and read it back through `lnk_catalog()` / `lnk_db_load()`; the gates pass on it.

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

