# Progress — link#88

## Session 2026-04-30

- Diagnosis: traced HARR blkey 356286055 BT under-credit to subsurfaceflow positions on downstream tributary 356282804 not reaching `natural_barriers` for the per-species observation/habitat lift.
- Read bcfp SQL (`model_access_bt.sql`, `model_access_ch_cm_co_pk_sk.sql`) — confirmed bcfp's natural-barrier union includes subsurfaceflow with same lift rules.
- Confirmed default-bundle off-switch is preserved verbatim (omit `subsurfaceflow` from `cfg$pipeline$break_order`).
- Filed link#88 with diagnosis + proposed fix.
- Branch `88-fold-subsurfaceflow-natural` from main.
- PWF baseline (commit 4bd9ca0).
- Code change: extended `.lnk_pipeline_prep_natural` signature `(conn, aoi, cfg, loaded, schema)`; absorbed subsurfaceflow body, gated on `cfg$pipeline$break_order`; deleted standalone `.lnk_pipeline_prep_subsurfaceflow`; pruned conditional call from `lnk_pipeline_prepare()`. `devtools::document()` clean.
- Tests: 3 new test cases in `tests/testthat/test-lnk_pipeline_prepare.R` — opted-out, opted-in (per-statement assertion that link#88 fix INSERT fires), control-table honoured. 44/44 pass.
- Code-check: 3 rounds. Rounds 1–2 clean. Round 3 caught a fragile cross-statement regex in the test; replaced with per-statement `any(grepl & grepl)`. Sanity-verified the assertion catches the regression.
- Pre-flight: HARR single-WSG `compare_bcfishpass_wsg(wsg = "HARR", config = lnk_config("bcfishpass"))` 89.5 s. blkey 356286055 BT credits 6.509 km (was 0). HARR BT diffs collapsed: rearing_stream -10.4% → -4.19%, rearing -1.84%, spawning -1.6%.
- 15-WSG `tar_make` (53m 2s, 33/33). Parity dramatic on HARR (CH/CO/ST <0.32%; BT residual -4.19%) and LFRA (CH/CO/ST <0.6%; BT residual -3.75%). HORS unchanged (-7.68% rearing_stream BT) — different mechanism, follow-up needed. Default-bundle bit-identical (0 of 581 rows changed).
- Reproducibility re-run (52m 55s, 33/33). 0 of 1057 link_value rows differ; digest match (`5a641892b82604259b0ba168ea093661`). ✓
- Code commit `a21a8f8`. PWF + verification logs commit. Ready for PR.
