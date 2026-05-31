# Progress — PARS Peace mapping_code vignette (#215)

## Session 2026-05-31

- Plan-mode exploration — explored flooded vignette template, link function signatures, gq
  symbology registry consume pattern; phases approved by user (after one revision adding gq).
- Filed issue #215.
- Created branch `215-vignette-pars-peace-mapping-code-link-bc` off main.
- Scaffolded PWF baseline (task_plan.md / findings.md / progress.md) with approved phases.
- Phase 1 done (commit c4babc9): DESCRIPTION Suggests + Remotes + VignetteBuilder; `vignettes/`
  + seeded `references.bib`; gq/xciter already installed; gq registry consume pattern verified.
- Phase 2 done: `data-raw/pars_vignette_data.R` reads the authoritative #175 DS-first persists
  (model state NOT recomputed — a standalone PARS run would miss cross-WSG `;DAM`). Tunnel-free
  `lnk_compare_mapping_code` → BT 99.04% (only bcfp-config species in the Peace; Pacific salmon
  absent above WAC Bennett Dam). `fresh_default` adds GR (19,233 segs) for the showcase. Cached
  `pars.gpkg` (9.7 MB), `pars_parity.rds`, `pars_stamp.rds`. gq registry matches 99.99% of tokens.
  Dropped rollup/annotate (need live bcfp tunnel; breaks tunnel-free design).
- Next: Phase 3 — write `vignettes/pars-mapping-code.Rmd`.
