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
   **Revised 2026-11-12 (operator), after the plan review** (`review-plan.md`, blockers 1-2):
   the builds ran on 5 hosts, CABD and PSCIS have no version handle (5 loads, no content
   identity) and their group is decided province-wide inside a run, so per-group slices
   cannot be cut. Now: `snapshot_bcfp.sh` records a content md5 of CABD's and PSCIS's
   ordered rows in `provenance.source_artifact` (copied into `log_input` by every run); the
   export writes province-wide CABD and PSCIS snapshots keyed by content only for builds
   whose logged md5 equals the export host's (earlier builds read "no content identity");
   observations and modelled crossings are cited by their loader version id (one across all
   241 builds), not copied.
3. **Consumer: list, fetch, load barriers.** A helper lists dependency groups and their
   files; a loader puts their `barriers` and `barrier_overrides` into a persist schema
   (md5 and row counts checked) and reports input differences against the local database.
   Loading snapshots into primitive tables is a follow-up issue.
4. **Republish: the run summary prints the commands** (BUILD and PUBLISH for the run's
   config and schema); RUNBOOK §8d's post-run list names them. Nothing reaches S3 without
   the operator.

5. **End to end: the round trip on m1, a partial database later** (operator, 2026-11-12):
   export-loaded arm equal to an SQL-copied control arm exactly, a no-load negative arm and
   a barriers-without-overrides arm; a second database holding only some groups' FWA is a
   follow-up issue, and the limit is stated.

## Phase 1: Line-rule dependencies in R/
- [x] Extract the line rule from `data-raw/recompute_deps.R` (`deps_fwa()`, the `rd_seg` /
      `rd_anc_all` / `rd_pathblk` SQL) into an internal `R/` function returning `wsg, dep`;
      keep owner and closure in the script
- [x] `recompute_deps.R` calls it (via `load_all()`); prove its province `line` output
      byte-identical before and after (tsv diff, both runs logged)
