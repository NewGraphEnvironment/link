# Progress — A vocabulary for link's outputs (#414)

## Session 2026-10-29

- Plan-mode exploration — phases approved by user (four axes after the first test; derived tokens; `lnk_vocabulary_read()` / `lnk_vocabulary_resolve()`; no rows for extrabreaks/rearbreaks; `acc-bcfp` / `acc-v1`)
- Created branch `414-a-vocabulary-for-link-s-outputs-how-stre` off origin/main
- Scaffolded PWF baseline from issue #414 with approved phases
- Next: start Phase 1
- Phases 1–2: `inst/extdata/vocabulary.csv` (seven tokens, specs written by the resolver's helpers), `R/lnk_vocabulary.R` (`lnk_vocabulary_read()`, `lnk_vocabulary_resolve()`), `.lnk_break_order()` extracted from `lnk_pipeline_break()`, `tests/testthat/test-lnk_vocabulary.R` (10 tests, 1 skip until main holds the table), `research/output_vocabulary.md`. Three guards mutation-tested (species dropped from the digest, observation_breaks always in the cut spec, no `t` normalisation): each turns a test red.
