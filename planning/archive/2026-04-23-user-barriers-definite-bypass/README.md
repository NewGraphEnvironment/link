# #48 — user_barriers_definite bypass (closed)

PR #49 merged 2026-04-23 as link 0.7.0 (squash commit `5cbd75d`, tagged `v0.7.0`).

Dropped `barriers_definite` from `natural_barriers` in `.lnk_pipeline_prep_natural()` so user-definite positions are no longer eligible for observation-based override. Matches bcfishpass's `model_access_*.sql` post-filter `UNION ALL` shape.

Active defect pre-fix on ELKR: 4 override rows at user-definite positions (Erickson Creek exclusion + 2 Spillway MISC); post-fix: 0 on all 5 WSGs. ELKR rollup shifted toward bcfishpass (BT spawning +3.4% → +2.8%, WCT spawning +4.0% → +2.6%, WCT rearing +1.6% → +0.3%). Other 4 WSGs unchanged (empty `barriers_definite` on 3; BULK's 87 rows had no override matches). Reproducibility verified — digest `50908d234e2131fc0842dc3ab653ae78`, 46 rows identical across two rebuilds.

`barriers_definite` still consumed separately as break source (`lnk_pipeline_break()`) and via `UNION ALL` into `fresh.streams_breaks` (`lnk_pipeline_classify()`). Both surfaces unchanged.

## Next

- #46 — migrate remaining `information_schema.tables` probes in `.lnk_pipeline_prep_gradient()` and `.lnk_pipeline_prep_overrides()` to manifest-driven gating (pure refactor, no behavior change, bit-identical rollup expected).
