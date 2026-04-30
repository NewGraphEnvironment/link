# Task Plan — link#88: Fold subsurfaceflow into natural barriers

## Phase 1: Setup
- [x] File link#88 with diagnosis + proposed fix
- [x] Branch `88-fold-subsurfaceflow-natural` from main
- [x] PWF baseline (task_plan, findings, progress)

## Phase 2: Code change
- [ ] Extend `.lnk_pipeline_prep_natural(conn, aoi, cfg, loaded, schema)` to absorb subsurfaceflow body, gated on `"subsurfaceflow" %in% cfg$pipeline$break_order`
- [ ] Append subsurfaceflow rows to `<schema>.natural_barriers` (label `blocked`)
- [ ] Delete `.lnk_pipeline_prep_subsurfaceflow` helper
- [ ] Remove conditional call from `lnk_pipeline_prepare()`
- [ ] `devtools::document()` — refresh roxygen for prep_natural

## Phase 3: Tests
- [ ] `tests/testthat/test-lnk_pipeline_prepare.R`: subsurfaceflow opted in → INSERT into natural_barriers fires (mocked SQL shape)
- [ ] Same file: subsurfaceflow not opted in → no subsurfaceflow code path runs
- [ ] `devtools::test(filter = "lnk_pipeline_prepare")` clean

## Phase 4: Code-check
- [ ] `/code-check` on staged diff — fix any real findings, re-stage

## Phase 5: Verification
- [ ] HARR single-WSG pre-flight `tar_make` — log to `data-raw/logs/`
- [ ] Confirm blkey 356286055 BT rearing credits ~6.4 km (was 0)
- [ ] Full 15-WSG `tar_make` — log
- [ ] HARR/HORS/LFRA BT/CH/CO/ST rearing_stream within ±1%
- [ ] Default-bundle rollup numerically unchanged
- [ ] Reproducibility: second `tar_make` byte-identical to first

## Phase 6: Ship
- [ ] Atomic commits with PWF checkbox flips
- [ ] PR with `Fixes #88` and `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] Archive PWF after merge
