# Task Plan: user_barriers_definite should bypass override (#48)

## Goal

Match bcfishpass's architecture for `user_barriers_definite` rows: they must be appended to each per-model barrier table **post-filter** — always blocking, never eligible for observation override. Same-family fix as #44 but different mechanism.

Pre-fix defect on ELKR confirmed: 4 override rows at user-definite positions (Erickson Creek exclusion, 2× Spillway MISC) that bcfishpass would keep as blockers.

## Phase 1: Code change (simpler than initially planned)

Investigation showed `barriers_definite` is already wired as a break source in `lnk_pipeline_break` (sequential `frs_break_apply`) and into `fresh.streams_breaks` in `lnk_pipeline_classify` (access-gating barrier table). User-definite positions already end up as segment boundaries AND as blocking barriers at classification — bcfishpass parity on those two surfaces.

The only defect is `.lnk_pipeline_prep_natural()` UNIONing `barriers_definite` into `natural_barriers`. `natural_barriers` is passed to `lnk_barrier_overrides()` which generates per-species override (skip) rows for any barrier with threshold observations upstream. That's what lets user-definite positions be re-opened.

Only `natural_barriers` caller outside prep_natural is `.lnk_pipeline_prep_overrides()` (confirmed via grep). Safe to drop the definite UNION without touching prep_minimal.

- [x] `.lnk_pipeline_prep_natural()` — drop the `INSERT INTO natural_barriers SELECT ... FROM barriers_definite` block. `natural_barriers` becomes gradient + falls only. Inline NOTE comment explains the bcfishpass parity reasoning.
- [ ] Update tests in `test-lnk_pipeline_prepare.R` — the existing `prep_natural unions gradient + falls + definite` assertion needs to drop the "definite" clause.

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
- [ ] Open PR with SRED tag (`Relates to an internal issue`), link to #48, note closing of #48.

## Versions at start

- fresh: 0.14.0
- link: main (0.6.0, target 0.7.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
