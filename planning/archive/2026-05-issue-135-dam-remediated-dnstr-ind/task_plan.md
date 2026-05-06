# Task: lnk_pipeline_access: compute dam_dnstr_ind / remediated_dnstr_ind from primitives (#135)

## Problem

`lnk_pipeline_mapping_code()` reproduces bcfp's `streams_mapping_code` byte-identically for all 8 species on ADMS — **as long as the caller merges in bcfp's pre-computed `dam_dnstr_ind` and `remediated_dnstr_ind` columns from `bcfishpass.streams_access`**.

Without those, `mapping_code_<bt|wct>` (resident-flavor) drift on rows where multiple barrier types stack (e.g. PSCIS-then-dam downstream). The resident flavor's CASE is sequence-aware: `DAM` token only fires when the *next* downstream anthropogenic barrier IS a dam, not just "any dam exists downstream". Presence-only fallback (`has_barriers_dams_dnstr`) over-emits DAM for ~14% of segments where bcfp emits `ASSESSED`.

bcfp's SQL ([load_streams_access.sql:140-147](https://github.com/smnorris/bcfishpass/blob/main/model/01_access/sql/load_streams_access.sql#L140)):

```sql
case
  when array[b.barriers_anthropogenic_dnstr[1]] && b.barriers_dams_dnstr then true
  else false
end as dam_dnstr_ind,
```

i.e. take the FIRST element of `barriers_anthropogenic_dnstr` (the next-downstream anthropogenic barrier), check if it's also in `barriers_dams_dnstr`. If yes → DAM is the most-downstream barrier.

## Triage findings

1. **`barriers_<source>_id` columns are already in shared ID space.** All bcfp barriers tables populate their primary key from `bcfishpass.crossings.aggregated_crossings_id`. `barriers_anthropogenic` (444998 rows) ⋈ `barriers_dams` (2384 rows) on `_id` columns → 2384 perfect overlaps. Our `frs_network_features` calls already produce arrays of those same IDs.

2. **`remediated_dnstr_ind` is currently dead code in bcfp due to a recent regression.** The JOIN clause `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` is contradictory (always FALSE); 4.2M rows confirm. Diagnosis: regressed in [smnorris/bcfishpass#690](https://github.com/smnorris/bcfishpass/pull/690) ("db v070", 2025-09-24). Looks like a typo where `AND` should have been `IN ('REMEDIATED', 'PASSABLE')`. Original feature was working pre-v070 (smnorris#275, smnorris#326). 154 REMEDIATED crossings province-wide.

   Strategy: link computes `remediated_dnstr_ind` *correctly* (bcfp-intended logic). Document divergence in NEWS — link's mapping_code may emit `REMEDIATED` tokens where bcfp's current output emits `DAM`/`MODELLED`/`ASSESSED`. Plus file an upstream PR to `NewGraphEnvironment/bcfishpass` (our fork) fixing the typo.

## Phase 1: Compute `dam_dnstr_ind` + `remediated_dnstr_ind` inside `lnk_pipeline_access`

**Files**: `R/lnk_pipeline_access.R`

- [x] Add `dam_dnstr_ind` computation after the existing `dnstr_per_source` loop, gated on both `anthropogenic` and `dams` being present in `barrier_sources`. Per-row: `dam_dnstr_ind = anth_arr[[i]][1] %in% dam_arr[[i]]`. Defensive: empty/NA anth array → FALSE.
- [x] Add optional `crossings_table = NULL` arg. When supplied alongside `barrier_sources$remediations`, compute `remediated_dnstr_ind` per the bcfp-intended logic — TRUE iff next-downstream remediation is a crossing with `pscis_status IN ('REMEDIATED', 'PASSABLE')`. Inline comment cross-refs the smnorris#690 regression and link's upstream fix-PR.
- [x] Roxygen update on `lnk_pipeline_access`: document both new columns, the `barrier_sources` shape needed, and the `crossings_table` arg. Note the bcfp v0.7.0 divergence on REMEDIATED.
- [x] `devtools::document()` + `lintr::lint("R/lnk_pipeline_access.R")` — both clean.

## Phase 1b: Upstream PR to NewGraphEnvironment/bcfishpass fork

**Files**: `model/01_access/sql/load_streams_access.sql` (one-line fix in our fork)

- [x] Filed [smnorris/bcfishpass#891](https://github.com/smnorris/bcfishpass/issues/891) (issue) and [smnorris/bcfishpass#892](https://github.com/smnorris/bcfishpass/pull/892) (PR, NewGraphEnvironment fork → smnorris:main, "Closes #891"). Branch synced from upstream/main first; one-line `AND` → `IN` change.

## Phase 2: ADMS validation without merge-in

**Files**: `data-raw/logs/<TS>_link135_parity_validation.txt` (stamped log)

- [x] Re-run the #124 Phase 5 ADMS parity check, no merge-in. Stamped log: `data-raw/logs/20260505_2251_link135_parity_validation.txt`.
- [x] `acc$dam_dnstr_ind` vs bcfp: 11803 FALSE / 3960 TRUE, zero off-diagonal.
- [x] `mapping_code` parity: BT 15733/15763 (30 REMEDIATED divergences), CH/CM/CO/PK/SK 15761/15763 (2 each), ST/WCT 15763/15763. All diffs are the documented bcfp v070 regression.
- [x] Other 6 species: see above (CH/CM/CO/PK/SK 99.99%, ST/WCT 100%).

## Phase 3: Mocked unit tests

**Files**: `tests/testthat/test-lnk_pipeline_access.R` (extend) — or new `test-lnk_pipeline_access-dam-ind.R` if cleaner.

- [x] Mocked tests via `local_mocked_bindings`. All cases above covered in `tests/testthat/test-lnk_pipeline_access.R`.
- [x] `testthat::test_file` clean (12 expectations, all pass).

## Phase 4: Release

**Files**: `NEWS.md` (prepend 0.30.1 entry), `DESCRIPTION` (0.30.0 → 0.30.1).

Patch bump — no new exported functions, internal correctness improvement on `lnk_pipeline_access`.

NEWS body bullets:
- `lnk_pipeline_access` computes `dam_dnstr_ind` from primitives (sequence-aware: TRUE iff next-downstream anthropogenic barrier is also a dam). bcfp ADMS parity: byte-identical without merge-in.
- `lnk_pipeline_access` gains optional `crossings_table = NULL` arg — when supplied alongside `barrier_sources$remediations`, computes `remediated_dnstr_ind` per the bcfp-intended logic.
- **Divergence note**: bcfp's `remediated_dnstr_ind` regressed in [smnorris/bcfishpass#690](https://github.com/smnorris/bcfishpass/pull/690) ("db v070") — a contradictory `AND` clause makes it always FALSE. link computes the bcfp-intended `IN` semantics, so link's mapping_code may emit `REMEDIATED` tokens on segments where bcfp's current output emits `DAM`/`MODELLED`/`ASSESSED`. PR filed against `NewGraphEnvironment/bcfishpass` fork; once merged + propagated upstream, both outputs converge.

- [ ] DESCRIPTION 0.30.0 → 0.30.1.
- [ ] NEWS.md 0.30.1 entry.
- [ ] `/code-check` on staged diff.
- [ ] Commit, push, open PR closing #135.
- [ ] `/planning-archive`.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
