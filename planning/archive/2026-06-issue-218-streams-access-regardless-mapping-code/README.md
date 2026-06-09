## Outcome

`lnk_pipeline_run()` now builds and persists `<persist_schema>.streams_access`
(+ `access_<sp>`) regardless of the `mapping_code` flag. The access build
(`lnk_presence` → pre-persist → `lnk_barriers_views` → `lnk_pipeline_access`,
plus the `sp_set`/`barriers_per_sp` locals) moved out of the
`if (isTRUE(mapping_code))` block to run unconditionally; only the mapping_code
**token assembly** (`lnk_mapping_code`) stays gated. Access is foundational —
mapping_code depends on it, not the reverse — so habitat-only callers
(`mapping_code = FALSE`) now also emit `streams_access`.

Key finding: **no persist change was needed**. `lnk_pipeline_persist()` already
probes `information_schema` for `streams_access` and `streams_mapping_code`
independently and copies whichever working tables exist — so satisfying the
issue's "persist streams_access independently" point was automatic. The
pre-persist (step 0) had to move out alongside access because
`lnk_barriers_views()` defaults to reading `<persist_schema>.barriers`
(cross-WSG dam visibility, #196), so the current WSG's barriers must be
persisted before the views are built. The `mapping_code = TRUE` execution order
stayed byte-identical, so the cached vignette parity (99.04% BT) is unchanged —
verified `tools::buildVignettes` exits 0 (vignette renders from cached
artifacts only, `eval = FALSE` pipeline chunk). Tests: rewrote the composition
test for the new call order and added a gating test asserting access builds for
both `mapping_code` values while `lnk_mapping_code` only runs when `TRUE`.
`/code-check` clean across 3 rounds.

Closed by: commits 681c7bd (hoist + tests) + 13026da (release v0.43.0) / PR TBD (Closes #218)
