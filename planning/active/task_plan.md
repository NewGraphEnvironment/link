# Task: Export persisted barriers and input snapshots per group, so a one-group run reads downstream (#465)

`lnk_pipeline_run()` classifies access from the already-persisted barriers of the groups downstream of the one it models. A machine built for a few groups has none of those. `data-raw/habitat_publish.R` (`lnk_scenario_export()`) already exports persisted runs per config and per group to `s3://fresh-bc/habitat/fwa/v1` with a manifest, but not the barriers a downstream run would read, nor the input snapshots they came from.

## Context

`lnk_pipeline_run()` classifies a group's access by walking downstream through the
persist schema's province-wide `barriers` and `barrier_overrides` (`R/lnk_pipeline_run.R:272-361`,
`R/lnk_barriers_views.R:162`). A machine built for a few groups holds neither for the
groups downstream, so its run classifies access as though nothing downstream blocks
(and, once #464 lands, refuses). The habitat export (`lnk_scenario_export()`,
`data-raw/habitat_publish.R`, RUNBOOK §6d) already ships segments and each build's
`log` / `log_input` under `provenance/`, but not the barriers, the overrides, the
dependency map, or the inputs. Outcome: a one-group machine fetches what its walk reads
from the export and classifies access as the provincial run does.

Two corrections to the issue body, found in exploration (the body gets edited to match):
- **The walk reads `barrier_overrides` too**, not only `barriers` (link's "CABD barriers"
  are the `barrier_source = 'CABD'` rows of `barriers`, not a separate table).
- **The outlet path is too narrow.** #374 measured `frs_wsg_drainage()` missing groups whose
  rows a walk reads in 150 of 241 groups; `data-raw/recompute_deps.R`'s line rule is
  complete by construction (median 9 groups). Item 4 lists the line rule's groups.

## Decided at the gate (operator, 2026-11-11)

1. **Dependency rule: the line rule**, moved into `R/`, computed at export from province
   FWA, shipped as a table in the export (a one-group machine has no province FWA).
2. **Input snapshots: all four**, CABD dams, PSCIS and modelled crossings sliced per group,
   bcfishobs observations once province-wide; each written only where the database's
   fingerprint still matches the build's `log_input`, otherwise the manifest says why not.
3. **Consumer: list, fetch, load barriers.** A helper lists dependency groups and their
   files; a loader puts their `barriers` and `barrier_overrides` into a persist schema
   (md5 and row counts checked) and reports input differences against the local database.
   Loading snapshots into primitive tables is a follow-up issue.
4. **Republish: the run summary prints the commands** (BUILD and PUBLISH for the run's
   config and schema); RUNBOOK §8d's post-run list names them. Nothing reaches S3 without
   the operator.

## Phase 1: Line-rule dependencies in R/
- [x] Extract the line rule from `data-raw/recompute_deps.R` (`deps_fwa()`, the `rd_seg` /
      `rd_anc_all` / `rd_pathblk` SQL) into an internal `R/` function returning `wsg, dep`;
      keep owner and closure in the script
- [x] `recompute_deps.R` calls it (via `load_all()`); prove its province `line` output
      byte-identical before and after (tsv diff, both runs logged)
- [x] Test: refuses an empty FWA answer; pairs on a small live fixture (skip without DB)
- [x] Map the new file in `data-raw/pretest_inputs.csv` (`none`, call-graph checked)

## Phase 2: Barrier and override parts in the export
- [ ] Per config, per exported group: `barriers/config=<c>/part-<WSG>.parquet` and
      `barrier_overrides/config=<c>/part-<WSG>.parquet`, columns from `cols_barriers` /
      `cols_barrier_overrides` (one source of truth; ltree as text, `blocks_species` a list,
      geom as WKB), ordered on their PKs so parts are byte-reproducible
- [ ] Manifest: a new top-level `barrier_parts` array (key, dataset, config, wsg, run_id,
      rows, bytes, md5) so `parts` stays the segment dataset and `lnk_catalog()` /
      `lnk_db_load()` / older readers are untouched; carried forward for configs not named;
      staged and swapped with the segment parts
- [ ] `.lnk_manifest_regressions()` judges barrier parts as it does segment groups (a
      dropped group or an older build refuses without `replace`)
