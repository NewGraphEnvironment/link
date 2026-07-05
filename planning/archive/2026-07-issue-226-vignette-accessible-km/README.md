## Outcome

Extended `vignettes/pars-habitat-connectivity.Rmd` to demonstrate `accessible_km` bcfishpass-equivalence
(#226): a new **Accessible habitat (km)** section with a link-vs-bcfp roll-up table (from cached
`pars_accessible.rds`) + computed prose — link 6,822.5 km vs bcfp 6,822.9 km accessible bull-trout habitat,
**−0.01%** (the #223 access-segmentation fix); spawning/rearing within the 5% habitat band. `data-raw/wsg_vignette_data.R`
gained the accessible roll-up cache (mirroring `parity_crosssection.R`'s `lnk_rollup_wsg()` + `streams_vw_bcfp`
`IN (1,2)`) and a segmentation-parity guard.

**The load-bearing discovery:** "regenerate the artifacts from the merged state" was *not* docs-only. The Plan
agent + live DB probes found `fresh_default` (the Arctic-grayling schema) was still on **pre-#223 segmentation**
(48,558 PARS segs vs `fresh`'s 97,538). The gpkg's single `streams` layer joins `fresh` geometry +
`mapping_code_bt` to `fresh_default` `mapping_code_gr` on `id_segment`, so a naive regeneration would have
attached grayling tokens to mismatched geometry and shipped a corrupted GR map. Fixed by re-modelling the
`default` config for PARS into `fresh_default` (`wsg_run_one.R`, 5.1 min) + a `merge=TRUE` recompute
(`wsg_recompute_one.R`, 1.6 min) for cross-WSG `;DAM`, bringing both configs onto the same segmentation. The
join is then faithful (exact GR count 19,232; 99.93% aggregate length; residual per-segment wiggle is local
habitat-break redistribution, sub-pixel at basin scale — single-layer gpkg design retained). Stale hardcoded
map-caption counts (19,233/31,932/1,764) are now computed inline (→ 19,232/38,622/257). mapping_code parity
refreshed 99.04% → 98.91% (denser post-#223). Verified with a DB-free knit; `/code-check` fixed a latent
`diff_pct` div-by-zero on the generic-reuse path.

**Reusable lesson:** the two persist configs (`fresh` / `fresh_default`) can drift in segmentation because only
WSGs re-modelled post-#223 are dense. Any cross-config artifact joined on `id_segment` must verify both sides
share segmentation first — the new guard in `wsg_vignette_data.R` enforces this.

Closed by: branch `226-vignette-accessible-km` (commits `fb0de90..7cb748d`), shipped v0.44.1. Closes #226.
