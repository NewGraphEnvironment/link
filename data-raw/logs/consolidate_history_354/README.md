# Restoring the log rows #246's consolidate deleted (#354)

2026-10-17, local fwapg, `fresh_default`. Operator call at the #354 plan gate: restore.

Run `20261017_004619-3f4c713b`'s consolidate deleted each cloud-built group's earlier `log` /
`log_input` rows on the dispatcher. The driver's pre-consolidate backup
(`/tmp/fresh_default_pre_consolidate_202610162242.dump`, machine-local, taken after m1's own
groups and before the cloud hosts' were copied in) still held them. Against the current schema
(an anti-join on each table's primary key) it had exactly **5 `log` rows and 60 `log_input` rows** whose primary key was gone, and an
empty `log_recompute`:

| group | run_id | built | link |
|---|---|---|---|
| DUNC | `m1-20261012T153135.985-b33d3a` | 2026-10-12 | 0.63.1 |
| KOTL | `m1-20260827T145219.059-18b6fe` | 2026-08-27 | 0.45.1 |
| LARL | `m1-20260827T144852.009-9d37a9` | 2026-08-27 | 0.45.1 |
| PINE | `m1-20260806T184954.325-afdf9b` | 2026-08-06 | 0.44.3 |
| SLOC | `m1-20260827T145652.093-c69f2d` | 2026-08-27 | 0.45.1 |

PINE was not named in the issue; it was built on `cypher-job2` in the run and lost its August
row the same way. PARS had no earlier row. The later backup (`…_202610162328.dump`, taken
before the hand consolidate of the 18 groups) has nothing missing in any of the three tables,
so the 22:42 dump alone was complete.

- `restore_log_rows.sql` → `restore_log_rows.out`: additive `INSERT … ON CONFLICT DO NOTHING`,
  `log` 241 → 246, `log_input` 2,892 → 2,952, 12 `log_input` rows per restored build.
- `study_area_verify_after_restore.out`, `verify_extra_after_restore.out`: both pass at
  `run_uid=20261017_004619-3f4c713b`, `expected_n=241`.
- `lnk_log_read()`: 241 groups, all 241 newest rows from this run; 246 rows with
  `latest = FALSE`.

The persist rows of those old builds are not restored (operator, 2026-10-17: no floodplains
item needs them). The scratch schema `zz354_restore` was dropped after the restore.
