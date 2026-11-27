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
