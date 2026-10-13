# Task: Record source-artifact identity for the DB primitives (bucket is versioned but unlistable) (#265)

We load the FWA primitives from a **versioned** object store, and we record
nothing that identifies which version we got. The store **will not let us ask
later** — so every version-id we fail to record at load time is gone, not merely
inconvenient to find.

`fwapg_sha` pins neither the data nor, it turns out, the loader's commit (see
"Measured 2026-10-12" below). `fwa_stream_networks_sp`
is, by `R/lnk_log.R`'s own comment, "the most load-bearing input the pipeline
has", and nothing records the bytes it was built from.

## Context

The primitives are loaded from a versioned object store (`nrs.objectstore.gov.bc.ca/bchamp`). A plain `HEAD` returns
`x-amz-version-id`, `ETag` and `Last-Modified`, and `?versionId=` re-fetches an exact version. But `?versions` and prefix
listing are `AccessDenied`, so a version id nobody wrote down at load time can never be recovered. Today nothing records
one. `fwapg_sha` pins neither the data nor the loader: it is the checkout HEAD at **model** time.

What was measured during planning (2026-10-12):
- The headers still come back on every artifact. Examples: observations `v1790057230537` (2026-09-22), modelled crossings
  `v1791321558612` (2026-10-06), `fwa_stream_networks_sp/BULK.parquet`, and channel_width / discharge `.csv.gz`.
- GDAL opens `/vsicurl/<url>?versionId=<id>` fine, and a bad id returns 404. So a loader can **pin** the read to the
  version it heads, which makes "recorded = loaded" true by construction.
- `fwa_obstructions_sp` was already fixed by #271 (`R/lnk_log.R:213`), and there are now **12** primitives (discharge was
  added).

Decisions taken at the plan gate:
- #270 (the fwapg `load.sh` capture wrapper) stays separate.
  - FWA rows here are honest `probe` rows.
  - The acceptance box "fwapg commit recorded at load time" moves to #270, which will write `loader` rows into this
    table.
- Each run carries the artifact identity it read, through new columns on `<schema>.log_input`. That table already
  consolidates by `watershed_group_code`, so a burned cypher's provenance survives the burn.
- `kind` takes one of three values:
  - `object`: a versioned bucket fetch;
  - `api`: PSCIS and CABD, which have no version handle, so NULL is permanent there;
  - `derived`: `order_parent`, built in the DB.
- #247 is absorbed: its absent-stamp-is-FATAL property is carried over.

Naming (adjust at approval if wanted): the exported `lnk_artifact_record()` and `lnk_artifact_probe()`. The table is
`fresh.log_source_artifact`, as the issue proposed.

## Phase 1: Dictionary and DDL
- [x] `.lnk_input_primitives()` (`R/lnk_log.R:200`) gains `kind` and `url` columns.
  - The URL template is per table: `{wsg}` for `fwa_stream_networks_sp`, `.csv.gz` for channel_width and discharge, and
    NA for `order_parent`.
  - PSCIS and CABD carry their API URLs.
  - This stays the single list (no second list of URLs).
- [x] `cols_source_artifact` named vector:
  - `host`, `table_name`, `url`, `kind`, `version_id`, `etag`, `last_modified`, `n_rows`, `loaded_at`, `recorded_at`,
    `recorded_by` and `notes`;
  - PK `(host, table_name, url)`;
  - CHECKs on `kind` and `recorded_by`.

  `.lnk_source_artifact_create(conn)` builds the DDL from that vector. It creates the `fresh` schema if absent and uses
  `ADD COLUMN IF NOT EXISTS`, following the `.lnk_log_create_tables()` pattern.
- [x] Tests: the dictionary's shape (12 rows; every `object` row has a URL; `derived` has none), and that the DDL is
  idempotent.

## Phase 2: HEAD helper, record and probe
- [x] `.lnk_artifact_head(url)`, using `httr::HEAD` with a timeout. It returns `version_id`, `etag`, `last_modified` and
  the HTTP status. **It never errors**: an unreachable URL or a non-200 gives NAs plus a status in `notes`.
- [x] `lnk_artifact_record(conn, artifacts, recorded_by, host)` upserts rows and computes `n_rows` from the DB.
  - **A `probe` never overwrites a `loader` row** (`ON CONFLICT … DO UPDATE … WHERE existing.recorded_by = 'probe' OR
    EXCLUDED.recorded_by = 'loader'`), so weaker evidence cannot replace stronger and a loader still refreshes a loader.
  - A missing primitive is reported as missing, not skipped.
- [x] `lnk_artifact_probe(conn, tables)` HEADs the FWA `object` URLs and writes `probe` rows. It takes the per-WSG stream
  objects from the distinct `watershed_group_code`s **loaded in the DB**, not from a copy of `load.sh`'s dispatch.
  `order_parent` gets a `derived` row with NULL identity.
- [x] Tests:
  - mocked HEAD (200, 404, unreachable): an honest NULL row, no error;
  - the probe-does-not-clobber-loader rule;
  - a runnable `@examples` on both exports.
