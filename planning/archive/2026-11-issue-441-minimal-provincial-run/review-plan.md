# Plan review — #441 (Plan agent, 2026-11-02 05:14 to 05:22 UTC, 66 reads)

Read against `data-raw/study_area_run.sh`, `study_area_remote.sh`, `study_area_hosts.sh`, `pretest*.R`, `R/lnk_pipeline_prepare.R`, `R/lnk_pipeline_run.R`, `R/lnk_persist_init.R`, `wsg_run_one.R`, `data-raw/logs/provincial_246/verify_extra.sql` and commit `0192b90c`. No blocker found for `--config=default_minimal --schema=fresh_default_minimal` at launch, given a clean borrowed history. All findings are folded into `task_plan.md`.

## Gaps

1. **Editing this worktree during the run corrupts the run's rows.** Only remote legs check that HEAD has not moved (`study_area_remote.sh:112`). Dispatcher groups stamp this worktree's HEAD and dirty state per group, and `study_area_verify.sql:487` raises on a second `link_sha`. The plan's "PWF pushed at each step" conflicted with "nothing edited". Folded: nothing edited or committed here, PWF included, until the driver exits.
2. **`--pick-only` warns where the launch check refuses.** `pretest_pick.R` (0192b90c, about line 100) gives `WARN (pick only)` for a history the range cannot cover; `pretest_record_check` refuses the same (`pretest.R:450-455`): a newest row with no `link_sha`, or a dirty or unknown `link_dirty`. Folded into PR 1 as a refusal in the pick, with a test. Checked at planning: all 241 newest rows on m1 are clean at `1d00c04c`.
3. **The first `lifts.R` design would not have measured observation lifts.** `barrier_overrides` has no source column (`lnk_persist_init.R:171`) and also holds habitat-classification and control lifts (`lnk_pipeline_prepare.R:585-619`); the per-group observation table is dropped when a build ends (`lnk_pipeline_run.R:207-211`); the union must include `barriers_orphan` (`prepare.R:787-805`); km must be measured on the full cut set (falls and definite cut too). Folded: rebuild the overrides with an empty observations table on a scratch copy of the working tables and call `link:::.lnk_pipeline_prep_minimal()`, never a copied SQL. Confirmed `working_<wsg>` keeps `gradient_barriers_raw`, `falls`, `barriers_definite` and `barrier_overrides` (`wsg_run_one.R:139`, `cleanup_working = FALSE`), so `lifts.R` runs before Phase 3 rebuilds BULK.

## Ordering

4. **What voids the gate is wider than modelling-path changes.** `study_area_run.sh`, `wsg_recompute_one.R`, `schema_consolidate.R` are mapped `unexercised` and only `none` passes (`pretest.R:513`); `data-raw/pretest*` is the gate's own rule set (`pretest.R:51,500`). Folded: the rehearsal check script lives under `data-raw/logs/`, and a driver fix re-runs the gate.
5. **Primitive refresh before #440's builds mixes code with data.** `zz432_post` was built on the 2026-10-25 loads. Folded: Phase 3 (#440 builds) before Phase 4 (refresh), stated as a decision at the gate.

## Assumptions

6. Cloud hosts snapshot whatever S3 holds at prep (`cypher_prep.sh:259`); m4 and m1 snapshot in Phase 4. A bcfishpass publish in between fails `verify_extra.sql` check 5 (line 74). Folded: compare S3's `log.json` with both ledgers just before launch.
7. A second full launch needs a new gate: finished rows at `RUN_SHA` become the history and are not ancestors of the gate's sha (`pretest.R:461`). `--recompute-only` skips the pre-flight (`study_area_run.sh:898`), so the partial-failure fallback holds.
8. A history schema holding only `log` gives the gate a scratch schema with only `log`; each pick's `lnk_persist_init()` creates the rest (`lnk_pipeline_run.R:255`). Not run in that shape before. Load with `pg_dump -t` so the key and indexes come. `host` exists at `1d00c04c` (`lnk_log.R:308`); the packer's minutes query has no config filter (`study_area_buckets.R:333`).

## Rehearsal

Four hosts need exactly four `--focal` lists (`study_area_run.sh:440-444`).

## Plan claims confirmed

- A detached HEAD is FATAL with remote hosts (`study_area_run.sh:481-487`); `main` is checked out in `~/Projects/repo/link`; the 439 branch is pushed and tracks origin.
- Version bumps and CITATION commits do not void the gate: `DESCRIPTION` maps to `none` (`pretest_inputs.csv:149`); NEWS and CITATION are outside the watched paths. A merge commit keeps the gate's sha an ancestor of the run's HEAD.
- `data-raw/logs` is excluded from the dirty and changed-file checks.
- `pretest_override.sql` has no `CREATE SCHEMA`, so `zz418_rehearsal` must exist first.
- The worker prior-rows check accepts a missing table (`study_area_hosts.sh:104-111`); the backup only needs a non-empty dump (`schema_consolidate.R:280`); the compare does not stop on `default_minimal` (segments starting at measure 0 always overlap bcfishpass, `lnk_compare_mapping_code.R:234-249`).
- `1d00c04c` is an ancestor of `origin/main`.