- [ ] `habitat_publish.R` PUBLISH uploads them and deletes stale keys under `barriers/`
      and `barrier_overrides/` only, as it does `segment/`
- [ ] Tests in `test-lnk_scenario_export.R` (helper-export.R fixture): parts present, rows
      equal the schema's per group, md5s, carry-forward, regression refusal; red first

## Phase 3: Dependency map in the export
- [ ] `dependencies/rule=line.parquet` (`wsg, dep`) from Phase 1, replaced each export,
      in the manifest with the FWA fingerprint it was computed at (the `log_input` row for
      `fwa_stream_networks_sp`), and refused when FWA gives no pairs
- [ ] Test: present, md5 matches, refuses an empty map

## Phase 4: Input snapshots
- [ ] Per build: `inputs/run_id=<id>/{cabd_dams,pscis,modelled_crossings}.parquet`
      (write-once, like `provenance/`), each the group's slice as the run's own filters
      select it (reuse the dams/PSCIS/crossings group filters, not a second copy)
- [ ] Province observations once: `inputs/observations/<md5>.parquet`, content-addressed,
      each build pointing at it when its fingerprint matches
- [ ] Guard: write a snapshot only when the database's current fingerprint of that table
      (`.lnk_log_inputs()`'s fields: row count, `source_at`, artifact version / ETag /
      `loaded_at`; not `last_analyze`) equals the build's `log_input` row; otherwise record
      `{input, reason: "changed since build", build: …, now: …}` in the manifest and write
      nothing
- [ ] Tests: written when unchanged, refused (recorded, not written) after a fingerprint
      moves, write-once refuses a different record

## Phase 5: The one-group side
- [ ] `lnk_downstream_files(manifest, wsg, config)`: the target's dependency groups from the
      shipped map, and for each the barrier / override hrefs and md5s, the build's input
      snapshot hrefs (or why absent), and the FWA object URL (from `.lnk_input_primitives()`'s
      `{wsg}` template) so the machine can load their streams for #464's check
- [ ] `lnk_downstream_load(conn, files, cfg, schema)`: fetch (`.lnk_fetch_file()`), check
      md5, `lnk_persist_init()`, replace each dependency group's rows in `barriers` and
      `barrier_overrides` (refuse a group the schema already holds from a build of its own
      unless `replace`), check row counts, and report each input whose local fingerprint
      differs from the build's (report, not refuse: provenance rule 8)
- [ ] Runnable examples on a local export written in `tempdir()`; tests: md5 mismatch
      refuses, counts, report
- [ ] Map both new files in `pretest_inputs.csv`; file the follow-up issue (load input
      snapshots into primitives) on the operator's word

## Phase 6: Driver, docs, release
- [ ] `study_area_run.sh` summary prints the export BUILD and PUBLISH commands for the
      run's config and schema (`data-raw/habitat_publish.R`), structural test
- [ ] RUNBOOK §6d (layout, barrier parts, dependencies, inputs, the guard), §8c (one-group
      runs read downstream from the export), §8d (post-run list); NEWS; CLAUDE.md status
- [ ] Edit #465's body to the corrections above; note the interplay on #464
- [ ] Version bump (minor) as the branch's last commit

## Owed at the end (reported, done after merge)
- [ ] The first PUBLISH carrying the new datasets (outward-facing; on the operator's word)
- [ ] The pre-run gate runs again before the next provincial run (`R/` changed)
- [ ] Follow-up issue: load input snapshots into the primitive tables
- [ ] #464 reads the same dependency rule (comment there, not done here)

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- Phase 1: `recompute_deps.R` province `line` output identical before and after.
- End to end on m4: export from `fresh_default` (built at `4dfbfa49`) a group with
  downstream natural barriers and lifts (PARS or a Fraser group) plus its line-rule
  dependencies into a local root; create scratch schema `fresh_465`, `lnk_downstream_load()`
  the dependencies, model the target with `wsg_run_one.R` into it, and compare its
  `streams_access` and `streams_mapping_code` with `fresh_default`'s, digest after rounding.
  Negative arm: the same run without the load differs. Logged under
  `data-raw/logs/downstream_export_465/`.
- `devtools::test()`, `lintr` per-file diff against main, `devtools::check()`.

