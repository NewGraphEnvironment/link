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
- [x] `data-raw/pars_vignette_data.R`: model state READ (not recomputed) from the authoritative #175 DS-first study-area persists — `fresh` (bcfp cfg, BT only in the Peace) + `fresh_default` (default cfg, adds GR/RB/KO); guarded persisted-state check shows the run invocation. (c) `lnk_compare_mapping_code` (tunnel-free, BT 99.04%); (d) `lnk_stamp`/`lnk_stamp_finish`; (e) spatial layers (PARS `aoi`, `streams` with `mapping_code_bt` from `fresh` + `mapping_code_gr` from `fresh_default`, `waterbodies`) → `inst/vignette-data/pars.gpkg`; (f) cache `pars_parity.rds` + `pars_stamp.rds`. **`lnk_compare_rollup`/`lnk_parity_annotate` dropped: they need the live bcfp tunnel (`:63333`), which breaks the tunnel-free no-DB design — and PARS BT at 99% has no habitat-km divergence to annotate.**
- [x] Run locally; confirm artifacts written + sizes reasonable: `pars.gpkg` 9.7 MB (33,696 streams + 1,914 waterbodies, ZM-dropped + 15 m simplify), `pars_parity.rds` 272 B, `pars_stamp.rds` 1.9 KB. gq registry matches 99.99% of BT + GR tokens.
- [x] `/code-check` clean → commit (script + artifacts + checkbox).

## Phase 3 — Write `vignettes/pars-mapping-code.Rmd`
- [x] 8 sections: orient → **Modelling parameters** (`xciter` species/gradient param table + `lnk_stamp` provenance) → **Cached inputs** (`system.file` + GitHub raw links) → **Reproducing bcfishpass (parity)** (kable of cached parity tibble + BT full-WSG map) → **Arctic grayling — a link extension** (GR full-WSG map) → **Maps — detail comparison** (BT vs GR sub-reach via the `gq` registry — `gq_reg_main()` + `gq_tmap_classes()` + base-R `plot`/`legend`, fresh's recipe; hillshade dropped — no PARS DEM shipped) → **From vignette to report** (Peace 2025 appendix / template#192) → **References**.
- [x] Model-run chunks `eval=FALSE`; data-load chunks read cached artifacts (`system.file` gpkg + 2 rds). No DB touched at build — confirmed by full local render.
- [x] Positioning prose reviewed against #192 ("complements and extends, never supersedes"; Norris stack framed foundational, credited inline).
- [x] `/code-check`: round 1 caught a factually-wrong GR map caption ("broader" — data shows GR 19,233 < BT 31,932 classified segs); corrected to "smaller, but 1,764 GR-only segments". Round 2 clean. Render verified: 3 figures numbered, 2 tables, citations resolved, no raw `@keys` leaked.

## Phase 4 — Render + verify
- [x] Render verified two ways, both tunnel-free: (1) `rmarkdown::render` via the `bookdown::html_vignette2` engine — **figures numbered 1/2/3**, 2 tables, citations resolved, no raw `@keys`; (2) `pkgdown::build_article("pars-mapping-code")` — all 3 figures + captions + tables + citations render. pkgdown flattens bookdown "Figure N" numbering by design (articles path), but the vignette uses **no `\@ref()` cross-refs**, so nothing breaks; numbering is present in the shipped vignette build. No DB touched — chunks read `system.file("vignette-data/...")` only. Required a local `pak::local_install` so `inst/vignette-data/` ships; pkgdown CI installs before building, so `system.file` resolves there automatically.
- [x] `lintr::lint_package()`: **vignette now 0 lints** (wrapped 3 long caption/sprintf strings with `paste0`). data-raw script retains 4 `indentation_linter` on multi-line SQL — accepted in Phase 2, matches the shipped `wsg_compare.R` pattern. Package-wide pre-existing lints (~1,250, this is a relaxed data-pipeline repo) unchanged / out of scope.
- [x] `/code-check` clean (fresh-eyes round confirmed the `paste0` wraps preserve exact caption text + all sprintf format specifiers) → commit.

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
