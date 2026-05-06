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

- [ ] Branch on `NewGraphEnvironment/bcfishpass` from main. Change line 159: `pscis_status = 'REMEDIATED' AND pscis_status = 'PASSABLE'` → `pscis_status IN ('REMEDIATED', 'PASSABLE')`.
- [ ] Open PR titled "Fix contradictory pscis_status check in remediated_dnstr_ind (regressed in v070)". Reference smnorris#690.
- [ ] Surface to smnorris (mention or upstream PR) once landed in our fork — non-blocking for link#135 work.

## Phase 2: ADMS validation without merge-in

**Files**: `data-raw/logs/<TS>_link135_parity_validation.txt` (stamped log)

- [ ] Re-run the #124 Phase 5 ADMS parity check, but DROP the `merge(acc, bcfp_inds, ...)` line — let `lnk_pipeline_access` produce both indicators.
- [ ] Compare `acc$dam_dnstr_ind` to `bcfishpass.streams_access.dam_dnstr_ind` per row, byte-identical.
- [ ] Compare `mapping_code_<sp>` against `bcfishpass.streams_mapping_code` for all 8 species. Acceptance: BT/WCT byte-identical (15762/15762) **without merge step**, except where link emits REMEDIATED on the bcfp-buggy rows. Quantify the divergence; document.
- [ ] Other 6 species byte-identical (anadromous flavor doesn't use either indicator).

## Phase 3: Mocked unit tests

**Files**: `tests/testthat/test-lnk_pipeline_access.R` (extend) — or new `test-lnk_pipeline_access-dam-ind.R` if cleaner.

- [ ] Mocked tests via `local_mocked_bindings(frs_network_features = ...)`. Cases:
  - Both anth + dams sources empty → `dam_dnstr_ind = FALSE`
  - Anth `[A1, A2]`, dams `[A1]` → `dam_dnstr_ind = TRUE`
  - Anth `[P1, A1]`, dams `[A1]` → `dam_dnstr_ind = FALSE` (PSCIS first)
  - Only `anthropogenic` in `barrier_sources` (no dams) → column not emitted
  - `remediated_dnstr_ind` with `crossings_table = NULL` → column not emitted
  - `remediated_dnstr_ind` with `crossings_table` provided → TRUE iff lookup returns PASSABLE/REMEDIATED status
- [ ] `devtools::test()` green.

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
