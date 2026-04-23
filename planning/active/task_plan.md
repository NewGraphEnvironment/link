# Task Plan: user_barriers_definite should bypass override (#48)

## Goal

Match bcfishpass's architecture for `user_barriers_definite` rows: they must be appended to each per-model barrier table **post-filter** — always blocking, never eligible for observation override. Same-family fix as #44 but different mechanism.

Pre-fix defect on ELKR confirmed: 4 override rows at user-definite positions (Erickson Creek exclusion, 2× Spillway MISC) that bcfishpass would keep as blockers.

## Phase 1: Code change (Shape A from #48)

- [ ] `.lnk_pipeline_prep_natural()` — drop the `INSERT INTO natural_barriers SELECT ... FROM barriers_definite` block. `natural_barriers` becomes gradient + falls only.
- [ ] `.lnk_pipeline_prep_minimal()` — after `frs_barriers_minimal()` runs for each per-model barrier table (`barriers_bt`, `barriers_ch_cm_co_pk_sk`, `barriers_st`, `barriers_wct`), append rows from `<schema>.barriers_definite` (already WSG-filtered at load time) into each, de-duped via `ON CONFLICT DO NOTHING`. Also append to `gradient_barriers_minimal` union so segmentation breaks still include them.
- [ ] Check callers of `natural_barriers` outside `.lnk_pipeline_prep_overrides()` and `.lnk_pipeline_prep_minimal()` — if other callers depend on the definite union, Shape A breaks them. (From a quick grep: `natural_barriers` is only referenced in prep_natural, prep_overrides, and prep_minimal.)
- [ ] Update tests in `test-lnk_pipeline_prepare.R` — remove "natural_barriers unions definite" assertion; add "per-model barrier tables include definite" assertion.

## Phase 2: Verification

- [ ] `devtools::test()` — all green.
- [ ] `pak::local_install()` and `cd data-raw && tar_destroy + tar_make`.
- [ ] Query `working_elkr.barrier_overrides` joined to `working_elkr.barriers_definite` — should be empty (pre-fix: 4 matches).
- [ ] ELKR rollup should shift toward bcfishpass: link BT/WCT spawning currently +3.4% / +4.0%; expected to DECREASE (closer to 0) since upstream habitat at Erickson and Spillway positions now correctly blocked.
- [ ] Reproducibility: two consecutive `tar_destroy + tar_make` produce bit-identical 46-row rollups.

## Phase 3: Artifacts

- [ ] Regenerate vignette artifacts via `data-raw/vignette_reproducing_bcfishpass.R`.
- [ ] Correct vignette text: user-definite barriers bullet no longer says "eligible for per-species override". Say they always block, are appended post-filter (bcfishpass parity).
- [ ] `research/bcfishpass_comparison.md` — new row in "Key fixes" table; update ELKR parity table with post-fix numbers; short paragraph describing the fix.
- [ ] `NEWS.md` 0.7.0 entry.
- [ ] `DESCRIPTION` 0.6.0 → 0.7.0.

## Phase 4: Ship

- [ ] `/code-check` on staged diff — 2 rounds minimum.
- [ ] Commit atomically (code + tests, then verification, then artifacts).
- [ ] Push branch.
- [ ] Open PR with SRED tag (`Relates to NewGraphEnvironment/sred-2025-2026#24`), link to #48, note closing of #48.

## Versions at start

- fresh: 0.14.0
- link: main (0.6.0, target 0.7.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