- [x] Test: refuses an empty FWA answer; pairs on a small live fixture (skip without DB)
- [x] Map the new file in `data-raw/pretest_inputs.csv` (`none`, call-graph checked)
- [x] Prove `recompute_deps.R ... all` identical before and after too (review: the owner
      rule's refusal path)

## Phase 2: Barrier and override parts in the export
- [x] Per config, per exported group: `barriers/config=<c>/part-<WSG>.parquet` and
      `barrier_overrides/config=<c>/part-<WSG>.parquet`, columns from `cols_barriers` /
      `cols_barrier_overrides` (one source of truth; ltree as text, `blocks_species` a list,
      geom as WKB), ordered on their PKs so parts are byte-reproducible
- [x] Manifest: a new top-level `group_parts` array (named for both tables) (key, dataset, config, wsg, run_id,
      rows, bytes, md5) so `parts` stays the segment dataset and `lnk_catalog()` /
      `lnk_db_load()` / older readers are untouched; carried forward for configs not named;
      staged and swapped with the segment parts
- [x] `.lnk_manifest_regressions()` judges barrier parts as it does segment groups (a
      dropped group or an older build refuses without `replace`)
- [x] `habitat_publish.R` PUBLISH uploads them and deletes stale keys under `barriers/`
      and `barrier_overrides/` only, as it does `segment/` (written and parses; not run:
      PUBLISH writes to S3, and no test drives the script)
- [x] Barrier parts iterate the exported groups, not the species loop (paused-only groups
      get them); a schema without `barriers` / `barrier_overrides` is refused
- [x] Tests (`test-lnk_export_groups.R`; helper-export.R fixture, extended with barrier
      tables): parts present, rows equal the schema's per group, md5s, carry-forward,
      regression refusal; red first

## Phase 3: Dependency map in the export
- [x] `dependencies/rule=line.parquet` (`wsg, dep`) from Phase 1, replaced each export,
      as its own manifest entry (not `files`, which are write-once), with the export
      database's FWA identity (whole-table row count and size, link sha), and refused when
      FWA gives no pairs; PUBLISH puts it and refuses nothing on a changed md5
- [x] Superset check, logged: `barriers` and `barrier_overrides` rows of `fresh_default`
      whose `blue_line_key` FWA does not touch under the row's own group (expect 0)
- [x] Test: present, md5 matches, refuses an empty map

## Phase 4: Input snapshots (last; revised at the gate, see decision 2)
- [ ] Content identity at load: `snapshot_bcfp.sh` (through `data-raw/artifact_record.R` /
      `lnk_artifact_record()`) writes an md5 of CABD's and PSCIS's rows, in a fixed order,
      into `provenance.source_artifact`; `.lnk_log_inputs()` copies it into `log_input`
      (new column, aligned for older rows)
- [ ] The export writes `inputs/cabd_dams/<md5>.parquet` and
      `inputs/pscis_assessment/<md5>.parquet` (province-wide, content-addressed, kind
      `input` in `files`) for builds whose logged md5 equals the export host's current md5;
      each run entry records its snapshot key or the reason absent (`no content identity at
      build`, `changed since build`, `not read`: `arg_dams` FALSE); an existing key is
      referenced without re-judging
- [ ] Observations and modelled crossings: each run entry cites the loader version id and
      ETag from its `log_input` (no copy)
- [ ] Tests: md5 deterministic under row order; snapshot written on match, reason recorded
      on mismatch or missing identity

## Phase 5: The one-group side
- [x] `lnk_downstream_files(manifest, wsg, config)`: the target's dependency groups from the
      shipped map, each classed exported (barrier / override hrefs and md5s, build run_id,
      config_hash, link sha), skipped (refused unless overridden) or not held by the
      provincial schema (nothing to read), plus the FWA object URL (`.lnk_input_primitives()`'s
      `{wsg}` template), which parity and #464's check need
- [x] `lnk_downstream_load(conn, files, cfg)`: fetch through `.lnk_part_fetch()` (size, md5,
      cache), `lnk_persist_init()` on `cfg$pipeline$schema`, replace each dependency group's
      rows in `barriers` and `barrier_overrides` in one transaction (refuse a group the
      schema holds from a build of its own unless `replace`), check row counts, record each
      load in `<schema>.log_downstream_load`, and report differences: each build's
      `config_hash` against `.lnk_config_hash(cfg)`, link version, and inputs (report, not
      refuse: provenance rule 8)
- [x] Examples (`\dontrun`, as `lnk_scenario_export()` and `lnk_db_load()`: building a
      dependency map needs a database); tests: md5 mismatch refuses, counts, report
- [x] Map both new files in `pretest_inputs.csv` (the follow-up issue is listed under Owed)

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
- [ ] Follow-up issue: a partial-database arm (only the target's and its dependencies' FWA)
- [ ] Re-snapshot primitives on the provincial hosts before the next run so builds carry the
      CABD / PSCIS content md5

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- Phase 1: `recompute_deps.R` province `line` output identical before and after.
- End to end on m1 (round trip, decision 5): export from `fresh_default` (built at
  `4dfbfa49`) a target built on m1 whose line set is larger than its closure and whose path
  holds a dependency's override, plus its dependencies, into a local root. Arms, each in a
  scratch schema (dropped after, with `working_<wsg>`): (a) `lnk_downstream_load()` then
  `wsg_run_one.R`, guard in `error`; (b) control, dependency rows copied by SQL from
  `fresh_default`; (a) must equal (b) exactly in `streams_access` and
  `streams_mapping_code`; (c) no load, `LNK_GUARD_DOWNSTREAM=ignore` with a note, differs;
  (d) barriers without overrides, differs. Difference from `fresh_default` reported with
  causes. Logged under `data-raw/logs/downstream_export_465/`.
- `devtools::test()`, `lintr` per-file diff against main, `devtools::check()`.

