# Archive: targets-pipeline refactor (link#38, closed 2026-04-23)

## Outcome

Three-PR arc completed:

- **PR #41 (link 0.3.0)** — six `lnk_pipeline_*` phase helpers extracted from the 635-line compare script
- **PR #42 (link 0.4.0)** — `data-raw/_targets.R` + `compare_bcfishpass_wsg()`, exported `lnk_pipeline_species()`, reproducibility framing
- **PR #43 (link 0.5.0)** — vignette `reproducing-bcfishpass.Rmd`, research doc refresh, retired legacy `compare_bcfishpass.R`

Three consecutive `tar_make()` runs produced bit-identical 34-row rollup tibbles. All species within 5% of bcfishpass reference on all four WSGs (ADMS, BULK, BABL, ELKR).

## What superseded it

- New PWF cycle 2026-04-23 for #44 (wire `barriers_definite_control` into `lnk_barrier_overrides`)
- Issue #45 filed for gradient-class cleanup, parallel-safe
- Issue #40 filed for config CSV provenance + pipeline run stamps (supersedes narrow scope of #24)

## Key lessons captured

- `feedback_verification_logs.md` — always stamp env state in pipeline verification logs
- `feedback_reproducibility.md` — correctness bar is bit-identical output, not "within 5% of bcfishpass"
