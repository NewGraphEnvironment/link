# Progress — Backlog move 9 (#477)

## Session 2026-11-27

- Plan-mode exploration — phases approved by user
- Created branch `477-backlog-move-9-mapping-codes-as-rules-an` off origin/main
- Scaffolded PWF baseline from issue #477 with approved phases
- Next: start Phase 1

## Phase 1, 2026-11-27

- Parity BEFORE digests captured from a worktree at `82cf1d08` (36 rows; `fresh` holds no ADMS or HORS mapping codes).
- #351: `.lnk_access_merge_case()` keeps `-9`; a DB test of the `CASE` over nine (scratch, persisted) pairs and a mocked UPDATE test, both failing with the old `CASE` restored. `lnk_pipeline_mapping_code()` takes a named logical presence (`.lnk_presence_fn()`), so `lnk_mapping_code(presence = NULL)` runs.
- #153: a missing habitat column reads 0, a missing habitat row stays NA; roxygen on `lnk_pipeline_species()` and `lnk_presence()`.
- #191: new `test-lnk_pipeline_mapping_code.R`; `lnk_mapping_code()` mocked tests; wide-table DDL and persist gating tests. The expired `*_species` aliases removed (a Phase 2 box, done here).
- Plan review returned (4 blockers, folded into the plan; `review-plan.md`).
- Full suite before the ref fix: 6851 pass, 4 fail, all `dictionary_presence_groups.csv` refs shifted by the roxygen added to `lnk_presence.R`; fixed, README regenerated.
- Next: Phase 2.

## Phase 2, 2026-11-27

- `parameters_mapping_code_rules.csv` in `inst/extdata/` and in `default` and `bcfishpass` (declared under `files:`, `read_as: text`, provenance with checksums); each residence ends on `NONE,TRUE` (review B1).
- `R/lnk_mapping_code_rules.R`: reader, validator (grammar walk, aliases, precedence, tokens, fallthrough), evaluator in an `emptyenv()`-parented environment, and `.lnk_mc_species()` shared by both exported functions (review B3, G2).
- `lnk_pipeline_mapping_code()` and `lnk_mapping_code()` take `cfg` and `rules_mapping_code` (appended last); `.lnk_mapping_code_persist()` passes the run's `cfg`.
- Tests: the 32-row alias grid and a 3^6 raw-column grid (every fallback subset) equal the 0.94.0 chains; validator refusals; a bundle adding a token; #512's BT + anadromous CT smoke test. Breaking the fallthrough check fails 1 test, the alias check 3.
- Parity probe at this code: 0 of 36 digests differ from BEFORE.
- Dictionary, README, `pretest_inputs.csv` rows; dictionary, pretest, config and vocabulary tests pass.
- Next: Phase 3.

## Phase 3, 2026-11-27

- `lnk_pipeline_persist()` → `lnk_persist_write()` and `lnk_compare_wsg()` → `lnk_compare_run()` by `git mv`, no shims; `.lnk_compare_wsg_*` → `.lnk_compare_rollup_*`; `with_mapping_code` removed. Callers swept in `R/`, tests and mocks, live `data-raw/` scripts, `pretest_inputs.csv`, RUNBOOK, and the `default` / `bcfishpass` config comments. `default_rearbreaks` / `default_extrabreaks` config.yaml and `data-raw/logs/` left as written.
- #159: `lnk_pipeline_run()` drops `working_<aoi>` on an error after setup when `cleanup_working = TRUE`, through its own handler (with `log = FALSE` too). Three tests (error drops, `FALSE` keeps, an error at setup drops nothing); disabling the handler fails one.
- `pkgdown::check_pkgdown()` clean.
- Next: Phase 4.
