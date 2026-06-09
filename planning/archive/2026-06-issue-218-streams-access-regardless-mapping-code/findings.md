# Findings — lnk_pipeline_run: produce streams_access regardless of mapping_code (#218)

## Issue context

### Problem
`lnk_pipeline_run()` only computes `streams_access` when `mapping_code = TRUE` —
`lnk_barriers_views()` + `lnk_pipeline_access()` sit inside the `if (isTRUE(mapping_code))`
branch. Access is foundational (mapping_code depends on it, not the reverse), so
`mapping_code = FALSE` should still produce `streams_access` / `access_<sp>`.

### Proposed solution
- Always run `lnk_barriers_views()` + `lnk_pipeline_access()` in `lnk_pipeline_run()`.
- Gate only `lnk_pipeline_mapping_code()` (token assembly) behind `mapping_code`.
- Persist `streams_access` independently of `streams_mapping_code`.

## Exploration notes

- **Persist is already shape-tolerant.** `lnk_pipeline_persist()` copies
  `streams_access` and `streams_mapping_code` under separate `information_schema`
  probes — copies whichever working tables exist. No change required there.
- **Pre-persist coupling.** The mapping_code block opens with a pre-persist
  (`R/lnk_pipeline_run.R:188`) so `<persist_schema>.barriers` holds the current
  WSG before `lnk_barriers_views()` reads it (default source = persist barriers,
  for cross-WSG dam visibility — link#196). Hoisting access requires hoisting this
  pre-persist too.
- **mapping_code = TRUE path unchanged.** The refactor only moves the first three
  steps out of the gate; the execution order for `mapping_code = TRUE` stays
  pre-persist → barriers_views → access → mapping_code → final persist. Output is
  byte-identical → vignette parity (99.04% BT) stable.
- **Callers.** `wsg_run_one.R` (provincial runner) already TRUE. `wsg_pipeline_run.R`
  default FALSE → now gains access. `lnk_compare_wsg()` passes through.
- **Test contract change.** `test-lnk_pipeline_run.R:141` asserts default path
  ends at `persist` with no access — must be rewritten.
