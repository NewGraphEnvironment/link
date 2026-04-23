# Task Plan: Wire barriers_definite_control into lnk_barrier_overrides (#44)

## Goal

Honour `user_barriers_definite_control.csv`'s `barrier_ind = TRUE` rows at the observation-override step. Positions marked as non-overridable (known fish-blocking dams, long impassable falls, diversions) must never be re-opened by historical upstream observations. Matches bcfishpass's per-species access SQL.

Bit-identical-across-reruns reproducibility preserved. Rollup direction expected: toward bcfishpass reference, not away.

## Phase 1: lnk_barrier_overrides control filter fix

- [x] Read `R/lnk_barrier_overrides.R` control block. Confirmed: current filter treated ANY control row as blocking; docstring said only `barrier_ind = TRUE` rows block.
- [x] Updated `ctrl_filter` to `"AND (c.blue_line_key IS NULL OR c.barrier_ind::boolean = false)"`.
- [x] Updated the inline comment to describe the fixed semantics.
- [x] New test file `tests/testthat/test-lnk_barrier_overrides.R` with mocked SQL assertions — 7 tests covering observation-path control filter, NULL-control path, habitat-path control filter.
- [x] `devtools::test()` green: 265 PASS.
- [x] lintr clean on changed R/test files (only pre-existing indentation style notes, consistent with the rest of the codebase).
- [ ] `/code-check` before commit

## Phase 2: Wire control through .lnk_pipeline_prep_overrides

- [x] Updated `.lnk_pipeline_prep_overrides` with manifest-gated `control_arg` computation; passes `control = control_arg` to `lnk_barrier_overrides`.
- [x] Fixed asymmetric gating — `.lnk_pipeline_prep_load_aux` now always creates a schema-valid (possibly empty) `<schema>.barriers_definite_control` table when the manifest declares the key, even if the AOI has zero control rows. Mirrors the `barriers_definite` pattern above. Lets `.lnk_pipeline_prep_overrides` gate on the manifest without worrying about the per-AOI row count.
- [x] Two new `.lnk_pipeline_prep_overrides` tests in `test-lnk_pipeline_prepare.R` — manifest present → `control = "<schema>.barriers_definite_control"`; manifest absent → `control = NULL`.
- [x] `devtools::test()` green: 271 PASS.
- [x] `/code-check` surfaced the asymmetric-gating bug — fixed and re-verified before commit.

## Phase 2a: Per-species control gate (observation_control_apply)

Post-Phase-2 `tar_make()` drifted 11–22pp *away* from bcfishpass on ADMS/BABL because bcfishpass applies the control filter per-species (CH/CM/CO/PK/SK and ST only), while my implementation applied it across all species. Residents (BT, WCT) inhabit reaches upstream of anadromous-blocking falls — their observations should still override.

- [x] Add `observation_control_apply` column to `inst/extdata/configs/bcfishpass/parameters_fresh.csv`. TRUE for CH/CM/CO/PK/SK/ST; FALSE for BT/WCT; NA for CT/DV/RB.
- [x] `lnk_barrier_overrides()` gates the NOT EXISTS clause per-species on `params$observation_control_apply[i]`. Missing column or NA ⇒ no filter (resident default).
- [x] Updated `@param control` / `@param params` roxygen to document the gate.
- [x] Extended `.stub_params()` in `test-lnk_barrier_overrides.R` with optional `control_apply`. Three new tests: FALSE ⇒ no clause, NA ⇒ no clause, mixed-species params ⇒ per-species gating.
- [x] `devtools::test()`: 279 PASS.
- [x] Amend issue #44 body with Phase 2a scope and biological rationale.
- [x] `/code-check` before commit — two rounds, both Clean.

## Phase 2b: Ungate habitat override path from control

Phase 2a species-gating fixed BT/WCT drift but CH/CM/CO/PK/SK/ST still dropped 11–22pp on ADMS/BABL. Root cause: my `ctrl_filter` was applied to BOTH the observation and habitat paths of `lnk_barrier_overrides()`. bcfishpass's `hab_upstr` CTE has no control join at all — expert-confirmed habitat is higher-trust than the control designation and bypasses the filter.

