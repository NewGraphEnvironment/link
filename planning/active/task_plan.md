# Task: PARS Peace mapping_code vignette — link/bcfp parity + Arctic grayling showcase (#215)

`link` has no vignette. We want one for the **PARS (Parsnip) WSG** in the FWCP Peace region that rehearses a habitat `mapping_code` analysis end-to-end, so the showcase can transfer into the **Fish Passage Peace 2025** report appendix — the same vignette→appendix path `flooded` took (`pars-floodplain.Rmd` → `0830-appendix-floodplain.Rmd`), templated in fish_passage_template_reporting#178.

Two analyses:
1. **Parity** — link's `bcfishpass` config reproduces bcfishpass per-segment `mapping_code` for PARS (inside the 99.66% study-area median, #175). Tunnel-free vs the local `fresh.streams_vw_bcfp` snapshot.
2. **Arctic grayling showcase** — link's `default` config models GR, which bcfishpass does not model at all. The net-new, project-specific extension.

**Positioning (load-bearing, per fish_passage_template_reporting#192):** complements and extends the canonical `smnorris` stack (`fwapg`/`bcfishpass`/`bcfishobs`) — never supersedes. Lead with what's net-new; frame upstream as foundational. Norris credited inline, lightly.

**Symbology — reuse `gq`, don't hand-roll:** map colours come from the bcfishpass symbology registry bundled in `gq` (`gq::gq_reg_main()`), the same way `fresh` does it (`fresh/vignettes/fwa-network-query.Rmd`). Stream colours match bcfishpass exactly; no bespoke mapping_code colour scheme.

## Critical design constraint (drives everything)

pkgdown CI has **no Postgres and no bcfp snapshot**. The model run + comparison happen **once locally** in a data-gen script that caches artifacts to `inst/vignette-data/`; the vignette only *loads* those (model-run chunks shown `eval=FALSE`, mirroring flooded's `vca` chunk). Do not run the model during vignette build.

## Phase 1 — Vignette infra scaffold
- [x] `DESCRIPTION`: add Suggests `bookdown, knitr, rmarkdown, terra, xciter, gq`; add `VignetteBuilder: knitr`; add `NewGraphEnvironment/xciter` + `NewGraphEnvironment/gq` to Remotes.
- [x] Create `vignettes/` + `vignettes/references.bib` (seed cites: bcfishpass, fwapg, bcfishobs, any GR/habitat refs).
- [x] Reinstall dev deps so `xciter` + `gq` resolve — both already installed (`gq` registry consume pattern verified: `gq_tmap_classes()` returns 30 token→hex values, salmon layer field `mapping_code_salmon`).
- [x] `/code-check` clean → commit (checkbox flip).

## Phase 2 — Data-gen script + cached artifacts
- [ ] `data-raw/pars_vignette_data.R`: (a) bcfp config → `lnk_pipeline_run(aoi="PARS", mapping_code=TRUE)` persist `fresh`; (b) default config → same, persist `fresh_default`; (c) `lnk_compare_mapping_code` (bcfp) + `lnk_compare_rollup` + `lnk_parity_annotate`; (d) `lnk_stamp`/`lnk_stamp_finish`; (e) pull spatial layers (PARS `aoi`, `streams` + mapping_code tokens incl. GR, `waterbodies`, optional context) into `inst/vignette-data/pars.gpkg`; (f) cache `pars_parity.rds`, `pars_stamp.rds`.
- [ ] Run locally; confirm artifacts written + sizes reasonable (ship-small).
- [ ] `/code-check` clean → commit (script + artifacts + checkbox).

## Phase 3 — Write `vignettes/pars-mapping-code.Rmd`
- [ ] 8 sections: orient → **Modelling parameters** (`xciter` param/stamp table) → **Cached inputs** (`system.file` + GitHub raw links) → **Reproducing bcfishpass (parity)** (kable of cached parity tibble) → **Arctic grayling — a link extension** (GR map) → **Maps** (streams coloured by mapping_code via the `gq` registry — `gq::gq_reg_main()` + `gq_tmap_classes()` + base-R `plot`/`legend`, fresh's recipe; optional terra hillshade backdrop; full-WSG + detail) → **From vignette to report** (forward-looking, names Peace 2025 appendix / template#192) → **References**.
- [ ] Model-run chunks `eval=FALSE`; data-load chunks read cached artifacts.
- [ ] Positioning prose reviewed against #192 ("extends, not supersedes").
- [ ] `/code-check` clean → commit.

## Phase 4 — Render + verify
- [ ] `pkgdown::build_site(new_process=FALSE, install=FALSE)` (or `devtools::build_vignettes()`) renders clean; figures numbered, cross-refs + inline citations resolve; no DB touched at build.
- [ ] `lintr::lint_package()` clean (covers the new data-raw script + Rmd-adjacent R).
- [ ] `/code-check` clean → commit.

## Phase 5 — Release
- [ ] `NEWS.md` new section + `DESCRIPTION` version bump (final commit).
- [ ] `/planning-archive` → `/gh-pr-push` (PR body: `Closes #215` + `Relates to NewGraphEnvironment/sred#24`).

## Dependencies / relations

- **#212** (KO/RB/GR rows in bcfp config) — needed only for the link-vs-link full-species Comparison B. The grayling **showcase** here uses the `default` config and is independent. Vignette notes this so the two aren't conflated.
- Relates: #175 (parity baseline); fish_passage_template_reporting#192, #178; flooded#35, #17; `gq` symbology registry.

## Out of scope

- #212's bcfp-config GR rows / link-vs-link Comparison B (separate issue).
- The report-side chapter itself (lives in the Peace report / template#178, #192).
- bcfishobs calibration loop (template#192 Phase C).
- Hillshade DEM backdrop is optional — if a PARS DEM isn't cheap to fetch, primary map is streams-by-mapping_code over the WSG boundary (no DEM dependency).

## Validation

- [ ] `pkgdown::build_site` renders the vignette with figures numbered and citations resolved, with **no live DB** (proves the cached-artifact design).
- [ ] Parity table reproduces PARS numbers consistent with the #175 baseline.
- [ ] GR map renders from default-config output (a species bcfp doesn't model).
- [ ] Tone consistent with #192 positioning.
- [ ] `/code-check` clean on each commit.
- [ ] PWF checkboxes match landed work.
- [ ] `/planning-archive` on completion.
