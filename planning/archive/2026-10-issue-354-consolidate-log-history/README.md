## Outcome

`schema_consolidate()` deleted the destination's bucket from every table with a
`watershed_group_code` column, so the three log tables that carry one (`log`, `log_input`,
`log_recompute`) lost every earlier build of each cloud-built group. The log tables are now
named once in `.lnk_log_specs()`; consolidate deletes the bucket from persist tables only and
loads a log table through a one-transaction staged replace by primary key, so earlier builds
survive and a re-consolidate changes nothing. The plan's `run_key` became the full primary key,
which deletes only rows being rewritten. The plan review found the consequence that mattered:
with history kept, a group's newest log row is what names the build its persist rows hold, so
consolidate now refuses a source (nothing deleted) when a group has a destination log row and
the source's is older or absent. `lnk_pipeline_persist()` never touched the log tables; a test
pins it. The rows #246 had lost were restored from the driver's pre-consolidate dump.

## Measurement

- Lost in run `20261017_004619-3f4c713b`: 5 `log` rows (DUNC, KOTL, LARL, SLOC, and PINE, which
  the issue did not name) and their 60 `log_input` rows, 0 `log_recompute`. Restored:
  `fresh_default.log` 241 → 246, `log_input` 2,892 → 2,952. Both verify scripts pass at 241;
  `lnk_log_read()` still gives this run as newest for all 241 groups.
- Readers already handled history: `fresh.log` held 2–4 rows for 20 groups.
- Unprotected by the guard: groups with persist rows and no log row, 59 of `fresh`'s 98, 0 of
  `fresh_default`'s 241 (RUNBOOK §8d).
- Dropping `psql -1` fails closed (`relation "consolidate_in" does not exist`), measured.
- Restore-the-bug: five mutations (group-keyed DELETE, unsplit tables, unsplit DELETE list, no
  `-1`, guard off) each turn the tests red.
- Suite (local `devtools::test()`): 3,147 pass; 5 failures, all predating the branch
  (tunnel `:63333` down ×3, golden ADMS dams 8 → 7 ×2).
- Review: a plan review, then three `/code-check` rounds. Round 3 found a defect inside round 1's
  fix, and the loop ended by enumerating the 47 added lines that restate the rule (7 fixed;
  `findings.md`). Wrong turn kept: mid-run the suite was read as finished, from a timestamp that was my own
  appended `date -u`; `ps` showed R still running, and the wait was redone on the PID.

## Evidence

`data-raw/logs/consolidate_history_354/*`

Closed by: PR #355
