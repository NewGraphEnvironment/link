# Task: lnk_pipeline_run: produce streams_access regardless of mapping_code (#218)

## Problem

`lnk_pipeline_run()` only computes `streams_access` when `mapping_code = TRUE` —
`lnk_barriers_views()` + `lnk_pipeline_access()` sit inside the
`if (isTRUE(mapping_code))` branch. Access is foundational (mapping_code depends
on it, not the reverse), so `mapping_code = FALSE` should still produce
`streams_access` / `access_<sp>`.

## Proposed solution (from issue)

- Always run `lnk_barriers_views()` + `lnk_pipeline_access()` in `lnk_pipeline_run()`.
- Gate only `lnk_pipeline_mapping_code()` (token assembly) behind `mapping_code`.
- Persist `streams_access` independently of `streams_mapping_code`.

## Key findings (from plan-mode exploration)

- `lnk_pipeline_persist()` already probes for `streams_access`
  (`R/lnk_pipeline_persist.R:146–181`) and `streams_mapping_code` (`:186–213`)
  with **independent** table-presence checks → no persist change needed.
- The pre-persist (step 0, `R/lnk_pipeline_run.R:188`) must move out with access:
  `lnk_barriers_views()` defaults to reading `<persist_schema>.barriers`
  (`R/lnk_barriers_views.R:52–55`), so the current WSG's barriers must be
  persisted before the views are built (cross-WSG dam visibility, #196).
- Stays gated: species-residence classification (`:241–248`) + `lnk_mapping_code()`
  (`:250–259`). Moves out: `lnk_presence` (`:175`), `barriers_per_sp` (`:213–216`),
  pre-persist (`:188–189`), `lnk_barriers_views` (`:197–198`), `lnk_pipeline_access`
  (`:218–230`).
- Blast radius small + intended: `data-raw/wsg_run_one.R:56` already passes
  `mapping_code = TRUE`. Only habitat-only callers (`wsg_pipeline_run.R` default,
  `lnk_compare_wsg(mapping_code = FALSE)`) gain access output.
- Vignette safe: renders from cached artifacts only (`eval = FALSE` pipeline
  chunk); `mapping_code = TRUE` sequence is byte-identical after refactor.

## Phase 1 — Hoist access out of the `mapping_code` gate
- [x] `R/lnk_pipeline_run.R`: move `lnk_presence`, `barriers_per_sp`, pre-persist,
  `lnk_barriers_views`, `lnk_pipeline_access` out of `if (isTRUE(mapping_code))`
  so they run unconditionally (after `lnk_barriers_unify`, before final persist).
  Keep species-residence classification + `lnk_mapping_code` inside a slimmer gate.
- [x] Update roxygen header (phase-order list, `@param mapping_code`) to say access
  is always built and only token assembly is gated. Re-`document()`.

## Phase 2 — Update + extend tests
- [x] Rewrite "composes phases in expected order" (`test-lnk_pipeline_run.R:141`):
  default path now includes pre-persist, `barriers_views`, `pipeline_access`, then
  final persist (two `persist` calls). Add mocks for `lnk_presence`,
  `lnk_barriers_views`, `lnk_pipeline_access`.
- [x] Add test: `lnk_pipeline_access` called for BOTH `mapping_code` values;
  `lnk_mapping_code` called only when `mapping_code = TRUE`.
- [x] Add new mocks to empty-species / dams / cleanup tests so they keep passing.

## Phase 3 — Verify + release
- [x] `devtools::document()`; `lintr::lint_package()` clean; `devtools::test()` green.
- [x] `tools::buildVignettes(dir = ".", tangle = FALSE, clean = TRUE)` exits 0.
- [x] `/code-check` clean → atomic commits (code + checkbox flip) per phase.
- [x] NEWS.md entry + `DESCRIPTION` bump 0.42.0 → 0.43.0 (final commit).
- [ ] `/planning-archive` → `/gh-pr-push` (PR body: `Closes #218`, SRED tag in PR body).

## Validation

- [x] `devtools::test()` green, incl. rewritten composition test + new gating test
- [x] `tools::buildVignettes` exits 0
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
