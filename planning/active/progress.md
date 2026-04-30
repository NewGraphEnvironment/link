# Progress — link#88

## Session 2026-04-30

- Diagnosis: traced HARR blkey 356286055 BT under-credit to subsurfaceflow positions on downstream tributary 356282804 not reaching `natural_barriers` for the per-species observation/habitat lift.
- Read bcfp SQL (`model_access_bt.sql`, `model_access_ch_cm_co_pk_sk.sql`) — confirmed bcfp's natural-barrier union includes subsurfaceflow with same lift rules.
- Confirmed default-bundle off-switch is preserved verbatim (omit `subsurfaceflow` from `cfg$pipeline$break_order`).
- Filed link#88 with diagnosis + proposed fix.
- Branch `88-fold-subsurfaceflow-natural` from main.
- PWF baseline.
- Next: code change in `R/lnk_pipeline_prepare.R`.
