# Task Plan: Wire barriers_definite_control into lnk_barrier_overrides (#44)

## Goal

Honour `user_barriers_definite_control.csv`'s `barrier_ind = TRUE` rows at the observation-override step. Positions marked as non-overridable (known fish-blocking dams, long impassable falls, diversions) must never be re-opened by historical upstream observations. Matches bcfishpass's per-species access SQL.

Bit-identical-across-reruns reproducibility preserved. Rollup direction expected: toward bcfishpass reference, not away.

## Phase 1: lnk_barrier_overrides control filter fix

- [x] Read `R/lnk_barrier_overrides.R` control block. Confirmed: current filter treated ANY control row as blocking; docstring said only `barrier_ind = TRUE` rows block.
- [x] Updated `ctrl_filter` to `"AND (c.blue_line_key IS NULL OR c.barrier_ind::boolean = false)"`.
- [x] Updated the inline comment to describe the fixed semantics.
- [x] New test file `tests/testthat/test-lnk_barrier_overrides.R` with mocked SQL assertions — 7 tests covering observation-path control filter, NULL-control path, habitat-path control filter.
- [x] `devtools::test()` green: 265 PASS.
- [x] lintr clean on changed R/test files (only pre-existing indentation style notes, consistent with the rest of the codebase).
- [ ] `/code-check` before commit

## Phase 2: Wire control through .lnk_pipeline_prep_overrides

- [ ] Update `R/lnk_pipeline_prepare.R` `.lnk_pipeline_prep_overrides`:
  - Compute `control_arg <- if (!is.null(cfg$overrides$barriers_definite_control)) paste0(schema, ".barriers_definite_control") else NULL`
  - Pass to `lnk_barrier_overrides(..., control = control_arg, ...)`
  - **Manifest-driven** — not `information_schema` probe. `cfg$overrides$barriers_definite_control` is the contract.
- [ ] Add test to `tests/testthat/test-lnk_pipeline_prepare.R`:
  - `.lnk_pipeline_prep_overrides` with `cfg$overrides$barriers_definite_control` non-NULL → call carries `control = "<schema>.barriers_definite_control"`
  - `cfg$overrides$barriers_definite_control` NULL → call carries `control = NULL`
- [ ] `devtools::test(filter = "lnk_pipeline_prepare")` green
- [ ] Full `devtools::test()` green
- [ ] `lintr::lint_package()` — no new lints on changed files
- [ ] `/code-check` before commit

## Phase 3: End-to-end verification

- [ ] `pak::local_install()` to pick up the pipeline changes
- [ ] First run: `cd data-raw && Rscript -e 'targets::tar_destroy(ask = FALSE); targets::tar_make()'` → log under `data-raw/logs/20260423_01_tar_make_post_44.txt`
- [ ] Inspect new rollup; compare to pre-change baseline (run 12 from 2026-04-22). Direction must be toward bcfishpass on WSGs with controlled `barrier_ind = TRUE` rows.
- [ ] Reproducibility run: immediately re-run `tar_make()` → `data-raw/logs/20260423_02_tar_make_repro.txt`. Rollup must be bit-identical.
- [ ] `digest::digest()` on the two rollup tibbles → same hash

## Phase 4: Artifact updates

- [ ] Regenerate vignette data: `Rscript data-raw/vignette_reproducing_bcfishpass.R`. Produces new `rollup.rds` + `sub_ch.rds` + `sub_ch_bcfp.rds`.
- [ ] Render vignette locally to verify pivot tables + map update cleanly
- [ ] Update `research/bcfishpass_comparison.md`:
  - Four per-WSG parity tables with new numbers
  - Short paragraph under "Key fixes during comparison" documenting the control wiring + numeric direction
- [ ] `NEWS.md` 0.6.0 entry: "Honour `user_barriers_definite_control.csv` at the observation-override step. Previously controlled positions could be re-opened by upstream observations; now they can't."
- [ ] `DESCRIPTION` version bump 0.5.0 → 0.6.0

## Phase 5: Ship

- [ ] `/code-check` on full staged diff
- [ ] Commit atomically per the plan's commit layout
- [ ] Push branch
- [ ] Open PR with SRED tag `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] **File follow-up issue** (before closing PR 44): "Migrate remaining pipeline probes to manifest-driven gating". See `/Users/airvine/.claude/plans/stateful-hopping-feather.md` for scope.

## Versions at start

- fresh: 0.14.0
- link: main (0.5.0, target 0.6.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
