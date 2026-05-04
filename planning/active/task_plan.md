# Task: Gradient classes: derive from parameters_fresh, optional override arg (#45)

`R/lnk_pipeline_prepare.R` carries two coupled hardcodes that bake bcfishpass's
gradient-classification scheme directly into pipeline code:

1. **Hardcode #1** (lines 297-301) — the `c("1500"=0.15, "2000"=0.20, "2500"=0.25, "3000"=0.30)` vector passed to `fresh::frs_break_find()`.
2. **Hardcode #2** (lines 489-494) — the per-model class filter list `models <- list(bt = c(2500, 3000), ch_cm_co_pk_sk = c(1500, ...), ...)` consumed by SQL `WHERE gradient_class IN (...)`.

Both must change together. A user-supplied class vector outside the bcfp 0.15–0.30 range silently produces empty filters in Hardcode #2 (label mismatch). This PR exposes a `classes` override + derives the per-model filter from `loaded$parameters_fresh$access_gradient_max`. Bit-identical bcfp parity by default.

Once shipped, the user's experiment ("break the network at the union of unique rearing/spawning/access gradient values") is purely a config bundle that supplies a custom `pipeline.gradient_classes`. Schema isolation already in place per v0.26.0.

## Phase 1: Override threading + per-species filter

Functional core. Bit-identical bcfp parity preserved by default (no caller passes `classes` → falls back to hardcoded vector).

- [x] Add `classes = NULL` parameter to `lnk_pipeline_prepare()` signature (R/lnk_pipeline_prepare.R:86). Roxygen `@param classes` documents shape (named numeric vector; integer-encoded labels, gradient fractions).
- [x] Add `classes` arg to `.lnk_pipeline_prep_gradient()` signature (line 286). Replace hardcoded vector at lines 299-300 with the parameter.
- [x] In `lnk_pipeline_prepare()` body, resolve `classes %||% c("1500"=0.15, "2000"=0.20, "2500"=0.25, "3000"=0.30)` and thread to both `.lnk_pipeline_prep_gradient()` and `.lnk_pipeline_prep_minimal()`.
- [x] Add `cfg`, `loaded`, `classes` args to `.lnk_pipeline_prep_minimal()` signature (currently `conn, aoi, schema`).
- [x] Replace hardcoded `models` list (lines 489-494) with per-species derivation using `lnk_pipeline_species(cfg, loaded, aoi)` × `loaded$parameters_fresh$access_gradient_max`. Skip species with NA / zero / missing values. Per-species barrier tables become `barriers_<sp>` (e.g. `barriers_bt`, `barriers_ch`, `barriers_co`).
- [x] Update `tests/testthat/test-lnk_pipeline_prepare.R` lines 71-93 (`prep_gradient` mock): assert threaded `classes` appears in `frs_break_find` call.
- [x] Update `tests/testthat/test-lnk_pipeline_prepare.R` lines 206-237 (`prep_minimal` mock): expectation shifts from "4 per-model tables" to "N per-species tables" (N = species in bcfp config). Verify per-species filter logic (BT@0.25 → c(2500, 3000); CH@0.15 → c(1500, 2000, 2500, 3000)).
- [x] Add test for skip path: species with NA / zero `access_gradient_max` produces no barrier table.
- [x] `devtools::document()` to refresh man/.
- [x] `devtools::test()` clean.
- [x] `lintr::lint_package()` clean.
- [x] `/code-check` on staged diff. (3 fragile findings round 1 fixed: empty species → empty table fallback; `sp_amax[1L]` defensive coerce for R 4.3+ length-1 enforcement; `.lnk_validate_identifier` on lowercased species code. Round 2 clean.)

## Phase 2: Config knob

Lets variants declare break vectors at the bundle level without R code edits.

- [ ] In `lnk_pipeline_prepare()`, resolution order: `classes %||% cfg$pipeline$gradient_classes %||% <hardcoded bcfp vector>`. Coerce list-from-YAML to named numeric vector (`unlist()` + as.numeric).
- [ ] Test the resolution order: caller arg wins, then cfg, then fallback.
- [ ] Test YAML→R coercion round-trip (write a temp config, read it, confirm the named numeric vector shape).
- [ ] Document the optional knob in `inst/extdata/configs/bcfishpass/config.yaml` (and `default/`) as a commented-out optional with the implicit current value shown explicitly.
- [ ] `devtools::test()` clean.
- [ ] `/code-check` on staged diff.

## Phase 3: Bit-identical regression verification

- [ ] HARR single-WSG pre-flight (`link-tarmake-single HARR`) — confirm rollup matches pre-change baseline byte-identical (`digest::digest()` match).
- [ ] 4-WSG `tar_make` full run — same byte-identical assertion on rollup.
- [ ] Stamped log under `data-raw/logs/<TS>_link45_regression.txt` with env stamp + data snapshot timestamps.
- [ ] `gradient_barriers_minimal` row count per WSG: identical pre/post (per-species union must equal per-group union when `access_gradient_max` is consistent within bcfp groups).

## Phase 4: Release

- [ ] `NEWS.md` entry under 0.27.0 (override + per-species derivation; bit-identical to bcfp parity).
- [ ] `DESCRIPTION` version bump 0.26.0 → 0.27.0.
- [ ] Open PR with body referencing #45 + SRED tag (`Relates to NewGraphEnvironment/sred-2025-2026#24`).
- [ ] File follow-up: "Auto-derive `gradient_classes` default from `parameters_fresh$access_gradient_max`" (issue #45 scope item 1, separated).

## Validation

- [ ] Tests pass (mocks: existing + new)
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
