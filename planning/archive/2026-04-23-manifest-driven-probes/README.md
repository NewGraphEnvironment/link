# #46 — manifest-driven probes refactor (closed)

PR #50 merged 2026-04-23 onto link 0.7.0 (squash commit `b2fc181`). No version bump — pure refactor, no behavior change.

Replaced two `information_schema.tables` probes in `R/lnk_pipeline_prepare.R` with direct `cfg$...` manifest checks:
- `.lnk_pipeline_prep_gradient()` gained `cfg` parameter; probe for `barriers_definite_control` → `!is.null(cfg$overrides$barriers_definite_control)`.
- `.lnk_pipeline_prep_overrides()` probe for `user_habitat_classification` → `!is.null(cfg$habitat_classification)`.

Code-check caught an asymmetry on the habitat side (manifest declared with empty CSV would pass the gate but fail at runtime). Fixed by mirroring the `barriers_definite_control` empty-stub pattern in `.lnk_pipeline_prep_load_aux()` — always create schema-valid table when manifest declares the key.

Two consecutive rebuilds confirmed bit-identical rollup vs baseline (`50908d234e2131fc0842dc3ab653ae78`, 46 rows).
