# Code-check round 2 — link#369 branch (102762da...5ce5f331)

## Checklist read

- `index_code-check.md`: in full.
- `code-check.md`: prose of all 14 H3s under `## Mechanisms` (table rows skipped). None of the 23 headings under "Rules that stand alone", Security, or Spreadsheets/PDFs were read in full: none fit this diff closely enough to need it.
- `index_code-check-shell.md`: in full.
- `code-check-shell.md`, 10 headings: "`wait` with no argument…", "`if ! cmd; then rc=$?`…", "A second `trap … EXIT`…", "A `local` statement…", "A failed `cd`…", "`exit` inside a loop condition…", "Put cleanup on the EXIT trap…", "Parallel writers sharing one output file…", "`grep -c` prints the count…", "`for x in $(cmd | grep … || true)`…". The other ~65 were not read.
- `index_code-check-r.md`: in full (headings and first sentences).
- `code-check-r.md`, 10 headings: "An `information_schema` lookup…", "`system2(stdout = TRUE)`…", "`Rscript -e` supplies `--args`…", "`tryCatch()` nests…", "testthat counts an uncaught error…", "Postgres row order…", "A database driver's value…", "A `function(...)` mock…", "`on.exit()` at a script's top level…", "Under `R CMD check`, tests run…". The other ~105 were not read.
- `index_code-check-spatial.md`: first headings only. It does not apply to this diff.

## Findings

- **[fragile]** `data-raw/schema_consolidate.R:170-174` (`consolidate_missing_persist`), used at `:412-420`. The new refusal fires on every source-only table matching `streams_habitat_[a-z]+`, including a habitat table for a species outside this run's `cfg$species`. The dispatcher's pre-dispatch init (`study_area_run.sh:1360-1369`) creates habitat tables only for `cfg$species`. The cypher's `cypher_prep.sh` validates only those species and drops nothing else. So a cypher whose `$SCHEMA` still carries `streams_habitat_<sp>` from another config's build would be refused at stage `dest_missing_tables`:
  - Example: the image has `streams_habitat_ko`, `_rb` or `_gr` from a `default` build into `fresh`, and this run is `--config=bcfishpass --schema=fresh` against a dispatcher `fresh` without those tables.
  - That table holds no rows for the bucket, because the run never models that species. Before this change it was skipped with a NOTE and nothing was lost.
  - After it, the host is held, its groups are `not_consolidated` and left out of the recompute, and the run exits non-zero, all for a table that carries no data for the run.
  - The refusal fails safe: it comes before any DELETE. Its cost is a manual recovery of a whole host.
  - Not observed so far: the one source-only set in the committed 2026 consolidate logs (8 consolidates) is `streams_bt, streams_ch, streams_co, streams_habitat, streams_pk, streams_rb, streams_sk, streams_st, streams_v2`, and the pattern correctly ignores all of it.
  - Either of two changes would remove the risk: limit the habitat arm to the species of the run's config, or refuse only when the source table holds rows for the bucket.

No bug or security finding.

## Checked and found sound

**Round-1 fix (1), `${who:-}` and the 127 fallback** (`study_area_legs.sh:214-221`):
- `wait "$who"` on a pid that is not a child returns 127 immediately with a stderr line; it never blocks. Measured on bash 5.3.9.
- The leg is recorded with rc 127. For a cypher, `CY_RUN_RC` is 127, so `host_release` keeps it; this fails toward hold. For the dispatcher, `DISP_RC` is 127 with a WARN, and nothing reads `DISP_RC` beyond that.
- The fallback could block only if `wait -n` returned 127 while `pending[0]` is a live child. That costs delay, not data: the leg's real status is still read, and the other legs are taken on the next iteration.
- The driver traps no signal other than EXIT, so the >128 "trapped signal" case cannot occur.
- `wait -n -p` with a pid list returned neither an unlisted job nor one that had already been waited on (bash 5.3.9), so the loop cannot spin on a stray job. A job that is already done and listed is returned, and a re-reported one leaves `pending`.

