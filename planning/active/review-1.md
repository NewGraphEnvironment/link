# Plan review 1 (Plan agent, 2026-10-17) — findings and dispositions

Spawned after the baseline; it reported after Phases 1–5 had landed, so it reviewed code and plan.

| # | Class | Finding | Disposition |
|---|---|---|---|
| 1 | Gap | With history kept, a dispatcher log row newer than the source's would name a build the persist tables no longer hold (persist carries no run id; readers take the newest row). | **Fixed.** `consolidate_newer_on_dest()`: a source is refused (`dest_log_newer`, nothing deleted) when any bucket group's newest destination log row is newer than the source's, or the source has none. RUNBOOK §8d. |
| 2 | Gap | The loop's use of the split and the `-1` flag were untested; reverting the loop to `wgc_tables` stayed green. | **Fixed.** `consolidate_dest_delete_sql()` and `consolidate_stage2_cmd()` carry both, tested; mutations go red. Dropping `-1` measured to fail closed (temp table gone before `\copy`), tested live and commented. |
| 3 | Gap | Tests run only under local `devtools::test()` (data-raw is build-ignored; no R-CMD-check workflow). | **Recorded** in Validation. |
| 4 | Gap | `ORDER BY date_end DESC` puts an open (NULL) row first in two diagnostic scripts once history keeps failed attempts. | **Fixed.** `NULLS LAST` in `habitat_diff_segments.R`, `query_habitat_thresholds_fiss.R`. |
| 5 | Gap | `.lnk_log_specs()` doc says "nowhere else", but `lnk_persist_init()` hard-codes a log list. | **Fixed (doc).** Softened; changing persist-init's drift check is outside #354. |
| – | Assumption | Stage 2 lacked `-X`. | **Fixed** for both branches. |
| – | Assumption | `restore_log_rows.sql` `SELECT *` is positional; record how scratch tables were made; state the rows were absent before. | **Fixed** in the script header and README. |
| – | Assumption | `dunc_default_328/verify.R` asserts one DUNC log row. | **Noted** in that README as a dated record. |
| – | Scope | `data-raw/README.md` described the pg_dump flow; `study_area_hosts.sh` banners. | **Fixed.** |
| – | Ordering | 23:28 dump checked too: nothing missing; the 22:42 restore was complete. | Recorded in the evidence README. |
| – | Blocker | `pg_restore -t` "into a copy" cannot remap a schema. | Already avoided by the landed route (sed on the COPY target). |