- [x] Removed `ctrl_where` / `ctrl_filter` from the habitat INSERT in `lnk_barrier_overrides()`. Observation path unchanged.
- [x] Updated roxygen: control parameter now notes it applies only to observations; habitat bypasses.
- [x] Flipped the existing "control filter applies to habitat too" test to assert the opposite (bcfishpass parity). `devtools::test()` 279 PASS.
- [x] Committed (6f3bc46).
- [x] `tar_make()` — Phase 2b rollup numerically identical to pre-fix baseline on all 34 rows, all 4 WSGs within 5% of bcfishpass reference.

## Phase 2c: Add DEAD as the filter's end-to-end test WSG

Discovered post-Phase 2b: none of ADMS/BULK/BABL/ELKR actually exercises the new control filter end-to-end. All 6 TRUE control rows across these WSGs are rescued by either the observation threshold (obs < 5) or the habitat path (classification upstream). That's why post-fix == pre-fix — correct, but information-less.

Province-wide hunt for TRUE control rows with ≥ threshold observations upstream AND zero habitat coverage turned up 4 candidates: CAMB (11 obs), DEAD (6), LFRA (16, but too large), SALM (7). Picked **DEAD** (Deadman River) — smallest runtime, 6 obs just above CH threshold, single TRUE control row at FALLS (356361749, 45743). bcfishpass reference keeps this fall in `barriers_ch_cm_co_pk_sk` (control worked); pre-fix link would have overridden via observations.

- [x] Added DEAD to `data-raw/_targets.R` wsgs vector.
- [ ] `tar_make()` incremental — builds `comparison_DEAD` + new rollup (ADMS/BULK/BABL/ELKR cached from Phase 2b run).
- [ ] Verify DEAD's diff_pct on CH/CO/SK/ST is small (post-fix link ≈ bcfishpass — filter working).
- [ ] Verify the specific fall at (356361749, 45743) is NOT in `working_dead.barrier_overrides` for CH/CM/CO/PK/SK/ST (filter blocked the override).

## Phase 3: End-to-end verification

- [x] `pak::local_install()` to pick up pipeline changes.
- [x] First post-fix run: `20260423_02_tar_make_phase2a.txt`, `20260423_03_tar_make_phase2b.txt`.
- [x] Inspect rollup against pre-change baseline — matches exactly on 4 WSGs (filter moot on those; DEAD being added to exercise it).
- [ ] Reproducibility run (Phase 2b state): `20260423_04_tar_make_repro.txt` in progress. Rollup must be bit-identical to Phase 2b.
- [ ] `digest::digest()` on two Phase 2b rollup tibbles → same hash.
- [ ] Post-DEAD reproducibility: two consecutive `tar_make()` runs with DEAD present produce bit-identical 5-WSG rollups.

## Phase 4: Artifact updates

- [ ] Regenerate vignette data: `Rscript data-raw/vignette_reproducing_bcfishpass.R`. Produces new `rollup.rds` + `sub_ch.rds` + `sub_ch_bcfp.rds`.
- [ ] Render vignette locally to verify pivot tables + map update cleanly
- [ ] Update `research/bcfishpass_comparison.md`:
  - Four per-WSG parity tables with new numbers
  - Short paragraph under "Key fixes during comparison" documenting the control wiring + numeric direction
- [ ] `NEWS.md` 0.6.0 entry: "Honour `user_barriers_definite_control.csv` at the observation-override step. Previously controlled positions could be re-opened by upstream observations; now they can't."
- [ ] `DESCRIPTION` version bump 0.5.0 → 0.6.0

## Phase 5: Ship

- [ ] `/code-check` on full staged diff
- [ ] Commit atomically per the plan's commit layout
- [ ] Push branch
- [ ] Open PR with SRED tag `Relates to NewGraphEnvironment/sred-2025-2026#24`
- [ ] **File follow-up issue** (before closing PR 44): "Migrate remaining pipeline probes to manifest-driven gating". See `/Users/airvine/.claude/plans/stateful-hopping-feather.md` for scope.

## Versions at start

- fresh: 0.14.0
- link: main (0.5.0, target 0.6.0)
- bcfishpass: ea3c5d8
- fwapg: Docker (FWA 20240830)
