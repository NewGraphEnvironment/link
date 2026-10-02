# Review — #286 Phase 1, round 1

Diff: DESCRIPTION (fresh floor 0.35.0, Remotes v0.36.2), R/lnk_db_conn.R (roxygen),
R/lnk_preflight_fresh.R (`required_formals`), data-raw/wsg_vignette_data.R
(`fresh::frs_db_conn()` -> `lnk_db_conn()`), tests/testthat/test-lnk_preflight_fresh.R.

## Clean

No issues found that could cause failures, security problems or data loss.

### What was checked

- `test-lnk_preflight_fresh.R` under `NOT_CRAN=true` + `load_all`: FAIL 0 / PASS 38.
  `lnk_preflight_fresh()` against installed fresh 0.36.2: ok, `missing_formals` = `chr(0)`.
- Installed `fresh::frs_habitat_classify` formals include `params_method` (default NULL ->
  bundled all-`cw` table), so link's current calls (which do not pass it yet) are unchanged.
- Validation edge cases: `required_formals = list()` passes (names NULL -> `nzchar(NULL)` is
  `logical(0)`, `all()` TRUE); an unnamed list is rejected; a partially named list is rejected
  by `nzchar("")`. `[[fn]]` is exact-match (no `$` partial match). `sprintf()` over an empty
  arg vector yields `character(0)`, so no phantom entry. `.lnk_fresh_message` gains a trailing
  defaulted arg; its only caller passes it.
- fresh v0.33.0..v0.36.2 R/ changes (`git diff --stat -- R`): frs_db_conn, frs_habitat,
  frs_habitat_classify, frs_habitat_predicates, frs_network_segment, frs_params, utils.
  - `frs_db_conn()`: no other live call site in link R/, data-raw/ or tests/ (only the one
    swapped here). `lnk_db_conn()` itself does not call it.
  - `frs_habitat_predicates(sp_params)` (lnk_habitat_validate.R:823): `model` defaults to
    `"cw"`; the cw SQL text is the same shape (`s.channel_width >= x AND s.channel_width <= y`,
    `s.gradient ...`), so `.lnk_hv_relax()`'s `\bs\.channel_width\b` / `\bs\.gradient\b`
    substitutions still match.
  - `frs_params(csv =, rules_yaml =)` (classify:91, connect:94, validate:803): no conn path,
    so the 0.36.0 env-var flip does not reach it. `mad` rule key now accepted instead of
    erroring — no link rules use it.
  - `.frs_sql_num()` now `unlist()`s and renders `Inf` as `'Infinity'::double precision`;
    finite numerics render identically.
  - `.frs_run_connectivity` (reached via getFromNamespace) is unchanged across the range.
- Remotes collision (code-check-r "Two repos pinning the same remote at different tags"):
  no other local NGE DESCRIPTION pins `fresh@<tag>`; breaks and flooded take it unpinned;
  crate and gq do not depend on fresh.
- `wsg_vignette_data.R`: on a machine without `PG_*_SHARE`, `lnk_db_conn()` now falls back to
  `PG*` (and connects) where old `frs_db_conn()` would have stopped; each `fetch_ctx()` is
  wrapped in `try()` and skips on error, so the script degrades rather than fails.

### Non-blocking notes (stale text, not defects)

- data-raw/wsg_vignette_data.R:210 — the skip message still says `frs_db_conn() unavailable`;
  the call is now `lnk_db_conn()`. Misleading to an operator reading the log.
- R/lnk_habitat_validate.R:819-821 and tests/testthat/test-lnk_habitat_validate.R:66-67 —
  comments say "fresh@v0.33.0 (the pinned minimum)". The floor is now 0.35.0, whose
  `frs_habitat_predicates()` does take `model`. The test still passes (it asserts a one-arg
  call), but its stated rationale is now false.
- CLAUDE.md:376 — "`PG_*_SHARE` env vars (Docker fwapg, same as `frs_db_conn()`)" is no longer
  true from fresh 0.36.0; the roxygen was corrected but this sentence was not.
- `.lnk_fresh_required_formals()` comment cites R/lnk_pipeline_classify.R as passing
  `params_method`; it does not yet (Phase 2/3). Expected per the plan, but the comment reads
  as current fact.
