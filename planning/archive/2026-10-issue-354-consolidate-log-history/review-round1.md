# Code-check round 1 — branch 354 (schema_consolidate keeps log history)

Reviewer: unnamed subagent, 2026-10-17. Scope: `git diff main...HEAD` (branch.diff) plus full
reads of `data-raw/schema_consolidate.R`, `R/lnk_log.R` (specs/DDL), the three touched test
files, the callers in `data-raw/study_area_run.sh` / `wsgs_run_pipeline.sh` /
`study_area_hosts.sh`, and the log readers in `R/lnk_scenario_export.R` / `R/lnk_habitat_validate.R`.

## Verdict: code clean. One low-severity documentation inaccuracy.

## Findings

- **[severity: fragile (doc only)]** RUNBOOK.md:1274-1277, data-raw/study_area_hosts.sh:466-469 and :523-525.
  These say that consolidating a group the host "no longer holds (already consolidated, then
  deleted from the source) ... loses the dispatcher's copy of its persist rows". With this branch
  that case is now **refused**, not lossy. A successful consolidate copies the log tables and
  then its source cleanup (step 5, `copied_tables`) deletes the bucket's log rows on the source
  too. A re-consolidate of that group therefore finds a destination log row and no source row,
  and `consolidate_newer_on_dest()` refuses the source (`dest_log_newer`) before any DELETE. Only
  the "holds only in part" case (log row still on the source, persist rows partial) still loses
  the dispatcher's persist rows. The RUNBOOK passage goes on to describe the refusal, so the
  paragraph contradicts itself. The error is in the conservative direction and causes no data
  loss. Suggested wording: "...a group the host holds only in part loses the dispatcher's copy
  of its persist rows; one it no longer holds at all is refused (no log row on the source)."

## Checked and found OK (so a later round need not re-derive)

- The newest-log guard runs before the persist DELETE, and the `log_pk_unshared` guard too.
  Each `next`s with ok = FALSE, so neither can leave a bucket half-deleted.
- Parsing the source's newest values: I simulated the exact ssh/psql string through a local
  fake `ssh` (via = psql, read-only query on `fresh_default`). The `'\''` escaping comes through
  intact and the result parses to the right `data.frame`. Over all 246 `fresh_default.log` rows,
  RPostgres's double for `extract(epoch FROM date_start)` is identical to `as.numeric()` of
  psql's text, so the same build on both sides never compares as "newer". `date_start` is
  `timestamptz NOT NULL`, so `max()` is never NULL and the session timezone does not matter.
- If the source query fails (ssh or psql non-zero, exit status not checked), it reads as "no
  source rows". The source is then refused if the destination holds a row for any bucket group,
  and proceeds otherwise, when there is nothing to protect. So it fails closed; only the log
  message would be misleading.
- A source whose schema has no `log` table skips the newest guard (`"log" %in% split_tables$history`
  is FALSE). That is the pre-#354 behaviour, and every host that runs `lnk_persist_init()` has
  the table, so I did not raise it as a finding.
- `consolidate_history_sql()` under `psql -X -1 -v ON_ERROR_STOP=1 -f` is one transaction:
  temp table, `\copy`, DELETE by full PK, INSERT. The live test proves it fails closed both
  without `-1` and on a malformed row. An empty TSV (e.g. a cypher's empty `log_recompute`) is a
  clean no-op.
- `pre_rows`/`post_rows` semantics are unchanged in effect: persist tables are still deleted,
  so a real copy still raises the count.
- Driver paths: `study_area_run.sh` runs `pkgload::load_all()` before sourcing, so
  `link:::.lnk_log_specs` resolves. `wsgs_run_pipeline.sh` uses `library(link)`, so it needs
  an installed link with the new helper; until then it errors at step 3.5, before any DELETE
  (fails closed).
- The bucket fed in by `study_area_run.sh` (`host_consolidate_bucket` = database finished ∪ log
  done) always has a source log row per group, so the guard does not refuse a normal run.
- Restore: `fresh_default.log` 246 rows / 241 groups, `log_input` 2,952, 0 orphan `log_input`
  rows. The 5 restored rows are `config_name = default` and closed, so the newest-row readers
  (`.lnk_export_runs`, `lnk_habitat_validate`) are unaffected. This matches
  `restore_log_rows.out`.
- `NULLS LAST` edits in the two diagnostic scripts are correct.
- Tests (in a temp copy, `NOT_CRAN=true`, live DB): test-schema_consolidate.R 7/7 pass (live
  block ran), test-lnk_pipeline_persist.R 9/9 pass, test-lnk_log.R 295 pass / 0 fail.