**Round-1 fix (2), `CY_LEG_DONE`** (`study_area_legs.sh:144`):
- Its only reader is `burn_cyphers ended` (`study_area_hosts.sh:425`).
- A deferred host is held and its `CY_RUN_RC` is already set, so the EXIT trap (scope all) still keeps it and measures it as settled. Nothing else depended on the old timing.
- The test "a host deferred behind the dispatcher is not reported kept mid-run" goes red under the old placement: `a` would be in `kept_mid.tsv`.

**The R side:**
- `.lnk_schema_indexes()` and `.lnk_schema_columns()` fail toward issuing the statement. An empty or unreadable catalog behaves as before. `information_schema` hides only columns the role cannot see, and those are then issued.
- Index names live in the schema's relation namespace, so a name hit is exactly the case where `IF NOT EXISTS` would have been a no-op. No index name is near the 63-character truncation limit.
- In `lnk_persist_init()`, `have_idx` is read after the `force_recreate` drops, so a dropped table's indexes are recreated.
- `.lnk_log_create_tables()` (`lnk_persist_init.R:550`) is covered by the live lock test: the log tables are among those the holder session locks.
- The test helper `capture_ddl(…(NULL, …))` still captures every statement, because the NULL connection's catalog read errors and is caught.
- `lnk_artifact.R`'s call keeps the old behaviour (`have` defaults to empty), and it runs only from the recorder.
- `CREATE TABLE IF NOT EXISTS` and `CREATE OR REPLACE VIEW` take nothing that conflicts with a COPY's ROW EXCLUSIVE lock. The consolidate's own statements are DELETE, COPY, a temp table and INSERT, all row-level, on the bucket's rows.

**The copy check:**
- `pre_rows` is taken after the bucket DELETE (persist rows gone, log history kept), so any copied persist row is a strict increase.
- The bucket filter cannot see the dispatcher's own groups, except an overlapping one, and overlaps are deferred.
- `as.numeric()` on the integer64 `n` dispatches through bit64, which RPostgres imports.

**The driver:**
- `schema_consolidate_backup()` stops on a non-zero exit or an empty or missing file, and the path is unique per `TS`.
- The pre-run persist init uses the same species set as `lnk_pipeline_run()` (`cfg$species`, `R/lnk_pipeline_run.R:221`).
- The prep wait no longer waits on the backup pid. Dispatch waits on the backup's rc file.
- The init and backup are skipped on `--preflight-only` (exit at `:1261`) and on dispatcher-only runs.

**`study_area_legs.sh` / `study_area_finish.sh` in more detail:**
- The outcome rules hold:
  - a refused source is `failed:<stage>`;
  - a source that died or exited 1 after `ok` is `no_outcome`, stays `in_flight`, appears once in `CONS_FAILED`/`CONS_EXCLUDED`, and is not released;
  - `state_unwritten` writes no rows.
- The heredoc keeps `'\t'` as R's tab and `\$` as `$`, and the source list is substituted once and not re-expanded.
- `phases.tsv` rows are single appends, so a model leg's row written from its subshell does not interleave with the main shell's per-host rows.
- No main-shell `&` or bare `wait` sits between the dispatch and `legs_wait`. `burn_cyphers`' bare `wait` is inside its own subshell.

## Tests' ability to fail (notes, not defects)

- The `legs_wait` tests catch every rule they name:
  - Without the pending-list removal, the "each consolidated once" test double-copies or hits the 60 s timeout.
  - Without the overlap deferral, the deferred test fails (copy before the dispatcher ends).
  - Without the `ended` scope, the mid-run kept file lists `b`.
  - Reverting `${who:-}` makes set -u kill the script.
- `schema_consolidate()` itself is run by no test, because it needs ssh. The new tests pin only the pure helpers (`consolidate_bucket_count_sql`, `consolidate_missing_persist`) and `schema_consolidate_backup()`. Two reverts would leave the suite green: changing `pre_rows`/`post_rows` back to whole-table counts, or deleting the `dest_missing` block at `:412-420`. The same was true of the earlier `schema_consolidate()` wiring.
- Every `legs_wait` result above comes from bash 5.3.9, the only bash on this machine. The driver's stated floor is 5.1, and 5.1 and 5.2 are not exercised here. The dispatcher runs 5.3.
