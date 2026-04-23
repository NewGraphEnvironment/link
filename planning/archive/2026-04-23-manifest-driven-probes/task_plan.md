# Task Plan: Migrate pipeline probes to manifest-driven gating (#46)

## Goal

Replace two `information_schema.tables` probes with direct manifest-key checks. Pure refactor, no behavior change — rollup must remain bit-identical to the post-#48 baseline (`50908d234e2131fc0842dc3ab653ae78`).

## Phase 1: Code

- [ ] `.lnk_pipeline_prep_gradient()` — add `cfg` to signature. Replace the `information_schema.tables` probe for `barriers_definite_control` with `!is.null(cfg$overrides$barriers_definite_control)`. Update the caller (`lnk_pipeline_prepare()`) to pass `cfg`.
- [ ] `.lnk_pipeline_prep_overrides()` — already receives `cfg`. Replace the `information_schema.tables` probe for `user_habitat_classification` with `!is.null(cfg$habitat_classification)`.
- [ ] Update mocked tests in `test-lnk_pipeline_prepare.R`. The existing tests mock `dbGetQuery` to fake the probe result — swap those for `cfg` stubs with / without the relevant manifest keys.

## Phase 2: Verification

- [ ] `devtools::test()` — 279 PASS retained.
- [ ] `pak::local_install()` + `cd data-raw && tar_destroy + tar_make`.
- [ ] `digest::digest()` on rollup vs `50908d234e2131fc0842dc3ab653ae78` — **must match** (behavior is unchanged).
- [ ] If digest differs: stop and root-cause. A mismatch means the refactor has unintentionally changed behavior.

## Phase 3: Ship

- [ ] `/code-check` on staged diff.
- [ ] No version bump (pure refactor, no behavior change).
- [ ] No NEWS entry (or a terse internal-architecture note — reader opinion).
- [ ] Commit atomically.
- [ ] PR with SRED tag (`Relates to NewGraphEnvironment/sred-2025-2026#24`). `Fixes #46`.

## Versions at start

- fresh: 0.14.0
- link: main (0.7.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
