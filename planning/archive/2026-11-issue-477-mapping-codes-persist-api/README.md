## Outcome

Backlog move 9 (#477) landed as one release, 0.95.0: #197, #153, #191, #351, #512 (folded in at the gate), #177, #176, #159, #204. The mapping code's barrier token is a bundle's `parameters_mapping_code_rules.csv` (package copy as the fallback) under a five-alias grammar; the exported mapping-code functions read residence and rules from `cfg`; `lnk_access(merge = TRUE)` keeps `-9`; a named logical presence works; a missing habitat column reads 0; `lnk_pipeline_persist()` → `lnk_persist_write()` and `lnk_compare_wsg()` → `lnk_compare_run()` with no shims and the v0.41.0 aliases removed; `lnk_pipeline_run(cleanup_working = TRUE)` drops its working schema on an error after setup; `lnk_persist_init()` adds a missing species' wide-table columns. The Plan review's four blockers (the old chains end on `!any_anth`, not `TRUE`; #159's drop hung on the log-only handler; NULL species sets emptied `lnk_mapping_code()`'s own species set; the pretest map named the old files) were all folded in before code. The lint pass caught the rename merging `.lnk_compare_wsg_rollup_link` into the existing `.lnk_compare_rollup_link`; it is now `.lnk_compare_rollup_working`. `/code-check branch` ran three rounds (one stale name in CLAUDE.md, fixed); verdict clean. Mechanics: RUNBOOK §4, §6, §7.

## Measurement

- Mapping codes of eight groups (ADMS, BULK, ELKR, HORS, PARS in `fresh_default`; BULK, ELKR, PARS in `fresh`) rebuilt from persist at `82cf1d08` and at the branch, back to back: 36 of 36 digests identical. No persisted `access_<sp>` is `-9` in either schema (19 columns), so the #351 merge change persisted nothing. A probe right after the rules engine landed (Phase 2) was also 0 of 36 different.
- The shipped rules equal the 0.94.0 chains on all 32 alias combinations and on a 3^6 raw-column grid (TRUE/FALSE/NA) over every subset of the fallback columns.
- `devtools::check()`: 0 errors, 0 warnings, 3 notes, all on main. Each new guard's tests fail with the guard disabled (merge `CASE` 3, fallthrough 1, alias walk 3, error-path drop 1, drift add 7).
- Round 2 of the review measured `.lnk_wide_species_align()` against a held lock: the ALTER waited 29.99 s, stopped with the quiet-time message, and left the connection usable with `lock_timeout` back to 0.

## Evidence

`data-raw/logs/mapping_code_rules_477/` (its README).

## Owed

- The re-model #479 already owes also settles `config_hash` for `default`, `bcfishpass` and the bundles extending them, but only if it starts after 0.95.0 merges; one started earlier leaves them reading as another bundle.
- Each host's wide tables checked, or `lnk_persist_init()` run once at a quiet time, before the next run that adds a species (the ADD COLUMN takes an ACCESS EXCLUSIVE lock).
- The pre-run gate runs again before the next provincial run (`R/` and `inst/extdata/` changed).
- Hosts and jobs calling `lnk_pipeline_persist()` or `lnk_compare_wsg()` outside this repo move to the new names.
- Outside this diff (code-check round 3): 0.93.0 deleted `R/lnk_score.R`, `R/lnk_source.R`, `R/lnk_thresholds.R` and `inst/extdata/thresholds_default.csv` and dropped their `pretest_inputs.csv` rows, so the pre-run gate over a range from `fresh_default`'s builds refuses on them until rows are kept for them, as for `inst/extdata/schemas/`.

Closed by: PR for branch `477-backlog-move-9-mapping-codes-as-rules-an`
