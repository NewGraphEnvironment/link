# Findings — Consume weekly crossings.csv; repoint pipeline off fresh (#231)

## Issue context

Repoint the pipeline off fresh's stale bundled `crossings.csv` onto the fresh,
weekly-refreshed `s3://newgraph/bcfishpass.crossings.csv` (produced by
`db_newgraph jobs/dump_weekly`, merged upstream via `smnorris/db_newgraph#57` on
2026-07-09). Depends-on/context: `db_newgraph#15` (now closed — the CSV is live).

## Exploration (two Explore agents, 2026-07-09)

### Read-side / swap point
- **Single reader**: `R/lnk_pipeline_load.R:100-108` — `system.file("extdata","crossings.csv",
  package="fresh")` → `read.csv` → filter `watershed_group_code == aoi` → `dbWriteTable`
  wholesale to `<schema>.crossings`. Repoint = swap the `system.file` call only; everything
  downstream is column-blind + source-agnostic given the shape holds.
- **12-col UUID compatibility**: load coerces `aggregated_crossings_id` to character
  (`:109-110`) → UUID fine; extra lon/lat cols carried harmlessly; misc-append NA-fills to
  `names(crossings)` (`:116-130`). Downstream consumes by name
  (`barrier_status`, `blue_line_key`, `downstream_route_measure`, `pscis_status`,
  `crossing_source`, `aggregated_crossings_id`). Verify no integer math on the id.
- Other (dev-only) readers: `data-raw/compare_adms.R:54`, `data-raw/test_sequential_breaking.R:279`.

### Bucket helpers (reuse as-is)
- `lnk_bucket_get(name, prefix=..., to=NULL)` and `lnk_bucket_log(prefix)` are
  **prefix-agnostic** — pass `prefix="https://newgraph.s3.us-west-2.amazonaws.com"`.
  Precedent: `data-raw/snapshot_bcfp.sh:247` already pulls newgraph.
- `s3://newgraph` is public/anon, same region as fresh-bc.

### Why fetch-cache, not bundle
- crossings ~59 MB (Content-Length 61,967,466), overwritten weekly, **no `log.json`**
  (all variants 404), but **ETag + Last-Modified present** → freshness checkable via HEAD.
- Pinned-bundle re-stales weekly (defeats the issue); weekly-commit = 59 MB/wk git bloat;
  newgraph keeps no history so committing can't reproduce old runs anyway. → fetch latest
  into cache + stamp the version.

### Deferred machinery (why it's follow-up, not MVP)
- **crate `canonical_schema` gate is INERT**: `sync_bcfishpass_csvs.R:128-141` reads
  `canonical_schema` from the provenance block, which nothing declares → returns NULL,
  never runs; slug format also mismatched vs `crt_schema_read` (expects
  `schemas/bcfp/<x>.yaml`). Real gate = a crate release (schema+handler+registry+tests) +
  fixing the sync gate. → follow-up.
- **Hard build-SHA guard** needs a build stamp on newgraph (none today) — `db_newgraph`
  `dump_weekly` would add a `log.json`. → follow-up. MVP stamps ETag/Last-Modified instead.
- **fresh sheds crossings.csv** is a fresh-repo change (`docker/load.sh:91-112`, generator
  `data-raw/bcfishpass_crossings.R`) — decoupled; link repoints first. → follow-up.

### Config / bundling facts
- All 4 configs use `extends: ~` (none inherit) and duplicate override CSVs; sync writes
  only `bcfishpass` + `default`. Overrides `cfg$files` path eager-loads every file each
  call — wrong vehicle for a 59 MB per-AOI table.

### Tests
- `.lnk_pipeline_load_crossings` is currently untested (greenfield). No bundled fixture
  matches the crossings-table shape (`crossings_example.csv` is the 9-col scoring shape).
  Mock patterns: `httr::GET` via `mockery`/`with_mocked_bindings` (`test-lnk_bucket.R`);
  DBI via `local_mocked_bindings` (`test-lnk_pipeline_load.R`).

### Install size
- link already ships ~30 MB `inst/`; no R-CMD-check workflow. Fetch-cache keeps the 59 MB
  out of the package entirely.
