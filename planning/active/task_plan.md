# Task: Ship the bcfishpass vignette (tight)

Vignette was pulled to `dev/habitat-bcfishpass.Rmd.draft` in v0.11.2.
Pipeline now runs again (v0.12.0 + fresh 0.22.0). Ready to bring it
back, with content radically tightened — "extremely tight" per the
ask. Public site shouldn't carry anything that doesn't earn its place.

## Goal

Ship `vignettes/habitat-bcfishpass.Rmd` with:

- One paragraph each for: what bcfishpass is, what the bundled config
  expresses, prereqs (fwapg required, comparison tunnel optional)
- The 6-line `lnk_pipeline_*` entrypoint (already written)
- The rollup table — apples-to-apples now via `streams_habitat_linear`
- The CH map — Neexdzii Kwa, link vs bcfishpass-published toggle
- Pointer to `research/bcfishpass_comparison.md` for everything else

Cut:
- The DAG ASCII art (research doc has it; visual in a knitted vignette
  is awkward anyway)
- "Where breaks go" / "Where classification comes from" / "Known-habitat
  overlay" subsections (research doc)
- "Stream-order bypass — not applied" (research doc; documented as
  follow-up)
- "Reproducibility" generic boilerplate
- "Further reading" lists that duplicate pkgdown's own navigation

Target: ~150 lines including frontmatter + chunks. Was ~400.

## Phases

- [ ] Phase 1 — PWF baseline (this file + minimal findings + progress)
- [ ] Phase 2 — Re-run targets pipeline against current state (fresh 0.22.0 + link 0.13.0 + retargeted bcfishpass-side query). ~18-20 min on M1. Capture log under `data-raw/logs/`.
- [ ] Phase 3 — Sanity check new diff_pct values: SK BABL should flip from positive to negative (link < published). BT/CH/CO/ST modest shifts. RB stays NA on the bcfp side (no published column).
- [ ] Phase 4 — Run `Rscript data-raw/vignette_reproducing_bcfishpass.R` to regenerate `inst/extdata/vignette-data/{rollup,sub_ch,sub_ch_bcfp}.rds` from the post-fresh-0.22.0 + post-retarget state.
- [ ] Phase 5 — Rewrite `dev/habitat-bcfishpass.Rmd.draft` to the tight scope. Cut six subsections; keep the entrypoint chunk (already aligned with current API); rewrite the rollup-discussion paragraph for the new comparison.
- [ ] Phase 6 — `git mv dev/habitat-bcfishpass.Rmd.draft vignettes/habitat-bcfishpass.Rmd`
- [ ] Phase 7 — Local render: `rmarkdown::render(...)` on the vignette to a tempdir; verify clean knit, kable output sane, mapgl map renders, no broken cross-refs.
- [ ] Phase 8 — `/code-check` on staged diff
- [ ] Phase 9 — `devtools::test()` — should be clean (no R changes other than the comparison query already merged separately? actually still on this branch — need to handle)
- [ ] Phase 10 — Update `README.md` "Full pipeline" section to re-link the (now-shipped) vignette
- [ ] Phase 11 — NEWS 0.13.1 entry; DESCRIPTION 0.13.0 → 0.13.1 (patch — vignette content + supporting query change)
- [ ] Phase 12 — PR

## Critical files

- `data-raw/compare_bcfishpass_wsg.R` — already retargeted on this branch (stash popped); commit it
- `data-raw/_targets.R` — re-run output
- `data-raw/logs/20260427_*.txt` — log artifact
- `inst/extdata/vignette-data/{rollup,sub_ch,sub_ch_bcfp}.rds` — regenerated
- `dev/habitat-bcfishpass.Rmd.draft` → `vignettes/habitat-bcfishpass.Rmd`
- `README.md` — re-link
- `NEWS.md`, `DESCRIPTION` — release artifacts

## Acceptance

- `vignettes/habitat-bcfishpass.Rmd` exists, total < 200 lines
- pkgdown site picks it up at `/articles/habitat-bcfishpass.html` after merge
- Rollup table reflects `streams_habitat_linear` reference
- Map renders both layers correctly (link layer default, bcfp toggle)
- `lnk_config_verify()` clean on both bundles
- `devtools::test()` clean

## Risks

- **Pipeline rerun cost**: ~20 min, single shot, DB needed. Manageable.
- **diff_pct sign flip on SK BABL** is the most visible change in numbers — make sure the prose acknowledges it.
- **Pre-existing pre-1.0 churn signal**: link tagged 4 versions today (0.11.1 / 0.11.2 / 0.12.0 / 0.13.0). One more (0.13.1) for the vignette is fine but worth noting in PR body that we're back to a stable surface.

## Not in this PR

- Stream-order-parent bypass (separate issue, ~easy follow-up)
- crate#2 / link#65 canonicalization-at-ingest (blocked on crate v0.0.1)
- Any further methodology additions
