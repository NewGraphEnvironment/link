# Task: Consume weekly crossings.csv; repoint pipeline off fresh (#231)

The pipeline reads crossings from `fresh`'s bundled `crossings.csv`
(`R/lnk_pipeline_load.R:100`) — a hand-exported snapshot ~3 months stale. A fresh,
weekly-refreshed `crossings.csv` is now published to
`s3://newgraph/bcfishpass.crossings.csv` (12 cols: 10 modelling + WGS84 lon/lat;
`aggregated_crossings_id` a UUID; ~59 MB; ETag + Last-Modified; no `log.json`;
overwritten weekly, no history). Repoint link at a link-owned, always-current copy.

## Decisions (user-approved)

- **Storage = fetch latest into a per-user cache** (`tools::R_user_dir("link","cache")`),
  re-download only on ETag change, stamp the version per run. No commit, no bloat,
  never stale. (Pinned-bundle rejected: re-stales weekly; weekly-commit rejected: 59 MB/wk bloat.)
- **Scope = MVP now, harden later.** Ship fetch-cache + repoint + lightweight header
  drift check + version stamp. Defer crate gate, hard build-SHA guard (needs upstream
  newgraph `log.json`), and fresh dropping its copy.
- **Not** the `cfg$files`/overrides path (eager-loads every file each call). Only reader
  is `lnk_pipeline_load.R:100`.

## Phase 1 — Fetch-cache helper + repoint
- [ ] New `R/lnk_crossings_cache.R` — `lnk_crossings_cache(prefix, name, cache_dir)`:
      HEAD for ETag; download via `lnk_bucket_get(..., to=<cache>/crossings.csv)` only on
      ETag change; ETag sidecar; return `list(path, etag, last_modified)`. Fetch-fail +
      cache → warn + use; fetch-fail + no cache → error. `@examples` block.
- [ ] Repoint `R/lnk_pipeline_load.R:100-103` → `lnk_crossings_cache()`; drop fresh error text.
- [ ] Repoint dev readers `data-raw/compare_adms.R:54`, `data-raw/test_sequential_breaking.R:279`.
- [ ] Verify 12-col UUID CSV flows: run ADMS through `lnk_pipeline_load`; 12-col table,
      AOI filter + misc NA-fill work, UUID id used only as string (grep integer math).

## Phase 2 — Version stamp + drift guard
- [ ] Stamp crossings version (ETag/Last-Modified/date) into run lineage
      (`lnk_baseline_append` / `bcfp_baselines.csv` or pipeline stamp).
- [ ] Header-shape drift check on download (reuse `shape_fingerprint`,
      `sync_bcfishpass_csvs.R:74-82`) → fail loud on 12-col header drift.

## Phase 3 — Tests
- [ ] `tests/testthat/test-lnk_crossings_cache.R` — mock `httr::HEAD`/`GET`: cache-hit,
      cache-miss, offline+cache (warn), offline+no-cache (error), header drift.
- [ ] Extend `test-lnk_pipeline_load.R`: mock cache helper → fixture path; assert AOI
      filter + `dbWriteTable` shape.
- [ ] New fixture `inst/testdata/crossings_table_example.csv` (12-col, 2 WSGs).

## Phase 4 — Docs + release
- [ ] RUNBOOK.md / README: crossings now fetched-on-demand from newgraph into user
      cache (not bundled, not fresh); version stamped per run.
- [ ] NEWS.md + DESCRIPTION patch bump (final commit).
- [ ] CLAUDE.md status block.

## Follow-ups (OUT of #231)
- fresh drops crossings.csv (fresh-repo PR): delete file, adjust `docker/load.sh:91-112`,
  retire `data-raw/bcfishpass_crossings.R`.
- Hard build-SHA guard: newgraph `log.json` from `dump_weekly` → assert crossings-build
  == overrides-build.
- crate `canonical_schema` gate (crate release) + fix inert sync gate.
- Crossing-rollup vignette (habitat + type by crossing, mapped via lon/lat).

## Validation
- [ ] ADMS end-to-end with fetched crossings: completes, 12-col table, ETag stamped.
      Small rollup diffs expected (newer data), sanity-check magnitude.
- [ ] Offline w/ cache → warn+use; offline no-cache → clear error.
- [ ] `devtools::test()` green; `lintr::lint_package()` clean.
- [ ] `/code-check` clean on each commit.
- [ ] PWF checkboxes match landed work; `/planning-archive` on completion.
