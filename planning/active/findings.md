# Findings — Extend PARS vignette to demonstrate accessible_km bcfp-equivalence (#226)

## Issue context

#221 added the per-WSG `accessible_km` roll-up and #223 fixed the access segmentation so `accessible_km`
converges to the bcfp reference **exactly** (proof: `research/parity_accessible_habitat_2026_07_03.md` —
44/44 within 0.05% across 8 species × 11 WSGs).

Extend `vignettes/pars-habitat-connectivity.Rmd` (currently demonstrates `mapping_code` parity at 99.04% BT)
to also demonstrate **accessible_km bcfp-equivalence**, and regenerate the cached artifacts via
`data-raw/wsg_vignette_data.R` from the merged state. Kept as its own PR (user-facing docs + a regenerated
binary `.gpkg` + pkgdown CI build). Relates to #221, #223.

## Live-verified DB state (2026-07-04, local `:5432` fwapg, read-only)

**PARS·BT roll-up — link vs bcfp (the numbers the vignette will assert):**

| metric | link km | bcfp km | diff |
|---|---|---|---|
| accessible | 6822.47 | 6822.88 | **−0.01%** (exact; the #223 target) |
| spawning | 1683.38 | 1667.92 | +0.93% (within habitat tol) |
| rearing | 2575.06 | 2588.91 | −0.53% (within habitat tol) |

- Link side reproduces `lnk_rollup_wsg(conn, aoi="PARS", species="BT", schema="fresh")`.
- Bcfp side = `fresh.streams_vw_bcfp` PARS, `access_bt/spawning_bt/rearing_bt IN (1,2)`, `sum(length_metre)/1000`.
- accessible −0.01% matches the proof doc's PARS·BT row exactly → persisted `fresh` is post-#223.

**The blocker (verified — drove the full-regen scope choice):**

| schema | PARS segs | avg length | state |
|---|---|---|---|
| `fresh` (BT) | 97,538 | 142.2 m | post-#223 |
| `fresh_default` (GR) | 48,558 | 285.6 m | **pre-#223** |

The gpkg `streams` query (`wsg_vignette_data.R:103-118`) pulls geometry + `mapping_code_bt` from `fresh` but
LEFT-JOINs `mapping_code_gr` from `fresh_default` on `(id_segment, watershed_group_code)`. Two different
segmentations → the GR token attaches to the wrong geometry. Regenerating the gpkg *now* corrupts the GR map.
Plan-agent measured: `gr_only` 1,764 → 12,749, streams layer 33,696 → 51,371 — pure join artifact.

**Why a local re-model suffices (no cyphers):** PARS downstream closure WSGs are all persisted in
`fresh_default` — PCEA (33,763), FINA (26,094), PARA (19,079), LBTN (28,304), LPCE (11,483), UPCE (25,024),
NECR (27,989). So the `;DAM` recompute can run locally. Pre-#223 both configs segmented PARS identically
(48,558 = 48,558) → expect both → ~97,538 post-#223, restoring a valid `id_segment` join.

`fresh` is a **patchwork**: only the proof WSGs (FINA/PARS/PCEA + the other 7) are post-#223; the rest still
match `fresh_default` (pre-#223). Only PARS's own segmentation matters for this gpkg.

## Existing structure (from Explore agents)

- Vignette output `bookdown::html_vignette2`; loads `inst/vignette-data/pars.gpkg` (11.5 MB) +
  `pars_parity.rds` (272 B, 1-row: wsg/species/total_segs/match_pct/n_diffs/top_pattern/top_pattern_count).
- Parity section `## Reproducing bcfishpass (parity)` (~L212): `parity-table` kable + `parity-pct` computed
  prose (99.04% inline, auto-updates). No `\@ref` cross-refs anywhere.
- Two-species: BT (bcfp parity) + GR (link extension, "nothing to compare"). Parity portion is BT-only.
- **Blocker 2:** map-gr `fig.cap` (`Rmd:388`) + map-detail prose (`Rmd:411`) hardcode 19,233 / 31,932 / 1,764
  — won't auto-update; must inline-compute post-regen.
- `data-raw/wsg_vignette_data.R`: `LNK_LOAD=loadall Rscript ...`, reads persisted `fresh` + `fresh_default`
  on `:5432`; computes ONLY mapping_code + geometry (no rollup). `bookdown`/`sf`/`gq` in Suggests;
  `ggplot2` NOT declared (new content stays kable+prose). pkgdown CI builds on push to main, cache-only.

## API to reuse

- `R/lnk_rollup_wsg.R` — `lnk_rollup_wsg(conn, aoi, species, schema="fresh")` → data.frame
  `wsg/species/accessible_km/spawning_km/rearing_km`. accessible = `access_<sp> IN (1,2)` from
  `streams_access` LEFT-joined to `streams` on full PK; length from `streams`.
- `data-raw/parity_crosssection.R:55-69` — the exact bcfp `streams_vw_bcfp` `IN (1,2)` rollup SQL to mirror.
- `data-raw/wsg_run_one.R` / `wsg_recompute_one.R` — Phase 1 re-model + cheap `merge=TRUE` recompute.

## Reference
- bcfp reference: local `fresh.streams_vw_bcfp` snapshot, `smnorris/bcfishpass@v0.7.15-41-g2917790` (tunnel-free).
