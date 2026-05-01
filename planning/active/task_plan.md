# Task Plan — link#88: Fold subsurfaceflow into natural barriers

## Phase 1: Setup
- [x] File link#88 with diagnosis + proposed fix
- [x] Branch `88-fold-subsurfaceflow-natural` from main
- [x] PWF baseline (task_plan, findings, progress)

## Phase 2: Code change
- [x] Extend `.lnk_pipeline_prep_natural(conn, aoi, cfg, loaded, schema)` to absorb subsurfaceflow body, gated on `"subsurfaceflow" %in% cfg$pipeline$break_order`
- [x] Append subsurfaceflow rows to `<schema>.natural_barriers` (label `blocked`)
- [x] Delete `.lnk_pipeline_prep_subsurfaceflow` helper
- [x] Remove conditional call from `lnk_pipeline_prepare()`
- [x] `devtools::document()` — refresh roxygen for prep_natural

## Phase 3: Tests
- [x] `tests/testthat/test-lnk_pipeline_prepare.R`: subsurfaceflow opted in → INSERT into natural_barriers fires (per-statement assertion)
- [x] Same file: subsurfaceflow not opted in → no subsurfaceflow code path runs
- [x] Same file: subsurfaceflow honours barriers_definite_control
- [x] `devtools::test(filter = "lnk_pipeline_prepare")` clean (44/44 PASS)

## Phase 4: Code-check
- [x] `/code-check` on staged diff — 3 rounds. Round 3 caught fragile cross-statement regex; tightened to per-statement `any(grepl & grepl)`. Final clean.

## Phase 5: Verification
- [x] HARR single-WSG pre-flight `tar_make` — `data-raw/logs/20260430_11_preflight_harr_link88.txt`
- [x] blkey 356286055 BT rearing credits **6.509 km** (was 0)
- [x] Full 15-WSG `tar_make` — `data-raw/logs/20260430_12_tar_make_15wsg_link88.txt` (53m 2.2s, 33/33 targets)
- [x] HARR CH/CO/ST rearing_stream closed to ±0.32% (BT residual -4.2%, separate mechanism noted)
- [x] LFRA CH/CO/ST closed to ±0.6% (BT residual -3.75%)
- [x] HORS unchanged (-7.68% BT) — different mechanism, follow-up issue
- [x] Default-bundle rollup bit-identical (0 of 581 link_value rows changed)
- [ ] Reproducibility: second `tar_make` byte-identical to first (running)

## Phase 6: Ship
- [ ] Atomic commits with PWF checkbox flips
- [ ] PR with `Fixes #88` and `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] Archive PWF after merge
