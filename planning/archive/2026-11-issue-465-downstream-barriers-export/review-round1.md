# Code review, round 1: #465 branch (3c0ab0bc...80549772)

## Checklist read

- **code-check.md:** the `## Mechanisms` prose of: A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies (first half); Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently (first part). Not read in full: 5 mechanisms (A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; One fact derived twice) and the stand-alone, security and spreadsheet sections (about 25 headings), which I read from the index only.
- **code-check-r.md:** read in full: A database driver's value is not a base R type; Postgres row order is never fixed unless the query fixes it...; `$` on a list partial-matches...; An `information_schema` lookup by the literal table name...; `data.frame()` recycles a scalar against a zero-length column. The rest (about 125 headings) from the index only. I also probed the RPostgres double round trip that the loader relies on: `dbWriteTable` of doubles, including 2,000 `fresh_default.barriers` measures, reads back `identical()`.
- **code-check-shell.md:** all from the index (the diff's shell is one awk test and some echo lines; `[ … ] && [ … ] || return 0` is used correctly). 0 sections read in full.
- **code-check-spatial.md:** all from the index (the hex WKB round trip uses no sf or terra). 0 sections read in full.

Tests run in the worktree with NOT_CRAN=true: test-lnk_downstream.R (46 pass), test-lnk_export_groups.R (53), test-lnk_export_inputs.R (22), test-lnk_wsg_deps.R (4) and test-pretest.R (134, 1 skip: no fresh checkout). All green.

## Findings

- **[severity: fragile]** R/lnk_export_inputs.R:116-117 together with R/lnk_downstream.R:181 and :461. The loader's input comparison silently skips every snapshotted input whose reason is `changed since build`. That branch returns `list(key = NULL, content_md5 = m, reason = "changed since build")`, which carries the build's md5 but no `table`. `.lnk_downstream_inputs()` then reads `table` as NA, and `.lnk_downstream_inputs_compare()` drops rows with `!is.na(inputs$table)`, so the build's recorded CABD or PSCIS md5 is never compared with this database's. That breaks the function's own contract ("A build that recorded no identity is not compared"): this build did record one. It is also the case where the report matters most, because the builds ran on several hosts with loads of their own, and the export database's CABD has already been seen to differ. Reproduced in the worktree. Given a dependency whose `cabd_dams` entry is `{content_md5: "aaa", reason: "changed since build"}` and whose PSCIS entry carries a table, `.lnk_downstream_inputs_compare()` returned only the PSCIS row; the CABD difference (local md5 is not "aaa") was not reported. The fix is to put `table = t` in the `changed since build` return (and arguably in `not read`, though that one is correctly not compared).
  - **Rule:** code-check.md "A guard that fails toward pass" ; code-check.md "Zero-length, empty, and unset are three different things"

- **[severity: fragile]** R/lnk_wsg_deps.R:74 (the only completeness check) and R/lnk_export_groups.R:190 (`.lnk_export_dependencies()`). The dependency map the export ships is computed from whatever FWA the exporting database holds, and the only refusal is an empty result. On an export database whose `fwa_stream_networks_sp` lacks some groups, the line rule silently drops every pair through those lines. `lnk_downstream_files()` then lists fewer dependencies, `lnk_downstream_load()` loads fewer groups, and the target's walk reads too little. Nothing reports it: `.lnk_export_fwa_identity()` records the row count and size "as context, not a guard". The map is the one artifact the one-group machine cannot recompute, so a partial map is undetectable there. A cheap guard at export time would close it: refuse, or at least flag in the manifest, when any group the export holds (any config's `r_cf$watershed_group_code`) or any group in `barriers` is absent from the FWA segments the rule read.
  - **Rule:** code-check.md "A guard that fails toward pass"

Nothing else rose to a real issue. Checked and found sound:

- Carry-forward of `group_parts`: `list(prev$group_parts)` plus `[-1]` in the regressions call, and `.lnk_manifest_previous_groups()` md5-checks what it carries.
- `.lnk_manifest_group_pairs()` reads both the column-list shape (exporting) and the one-part shape (parsed JSON).
- PUBLISH: the regressions judgement covers per-group parts before any write. Stale deletion is scoped to `segment/`, `barriers/` and `barrier_overrides/` with a prefix assertion, and `inputs/` and `dependencies/` are never deleted. The read-back covers group parts and the map's md5.
- The loader: every part is fetched and md5-checked before the database is touched; one transaction with per-part row checks; a NOT NULL `manifest` or `run_id` fails inside the transaction and rolls back.
- `null = "null"` on the manifest writer, so NULL keys read back as NULL, not `{}`.
- The `artifact_content_md5` and `content_md5` columns are added by `ADD COLUMN IF NOT EXISTS`, and `.lnk_log_inputs()` guards an old ledger.
- The provenance `log_input` parquet gains an all-NA column, which `.lnk_parquet_same()` accepts.
