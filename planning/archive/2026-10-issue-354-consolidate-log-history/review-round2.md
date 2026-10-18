# Code-check round 2 — branch `354-schema-consolidate-deletes-the-destinati` (#354)

Reviewed 2026-10-17: the whole branch (`git diff merge-base...HEAD`, commits 0a1f8534..1ccfafe5), with attention to round 1's fixes in 1ccfafe5.

## Clean

No issues found.

## What was checked, and how

- **The round 1 fixes are correct.**
  - The `source_log_query` stage: `system(intern = TRUE)` sets `attr(, "status")` only on a non-zero exit, and the branch reads it before parsing. I simulated the guard's quoting with `sh -c` in place of ssh, using the same `gsub("'", "'\\''")` escape. A good query returned `GROUP|epoch` lines with a NULL status. A query on a missing relation returned `character(0)` with status 1.
  - The corrected docs (RUNBOOK §8d, the `study_area_hosts.sh` comment and `hosts_kept_report` echo) match the code. A group consolidated and then cleaned from the source has no source log row: step 5 deletes `copied_tables`, and the log tables are among them. The dispatcher still has that group's row, so the source is refused with `dest_log_newer`, and the refusal comes before step 3.5's DELETE.
- **End to end, in a temp copy of the repo with a fake `ssh` on PATH** (the fake rewrites the schema name and runs the command locally). Scratch schemas `zzr2_a` (destination) and `zzr2_b` (source), dropped afterwards, `keep_source = TRUE`:
  - normal (destination row older): `ok`, persist replaced, BULK outside the bucket untouched, both log rows kept;
  - destination row newer: `dest_log_newer`, persist and log untouched;
  - source has no log row: `dest_log_newer`, untouched;
  - destination has no log row: `ok`;
  - source log query exits non-zero: `source_log_query`, untouched.
- **Precision of the guard's comparison.** The destination value comes through RPostgres as `numeric` and the source value is psql text. On all 241 `fresh_default` groups the two are equal, with 0 mismatches (read-only), so the same build never compares as newer.
- **Parsing edge cases.** An empty source result gives a 0-row frame, and `merge(all.x = TRUE)` then refuses every destination group. A line with a missing epoch (`"A|"`) parses to NA and is refused. A 0-row destination refuses nothing. `date_start` is NOT NULL, so `sort()` dropping NA cannot hide a group.
- **Stage 2 / the history SQL.**
  - `-1` with `ON_ERROR_STOP` rolls the replace back as a whole.
  - Without `-1`, `ON COMMIT DROP` makes the script fail closed. The live test covers both.
  - The log tables have no unique index other than the primary key (the `idx` list in `.lnk_log_create_tables()`).
  - `consolidate_dest_delete_sql()` returns `character(0)` when there are no persist tables, so the zero-length `sprintf` case is right.
- **Ordering.** The newest-log check, the source-query check and `pk_unshared` all `next` before any DELETE. A resumed consolidate after a partial failure has equal newest values on both sides (the log was copied, the source was not cleaned) and proceeds, as intended.
- **The driver path** (`study_area_run.sh`). The consolidate bucket is the database-finished set ∪ log done (`host_consolidate_bucket`). Every member therefore has a source log row from this run, so normal runs are not refused. Any `ok = FALSE` exits 1 and keeps every cypher (the existing behaviour).
- **Readers of a group's history.** The other `<schema>.log` readers pick the newest row by `date_start DESC` (`lnk_scenario_export`, `lnk_habitat_validate`, `habitat_variants_build.R`), or aggregate (`habitat_validate.R`), so the restored second rows do not change what they read. The two `date_end DESC` readers gained `NULLS LAST`.
- **The restore.** The live DB has `fresh_default.log` at 246 rows over 241 groups; DUNC, KOTL, LARL, PINE and SLOC have 2 rows each. `log_input` has 2,952 rows and no orphan `log_input` row. These match the README and CLAUDE.md.
- **Tests.** In a temp copy with `NOT_CRAN=true`: `test-schema_consolidate.R` 26 pass, `test-lnk_log.R` 295 pass, `test-lnk_pipeline_persist.R` 23 pass; 0 fail, 0 error, 0 skip.
- **Checklist items checked against the diff:**
  - `on.exit` at top level: not used.
  - `system2`/`system` status read off the attribute: done.
  - psql `:'var'` / `\quit`: not used.
  - `paste`/`sprintf` with zero-length input: handled.
  - `$` partial matching: none.
  - Escaping of the shell and SQL quoting: checked by running it.
  - A guard that fails toward pass: none found, apart from the accepted no-`log`-table skip.
  - The restore is additive, with `ON CONFLICT DO NOTHING`.

The repo was not modified, apart from this file.
