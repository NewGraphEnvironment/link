# Findings — Backlog move 9 (#477)

## Issue context

**If we do it:** mapping-code tokens come from a rules file, the persist functions form one family, and a failed run cleans up its working schema. **If we never do:** each new token is a code change and the API keeps its old seams.

Move 9 of link's backlog, [`planning/backlog.md`](../blob/main/planning/backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

## Batch 12: Mapping codes as rules

**Why here:** one parity run shows the output unchanged.

#197 (mapping-code second tokens from a rules CSV, not hard-coded chains), #153 (presence definitions for mapping codes: absent species read `""`), #191 (tests for `lnk_mapping_code()`, `lnk_pipeline_mapping_code()` and the deprecation shims) and #351 (`lnk_access(merge = TRUE)` turns an absent species' -9 into 1, and `lnk_mapping_code(presence = NULL)` errors). Touches `R/lnk_pipeline_mapping_code.R`, `R/lnk_mapping_code.R`, `R/lnk_access.R` (the merge CASE), new tests. Gate: `""` for an absent species is the design. One parity run shows the output unchanged.

| issue | title |
|---|---|
| #197 | mapping_code rules engine: config-driven token classification (replace hardcoded R case-when) |
| #153 | lnk_pipeline_species vs lnk_presence: align presence definitions for mapping_code parity |
| #191 | Add unit tests for v0.40.0 surface (lnk_mapping_code, persist additions, pipeline_run mapping_code phase, deprecation shims) |
| #351 | lnk_access(merge = TRUE) turns an absent species' -9 into 1; lnk_mapping_code(presence = NULL) errors |

## Batch 13: The persist and run API

**Why here:** one release carries the deprecations.

#177 (`lnk_persist_{init, write}`: rename `lnk_pipeline_persist`), #176 (`lnk_compare_wsg()` to `lnk_compare_run()`), #159 (`lnk_pipeline_run()` drops its working schema only on success; clean up on error) and #204 (`lnk_persist_init()` checks only generated columns, so species-column drift passes). Touches `R/lnk_pipeline_persist.R`, `R/lnk_pipeline_run.R`, `R/lnk_compare_wsg.R`, `R/lnk_persist_init.R`, NAMESPACE, tests. Gate: deprecation shims or hard renames; #204 extends the column check that single #169 would remove, so decide which. One release carries the deprecations.

| issue | title |
|---|---|
| #177 | Reshape persist family: lnk_persist_{init, write} instead of split across pipeline + standalone |
| #176 | Rename lnk_compare_wsg() -> lnk_compare_run() for family symmetry |
| #159 | compare_bcfishpass_wsg / compare_bcfp_mapping_code: wrap per-WSG body in tryCatch finally to clean up working schema on error path |
| #204 | Persist+consolidate must be host-/species-count-agnostic: persist_init blind to species-column-set drift |


## Member issues read 2026-11-27

- #512 (rest of #189) names move 9 as its home but was not in the member table; folded in at the gate.
- #159's drivers (`compare_bcfishpass_wsg`, `compare_bcfp_mapping_code`) no longer exist; the live form is `lnk_pipeline_run()`.
- #153's `data-raw/compare_bcfp_mapping_code.R` workaround no longer exists; `lnk_mapping_code()` already pre-allocates missing habitat columns as 0.
- No `test-lnk_pipeline_mapping_code.R` exists; the v0.41.0 aliases are still accepted at 0.94.0.

## Errors Encountered

| Error | Resolution |
|-------|------------|
