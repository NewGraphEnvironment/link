# Task: Extend PARS vignette to demonstrate accessible_km bcfp-equivalence (#226)

#221 added the per-WSG `accessible_km` roll-up; #223 fixed the access-segmentation over-credit so link's
`accessible_km` converges to bcfishpass **exactly** (proof: `research/parity_accessible_habitat_2026_07_03.md`
— 44/44 within 0.05%). Extend `vignettes/pars-habitat-connectivity.Rmd` (currently only per-segment
`mapping_code` parity, 99.04% BT) to also demonstrate the aggregate `accessible_km` bcfp-equivalence, and
**regenerate the cached artifacts from the merged v0.44.0 state**. User chose **full faithful regeneration**
(re-model the stale grayling schema, not just add the accessible table).

## Phase 1: Re-model PARS default config to post-#223 (modelling prerequisite)
- [x] Re-model PARS default config → `fresh_default` post-#223 via `lnk_pipeline_run(aoi="PARS",
      cfg=lnk_config("default"), schema="fresh_default", mapping_code=TRUE)` (reuse `data-raw/wsg_run_one.R`
      if it selects config/schema; else call directly). Local `:5432`.
- [x] Recompute PARS access `merge=TRUE` + `lnk_mapping_code` so cross-WSG `;DAM` is settled against the
      consolidated barrier set (downstream Peace WSGs already persisted in `fresh_default`).
- [x] **Gate:** `fresh_default.streams` PARS ≈ 97,538 / ~142 m (matches `fresh`) and the gpkg `id_segment`
      join fresh↔fresh_default is ~100% length-consistent. If not, STOP and reassess.

## Phase 2: Extend data-gen — accessible_km cache + segmentation guard
- [x] `data-raw/wsg_vignette_data.R`: LINK `lnk_rollup_wsg(aoi, species="BT", schema="fresh")` + BCFP
      `fresh.streams_vw_bcfp` (`access_bt`/`spawning_bt`/`rearing_bt` `IN (1,2)`, coalesce, schema-qualified,
      mirror `parity_crosssection.R:55-69`) → 3-row `accessible` (metric/link_km/bcfp_km/diff_pct) →
      `saveRDS` `inst/vignette-data/pars_accessible.rds`.
- [x] Harden `persisted()` guard (`wsg_vignette_data.R:65-81`): assert `fresh.streams` vs
      `fresh_default.streams` AOI segment counts agree — refuse a mixed-segmentation gpkg.

## Phase 3: Regenerate all cached artifacts
- [x] `LNK_LOAD=loadall Rscript data-raw/wsg_vignette_data.R`.
- [x] Confirm `pars.gpkg` (post-#223 geometry, valid GR join), `pars_parity.rds` (refreshed BT parity),
      `pars_accessible.rds` (new).
- [x] Sanity: accessible −0.01% (6822.47/6822.88); mapping_code ~99%; **measure gpkg size** (~2× → ~22 MB);
      if it balloons bump `st_simplify(dTolerance=)` (L123) — note R CMD installed-size NOTE.

## Phase 4: Vignette — accessible_km subsection + fix stale captions
- [x] `load` chunk (~L154): `readRDS(pars_accessible.rds)`; inline-compute `n_bt`/`n_gr`/`n_gronly` from the
      loaded `streams` layer (DB-free).
- [x] Replace hardcoded caption counts — map-gr `fig.cap` (`Rmd:388`) + map-detail prose (`Rmd:411`) → vars.
- [x] Add `### Accessible habitat (km)` under `## Reproducing bcfishpass (parity)`: prose + captioned kable +
      computed `results="asis"` sentence (accessible −0.01%, bridge to the 416 mapping_code disagreements;
      spawn/rear within-tolerance, not "exact").
- [x] Update `## Cached inputs` prose + raw-download links (~L138-152) to include `pars_accessible.rds`.

## Phase 5: Verify + finalize
- [x] Knit with DB **stopped** — cache-only; numbers + captions + numbering correct.
- [x] `/code-check` on staged diff.
- [x] NEWS.md (patch); `/planning-archive`; `/gh-pr-push` (Closes #226; relates #221/#223; ref
      `NewGraphEnvironment/sred#24`). Version bump (patch) as final commit / at `/gh-pr-merge`.

## Validation
- [x] Phase 1 gate met (segmentation match + length-consistent join)
- [x] Vignette knits from cache with DB stopped; accessible sentence ≈ "6,822.5 km vs 6,822.9 km, −0.01%"
- [x] `pars_accessible.rds` equals the live-verified table (±rounding)
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
