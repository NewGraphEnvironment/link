# Progress — A vocabulary for link's outputs (#414)

## Session 2026-10-29

- Plan-mode exploration — phases approved by user (four axes after the first test; derived tokens; `lnk_vocabulary_read()` / `lnk_vocabulary_resolve()`; no rows for extrabreaks/rearbreaks; `acc-bcfp` / `acc-v1`)
- Created branch `414-a-vocabulary-for-link-s-outputs-how-stre` off origin/main
- Scaffolded PWF baseline from issue #414 with approved phases
- Next: start Phase 1
- Phases 1–2: `inst/extdata/vocabulary.csv` (seven tokens, specs written by the resolver's helpers), `R/lnk_vocabulary.R` (`lnk_vocabulary_read()`, `lnk_vocabulary_resolve()`), `.lnk_break_order()` extracted from `lnk_pipeline_break()`, `tests/testthat/test-lnk_vocabulary.R` (10 tests, 1 skip until main holds the table), `research/output_vocabulary.md`. Three guards mutation-tested (species dropped from the digest, observation_breaks always in the cut spec, no `t` normalisation): each turns a test red.
- Phase 3: `token_cut/acc/grad/flow` in `cols_log`, written by `.lnk_log_run_start()`; `lnk_pipeline_run()` resolves before the log opens, logged or not; phase tests mock the resolver, a real-resolver test proves a refused config writes no log row and runs no setup; pretest map rows for the two new files. Consolidate already copies shared columns after aligning the destination (`schema_consolidate.R:387-394`).
- Plan review back (`review-plan.md`, triaged). Operator: `observation_exclusions` is data vintage; a bundle loaded by path is refused. Fixes: barrier-input term in the cut spec, code-held access rules in the acc digest, pre-flight gate in `study_area_run.sh`. Mutations: token order in the INSERT, resolve moved into the log call: each turns a test red.