- [x] Added `lnk_artifact_read()`: one row per expected artifact, with `status = missing` where none is recorded (acceptance: a missing row is reported, not skipped).

## Phase 3: `snapshot_bcfp.sh` writes `loader` rows
- [x] For the two object sources (observations parquet, modelled-crossings zip), HEAD first, then pin the fetch to
  `?versionId=<id>`. That is `ogr2ogr /vsicurl/…?versionId=` for the parquet and `curl` for the zip. If the HEAD fails,
  load unpinned and record a NULL version, with a note.
- [x] PSCIS and CABD get `kind = api` rows, with their URL and `loaded_at`.
- [x] Bash writes a TSV manifest (table, url, kind, version, etag, last_modified, loaded_at).
  - One `Rscript data-raw/artifact_record.R <manifest>` call then runs `lnk_artifact_record(recorded_by = "loader")`.
  - **If it fails, the snapshot exits non-zero.** Provenance is the point, and `cypher_prep.sh` already treats a snapshot
    failure as FATAL.
  - This is unlike the soft-fail ledger step.

## Phase 4: Each run carries its artifacts (`log_input`)
- [x] `cols_log_input` gains `artifact_url`, `artifact_kind`, `artifact_version_id`, `artifact_etag`,
  `artifact_last_modified`, `artifact_loaded_at` (review G1) and `artifact_recorded_by`. They are added through the existing `ADD COLUMN IF NOT EXISTS`
  path.
- [x] `.lnk_log_inputs()` (`R/lnk_log.R:643`) LEFT JOINs `fresh.log_source_artifact` for this host. For
  `fwa_stream_networks_sp` it uses the run's own `<WSG>.parquet` URL. A missing table gives NULLs (it still soft-fails;
  logging never kills a run).
- [x] DB test: a stamped and an unstamped host both write a `log_input` row, with identity filled or NULL.

## Phase 5: Vintage gate prefers the stamp (#247)
- [ ] `lnk_preflight_vintage()` reads `loaded_at` from `fresh.log_source_artifact` for this host for the four snapshot
  primitives.
  - **An absent stamp is FATAL**, reported as `unstamped` and kept distinct from `absent` and `unknown`. The message
    carries the remediation command and shows the pg_stat-inferred age for context.
  - The message says which predicate judged each table.
- [ ] Tests in both directions (a host with a stamp, and one without), plus the existing tests kept green.

## Phase 6: Docs
- [ ] Correct the `.lnk_fwapg_sha()` roxygen (`R/lnk_log.R:1181`) and the `fwapg_sha` line in `lnk_stamp()`
  (`R/lnk_stamp.R:43`): they now say it is the checkout's HEAD at run time, not the loader's commit. Already-logged
  values are left alone.
- [ ] `R/lnk_pipeline_break.R:25` still names `fwa_obstacles_sp`. Falls actually come from `fresh`'s `falls.csv`
  (`R/lnk_pipeline_prepare.R:171`), so name that, not `fwa_obstructions_sp` (review, Scope 1).
- [ ] RUNBOOK §8d: the stamp becomes the gate's primary source, plus a note on `recorded_by` / `kind`. Add NEWS and a
  CLAUDE.md status entry.
- [ ] Mark #247 superseded in the PR body; leave a pointer on #270 that the table exists.

## Review fixes (Plan agent, 2026-10-13)
- [x] The table location comes from one function (`.lnk_artifact_location()`), so a move is one line (review B1 / G3).
- [x] Reuse `.lnk_regex_escape`; normalise ETags in `lnk_artifact_record()`; the probe stops after `max_fail` consecutive
  failures and has a connect timeout; `lnk_artifact_probe()` is documented as never a baseline for #273.
- [x] Probe call site: `snapshot_bcfp.sh` runs `artifact_record.R --probe` after recording (soft-fail).
- [x] `.lnk_http_date()`: `httr::parse_http_date()` is all-or-nothing, which blanked `last_modified` on both loader rows of
  the first live run. Element-wise parse, a regression test, and the recorder refuses a version id without its date.
- [ ] Open for the user: B1, the table's schema (`fresh` is dropped by `state_clean.sh`'s default mode) and whether `host`
  belongs in the key.

## Verification (live, local docker fwapg)
- `devtools::test()`, `lintr::lint_package()`, `devtools::document()`.
- `lnk_artifact_probe()` writes about 260 FWA `probe` rows. Every `object` row has a `last_modified`.
- `bash data-raw/snapshot_bcfp.sh --force` writes 4 `loader` rows. **This reloads the four snapshot primitives in the
  local DB** (about 5 min).
- Round trip: for each recorded `version_id`, `curl -I <url>?versionId=<id>` returns 200 and the same `ETag`.
- Negative: an unreachable URL gives a NULL row and does not fail. With the stamp table emptied, `host_vintage.R` exits 1
  with `unstamped`; with stamps present, it exits 0.
- Carriage: `.lnk_log_inputs()` into a scratch schema puts identity on the run's row, and `fwa_obstructions_sp` is
  non-NULL.

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
