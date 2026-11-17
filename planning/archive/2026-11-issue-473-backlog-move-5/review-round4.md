# Code-check round 4: #473 (branch 473-backlog-move-5-the-habitat-export-s-cont)

## Checklist read

- code-check.md: under `## Mechanisms`, read the prose (table rows skipped) of "A guard that fails toward pass", "A fixture that cannot reach the failure mode", "A proxy is not the property", the opening of "Verification that reads its own output", "A guard's scope, escape hatches, and remedies", "Zero-length, empty, and unset are three different things", "Written data outlives the fix", "Serialization loses meaning silently" and "One fact derived twice". Not read in full: "A fix lands in one of two callers that share a harness", "Restore the bug and prove the guard fires", "A shared working tree, and what generators leave in it", "A wrapper's exit is not the work" and "The probe is broken before the world is" (index lines only), plus every heading under "Rules that stand alone" and the later sections (index only).
- code-check-r.md: index read. Checked against the diff from their index text: "`tryCatch()` nests its handlers, so a `stop()` in one is caught by a later one", "A `function(...)` mock hides arguments the real callee no longer accepts", "`system2(stdout = TRUE)` warns on a non-zero exit instead of raising…", "`$` on a list partial-matches…", "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "`load_all()` refuses an installed dependency below the `Imports:` floor…" and "Postgres row order is never fixed unless the query fixes it…". I did not open their full sections. The other headings (about 140) were not read.
- code-check-shell.md: index only. "`gh api` prints an HTTP error's body on stdout and exits 1, ignoring `--jq`" and "`aws s3 cp` cannot tell a missing key from a missing bucket" were checked against the aws calls. The rest (about 90 headings) were not read.
- code-check-spatial.md: index only. No heading names a pattern this diff uses beyond `ST_DWithin`/`ST_Transform`, which no heading covers, so none was read.

## What was checked

**Round 3's fix (`.lnk_part_fetch()` falls back to the current object):**
- It catches any error from the versioned read: AccessDenied, NoSuchVersion after lifecycle expiry, a network failure, expired credentials, or `aws` missing from PATH. In each case it then reads the current object.
- The size and md5 check that follows is unchanged, and it is the only exit to success. `part$md5` or `part$bytes` being NA fails `identical()` and refuses.
- So the fallback cannot hand back bytes other than the ones the manifest names. A real failure either fails the second read too, which raises that read's error after the `message()` naming the first, or ends in the "does not match the manifest's size and md5" stop.
- There is only one handler, so a stop raised in it is not re-caught.
- The https path unlinks a 4xx body before stopping, so the fallback starts from a clean file. Either path overwrites the `.part` file.
- The cache is keyed by key and judged by md5. A cached file of an older version is refetched, and a cached file with the right md5 is the right bytes, whatever version it came from.
- The same code serves every remote fetch: `lnk_db_load()`, `lnk_downstream_files()`'s dependency map (whose `version_id` is passed) and `lnk_downstream_load()`.

**The live bucket:** fresh-bc versioning reads `Enabled`. The 2026-11-14 objects (`barriers/config=default/part-ADMS.parquet` and `manifest.json`) carry real version ids, not `null`. So PUBLISH's `version()` will not stop part-way on group parts it skips as unchanged.

**The contract changes and their consumers, re-enumerated:**

- **`log.streams_md5`:**
  - Consolidate copies log tables by shared column name, after bringing the destination's log tables up to this link's columns.
  - Nothing copies `log` with `INSERT … SELECT *` between tables of different column order: `pretest_history_load.sh` goes through pg_dump, and `study_area_verify_negative.sh` uses scratch `CREATE … AS`.
  - The write-once `provenance/<run>/log.parquet` tolerates the new all-NA column (`.lnk_parquet_same`), so builds published at 0.82.0 re-export and re-publish unchanged.
- **`access` column:**
  - An old tree loads into a new table, and a table loaded before gains the column.
  - An old link refuses a new tree loudly.
  - Mixed contracts in one root are refused by `.lnk_manifest_previous()`.
  - Nothing else in `R/` or `data-raw/` reads segment parts by position.
- **The crate contract:**
  - The `.lnk_export_spec()` and `.lnk_export_cols()` callers are only the export, `lnk_db_load()` and the carry-forward. None of them is on the modelling path.
  - The removed `inst/extdata/schemas` file has no remaining reference.
- **`lnk_wsg_downstream_check()`:**
  - It is called by `wsg_run_one.R`, `wsg_recompute_one.R`, `recompute_readers_check.R` (warn mode, wrapped in tryCatch) and `habitat_variants_build.R`, and all of them read only `$status`, `$note` and `$elapsed_s`, plus `$steps_s` in `wsg_run_one.R`. `steps_s` is `numeric(0)` under `ignore` and prints as "".
  - `fresh::frs_wsg_drainage(conn, wsg, outlets)` has taken `outlets` since fresh v0.33.0, so the Imports floor (0.52.0) covers it.
  - All 246 outlet groups hold FWA streams in the full local load, so a complete database never reads a group as unloaded.
  - The local `fwa_watershed_groups_poly` has codes on all 246 rows. Where the codes are NULL (as the docker note in CLAUDE.md says), the count check sends the probe back to snapping every dam.
- **The new `[wsg_run_one] <WSG> downstream check …` line** does not match `host_log_reported()`'s `\[wsg_run_one\] [A-Z]{4} (done|SKIP)` or `study_area_finish.sh`'s `statement_timeout=` and `TIMEOUT after` patterns.
- **`.lnk_publish_refusals()`:** `[[""]]`, `NULL[[k]]` and `list()[[k]]` all return NULL, so a run with a missing config hash or thresholds map refuses rather than erroring.

## Clean
No issues found.
