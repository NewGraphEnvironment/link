# Findings — PARS Peace mapping_code vignette (#215)

## Issue context

`link` has no vignette. We want one for the **PARS (Parsnip) WSG** in the FWCP Peace
region that rehearses a habitat `mapping_code` analysis end-to-end, so the showcase can
transfer into the **Fish Passage Peace 2025** report appendix — the same vignette→appendix
path `flooded` took (`pars-floodplain.Rmd` → `0830-appendix-floodplain.Rmd`), templated in
fish_passage_template_reporting#178.

Two analyses:
1. **Parity** — link's `bcfishpass` config reproduces bcfishpass per-segment `mapping_code`
   for PARS (inside the 99.66% study-area median, #175). Tunnel-free vs the local
   `fresh.streams_vw_bcfp` snapshot.
2. **Arctic grayling showcase** — link's `default` config models GR, which bcfishpass does
   not model at all. The net-new, project-specific extension.

**Positioning (load-bearing, per fish_passage_template_reporting#192):** complements and
extends the canonical `smnorris` stack (`fwapg`/`bcfishpass`/`bcfishobs`) — never supersedes.
Lead with what's net-new; frame upstream as foundational. Norris credited inline, lightly.

## Critical design constraint

pkgdown CI has **no Postgres and no bcfp snapshot**. The model run + comparison happen
**once locally** in a data-gen script that caches artifacts to `inst/vignette-data/`; the
vignette only *loads* those (model-run chunks shown `eval=FALSE`, mirroring flooded's `vca`
chunk). Do not run the model during vignette build.

## Grounded facts (from plan-mode exploration)

### flooded template
- `flooded/vignettes/pars-floodplain.Rmd`: YAML `output: bookdown::html_vignette2` +
  `bibliography: references.bib` + `link-citations: false`; param table via
  `xciter::xct_keys_to_inline_table_col(tab, col_format="citation_keys", path_bib="references.bib")`
  → `knitr::kable`; loads via `system.file("vignette-data/pars.gpkg", package="flooded", mustWork=TRUE)`;
  maps = `terra::shade(terra::terrain(...))` hillshade + layered `sf` overlays + text halos.
- `flooded/data-raw/wsg_vignette_data.R`: data-gen → wipes + writes a multi-layer `.gpkg`
  via `sf::st_write(..., append=TRUE)` + COG tifs + meta `.rds`. **Not** the `.Rmd.orig`
  pre-knit pattern (breaks bookdown figure numbering).
- flooded `_pkgdown.yml` has **no `articles:`** — vignettes auto-discover.
- GitHub raw links: `https://github.com/NewGraphEnvironment/link/raw/main/inst/vignette-data/<file>`.

### link function signatures (verified)
- `lnk_config(name_or_path)` → manifest; `lnk_load_overrides(cfg)` → `loaded` list.
- `lnk_pipeline_run(conn, aoi, cfg, loaded, schema=paste0("working_",tolower(aoi)), dams=TRUE,
  cleanup_working=TRUE, mapping_code=FALSE)` — persists to `cfg$pipeline$schema` (`fresh` for
  bcfishpass; `fresh_default` for default).
- `lnk_compare_mapping_code(conn, aoi, cfg, reference="bcfishpass", conn_ref=NULL, species=NULL,
  ref_table="fresh.streams_vw_bcfp")` → tibble `wsg, species, total_segs, match_pct, n_diffs,
  top_pattern, top_pattern_count`. **Tunnel-free when `conn_ref=NULL`** (reads local snapshot view).
- `lnk_compare_rollup(conn, aoi, cfg, reference, conn_ref, species)` → `wsg, species,
  habitat_type, unit, link_value, ref_value, diff_pct`.
- `lnk_parity_annotate(rollup, taxonomy="research/bcfp_divergence_taxonomy.yml", to=NULL,
  tolerance=2)` → adds `taxonomy_id, class, mechanism, status, refs`.
- `lnk_stamp(cfg, conn, aoi)` + `lnk_stamp_finish(stamp, result)` → provenance;
  `format(stamp, "markdown")`.
- GR confirmed in `inst/extdata/configs/default/{rules.yaml,dimensions.csv}`; absent from
  `bcfishpass/`. Snapshot `fresh.streams_vw_bcfp` loaded by
  `data-raw/snapshot_bcfp.sh --with-bcfp-views`.

### gq symbology registry
- `gq::gq_reg_main()` → list; `gq::gq_tmap_classes(reg$layers$streams_salmon)` → `$field`,
  `$values` (named vector `mapping_code` token → hex), `$labels`. Registry bundled at
  `gq/inst/registry/reg_main.json` (extracted from bcfp QGIS project). Token→colour vocabulary
  is barrier-status-based (`SPAWN;NONE`→`#129bdb`, `SPAWN;MODELLED`→`#ff9f85`,
  `SPAWN;ASSESSED`→`#ef4545`, `SPAWN;DAM`→`#ae7dd6`, `SPAWN;REMEDIATED`→`#33a02c`, `REAR;*`,
  `ACCESS;*`) — **species-agnostic**, so one lookup colours every species' map.
- **Consume pattern (verbatim from `fresh/vignettes/fwa-network-query.Rmd`):**
  ```r
  reg <- gq::gq_reg_main(); cls <- gq::gq_tmap_classes(reg$layers$streams_salmon)
  streams$col <- cls$values[streams$mapping_code_bt]; streams$col[is.na(streams$col)] <- "#999999"
  plot(sf::st_geometry(streams), col = streams$col, lwd = 1, add = TRUE)
  present <- names(cls$values) %in% unique(streams$mapping_code_bt)
  legend("topright", legend = cls$labels[present], col = cls$values[present], lwd = 2,
         cex = 0.7, bg = "white")
  ```
- link does not yet use `gq`; `fresh` carries it as Suggests + `NewGraphEnvironment/gq` Remote.

### link DESCRIPTION today
- Suggests has `sf` but NOT `bookdown/knitr/rmarkdown/xciter/terra/gq`; Remotes lacks
  `xciter`/`gq`; no `VignetteBuilder`.

## Reference issues

- fish_passage_template_reporting#192 — Arctic grayling framework integration; THE positioning
  register ("complements and extends... does not supersede"); grayling is first concrete FWCP
  Peace output; Phases A-D.
- fish_passage_template_reporting#178 — templated floodplain chapter; driver script + parameter
  CSVs + YAML toggle.
- flooded#35 — WSG-scale vignette pattern + output-path convention.
- #175 — study-area parity baseline (99.66% median).
- #212 — KO/RB/GR rows in bcfp config; needed only for link-vs-link Comparison B, NOT the
  grayling showcase (which uses `default` config). Kept un-conflated.
