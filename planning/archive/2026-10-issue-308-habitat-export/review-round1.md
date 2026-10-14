# Code-check round 1: #308 habitat export (branch diff main...HEAD)

Reviewer: subagent, 2026-10-14. Read in full: R/lnk_scenario_export.R, R/lnk_catalog.R,
R/lnk_db_load.R, the .lnk_config_files split in R/lnk_log.R, data-raw/habitat_publish.R,
data-raw/logs/habitat_export_308/verify.R, RUNBOOK §6d. Probes were read-only queries against
local fwapg plus throwaway R/duckdb snippets in the scratchpad; nothing in the repo was edited
except this file.

## Findings

- **[severity: fragile]** R/lnk_scenario_export.R:403-417 (`.lnk_write_once`), with :444-489 and
  :848-865. Write-once compares the md5 of a **re-serialisation**, not the record, so an
  unchanged build stops the export for reasons that have nothing to do with the build:
  1. **The duckdb version is in the bytes.** A duckdb Parquet footer carries
     `created_by = "DuckDB version v1.5.2 (build 8a5851971fa)"` (measured with
     `parquet_file_metadata()`). After any duckdb upgrade, or on a host with another duckdb,
     every existing `provenance/*.parquet` re-renders with other bytes, and re-exporting any
     config already in the root stops with "already written with different content". The
     PUBLISH side has the same failure: a root built on another machine has provenance files
     whose md5 differs from the S3 ETag, so habitat_publish.R:149-151 stops.
  2. **`source_artifact.parquet` is today's table, not the run's.**
     `provenance.source_artifact` is upserted on `(host, table_name, url)`
     (`R/lnk_artifact.R:292`, `ON CONFLICT ... DO UPDATE`), and `data-raw/artifact_record.R:76`
     deletes and re-inserts loader rows. The export copies
     `SELECT * ... WHERE host = ANY(<run hosts>)` (:469-476), and every `fresh_default` run is
     on host `m1`, the host that holds those rows. So the first `snapshot_bcfp.sh` after an
     export (CLAUDE.md says one `--force` is due once #265 lands) changes the file, and the
     next export of the same, unchanged run stops. The file also records the primitives as of
     the export, filed under the run's key as if they were the run's. The run's own record is
     `log_input.artifact_*`, which is already in `log_input.parquet`. The manifest's discharge
     copy (:810-812) carries a scope disclaimer; this copy has none.
  3. **`SELECT *` from `log` / `log_input` / `log_parameters_*`.** A later link that adds a log
     column (as #262, #305 and #282 each did; `.lnk_log_align_columns` adds it to existing
     tables) changes the bytes for every previously exported run. A dispatch exported while
     some of its other groups are still open (`date_end` NULL, or `notes` appended by
     `.lnk_log_run_fail`) does the same once they close: the file holds every group of the
     `run_uid`, not only the exported ones.

  Because "provenance is never deleted", each of these leaves the config impossible to
  re-export without a manual delete. Options: compare the records rather than the files (read
  the existing Parquet back and compare rows on the original columns), or treat an existing key
  as final and skip it. In either case, drop the host-scoped `source_artifact` copy from the
  per-run provenance, or take it from `log_input`.

- **[severity: bug]** R/lnk_scenario_export.R:302-311 with :673-678. A config can name several
  schemas holding different groups (documented at :631-632), but an explicit `wsgs` is passed
  unchanged to `.lnk_export_runs()` for **each** schema. There every named group the schema does
  not hold is `absent`, which stops the export. So
  `configs = c(default = "s1", default = "s2"), wsgs = c("A", "B")`, with A in s1 and B in s2,
  always stops with "B (not in streams)". The two documented features cannot be used together.
  Pass each schema only the named groups it holds, and stop only on a group no schema holds.

- **[severity: bug]** R/lnk_scenario_export.R:582-583 (manifest written with
  `auto_unbox = TRUE`). Every vector-valued field in the published manifest changes JSON type
  with its length: one element is written as a scalar and two or more as an array. Measured
  with jsonlite on the same shapes:
  `{"wsgs":"DUNC"}` against `{"wsgs":["A","B"]}`, and per run
  `"species":"BT"` against `"species":["BT","CH"]`, `"recompute_keys":[]` against
  `"recompute_keys":"p/1"`.
  The affected fields are `configs[].wsgs`, `species`, `schema_persist`, `run_uids` and
  `config_hashes`, and per run `species`, `wsg_upstream` and `recompute_keys`. Within one
  manifest the `runs` rows can mix the two forms. Any non-R reader of this contract that
  iterates `species` gets the characters of `"BT"`. R callers that use `length()` happen to
  work: the report's `length(r$recompute_keys)` returns 1 either way for a single key. Wrap
  array-typed fields in `I()`, or use `as.list()` for character vectors and list columns, so
  they are always arrays.

- **[severity: fragile]** data-raw/habitat_publish.R:135-153. Parts are put, overwriting their
  live keys, **before** the write-once check on `provenance/` and `config/`. A conflict there
  is a predictable stop: finding 1 makes one likely after any duckdb change or a rebuild on
  another host. When it stops, the bucket is left with new part bytes under the old
  `manifest.json`, whose md5s no longer match. Every `lnk_db_load()` from the live manifest
  then fails its md5 check until someone fixes it by hand. Run the `files` ETag check (head
  every key, refuse on any mismatch) before the first part is put. Separately, the head-then-put
  is not atomic: `put-object --if-none-match '*'` makes the write itself the check.

- **[severity: fragile]** data-raw/habitat_publish.R:161-172. Stale-key deletion trusts the
  local manifest as the complete list of published configs. PUBLISH from a root that never held
  a config which is live in the bucket (a new checkout, a fresh `--root`, or a root built with a
  subset) deletes that config's parts from `segment/` and replaces the manifest without it. The
  header comment asks operators to build into the published root, but nothing enforces it.
  Read the live manifest first, and refuse when its configs are not a subset of the local
  manifest's (or require an explicit flag to drop a config).

- **[severity: fragile]** R/lnk_scenario_export.R:708-710. The config's
  `segment/config=<cf>/` tree is deleted before any rows are queried. Any failure after that
  point (a `.lnk_export_rows` fan-out stop, a missing habitat table, a write-once stop in
  provenance) leaves `manifest.json` listing parts that no longer exist. The next export of a
  *different* config then stops in `.lnk_manifest_previous()` ("missing or changed"), and a
  PUBLISH from that root fails `verify_tree`. Both fail loud, but the root needs a full
  re-export of the deleted config to recover. Write the new parts to a staging directory and
  swap them in after the manifest is ready, or delete only after the rows succeed.

- **[severity: fragile]** R/lnk_catalog.R:45. `base <- sub("/[^/]*$", "", manifest)` leaves a bare
  relative filename unchanged, so `lnk_catalog("manifest.json")`, run from inside the root, gives
  hrefs like `manifest.json/segment/...`, and `lnk_db_load()` then stops because the md5 file
  is missing. Use `dirname()` for local paths.

Checked and not flagged (with the reason):
- Threshold CTE fan-out: `log_parameters_*` are keyed `(config_hash, species_code)`.
- int32 casts: the FWA maximums are `linear_feature_id` 868,144,683 and `blue_line_key`
  380,887,830.
- The `.lnk_config_hash()` split keeps the same payload and radix order.
- Bundle keys: shipped configs give no absolute, `..` or duplicate `rel`.
- `system2` argument quoting: `shQuote` is present in both `.lnk_aws` and the driver's `aws()`.
- `lnk_db_load` atomicity: it fetches and verifies before the transaction, then DELETE, insert
  and PK run inside it.
- Catalog attributes survive row subsetting.
- Recompute attributes survive `$<-`.

Assumption, not a finding: the PUBLISH ETag comparison (`identical(e, f$md5)`) holds only where
a single-PUT ETag is the MD5, which is true under SSE-S3. If `fresh-bc` defaults to SSE-KMS,
every existing file reads as a conflict. Check the bucket's encryption once.
