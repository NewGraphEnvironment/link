# Plan review of #478 (park review, 2026-11-22)

Blockers raised: 2
Owner forks: 3

A Plan agent reviewed the plan against #478, its six member issues, and the code. Each finding was probed before it was folded in.

- **Blocker (confirmed, folded): the 22 PSCIS ties are settled by the pick, not the snap.** The snap runs with `num_features = 5` (R/lnk_pipeline_pscis_build.R:65), and `.lnk_pscis_pick_order` ends on `linear_feature_id ASC` (:538). Now open decision 2.
- **Blocker (confirmed, folded): `frs_aggregate()` joins on the 4-argument `fwa_upstream`** (fresh v0.55.1 R/frs_aggregate.R:166). That form is measure-blind on the crossing's own localcode, so a measure test on the same line is added in Phase 2.
- Gap (folded): `frs_aggregate()` uses an inner join (zeros needed), matches a stream head with `[ds, us)`, takes `features` as an identifier only (needs a temp table) and has no prefilter (timed on BULK).
- Gap (folded): upstream habitat crosses watershed groups, so parity needs every upstream group persisted.
- Scope, owner (open decision 3): where the per-crossing table lives, and the breaking change to `lnk_aggregate()`'s output.
- Assumption (folded): the wrapper needs an id argument and a wider collision list. `num_features > 1` survives the wrap, and the build reads only the snap columns.
- Assumption (folded): `.lnk_crossings_union()` reads `<schema>.pscis`, not the snap output; its roxygen is stale.
- Gap (folded under decision 2): the dam snap (R/lnk_wsg_downstream_check.R:99) also ends on `linear_feature_id`.
- Gap (folded): `.lnk_sql_locate()` COALESCEs to a fallback, so the sweep counts its first arm. The threshold script's `fwa_locatealong` calls are added to the sweep.
- Gap (folded): the sweep runs on the local docker fwapg only, and fresh's gate helpers are ported.
- Acceptance (folded): each test's "before" is named (the old link code for the snap tests, the migration for head locates).
- Ordering/Acceptance, owner (open decision 4 revised): the cut spec cannot see the snap rule, so the token turns on a province-wide before/after diff.
- Gap (folded): the RUNBOOK target is the PSCIS-pick paragraph (RUNBOOK.md:167-176), not §2a.
- Scope (decided, not an owner fork): #356's committed CSVs stay as the records of their runs, with a note in their READMEs. The cost of a provincial re-model is an owed item, on the operator's word.

## Files the plan names

planning/active/task_plan.md
R/lnk_points_snap.R
R/lnk_pipeline_pscis_build.R
R/lnk_crossings_union.R
R/lnk_wsg_downstream_check.R
R/lnk_barriers_unify.R
R/lnk_barriers_emit.R
R/lnk_aggregate.R
R/lnk_vocabulary.R
inst/extdata/vocabulary.csv
NEWS.md
DESCRIPTION
RUNBOOK.md
CLAUDE.md
tests/testthat/test-lnk_points_snap.R
tests/testthat/test-lnk_aggregate.R
data-raw/crossings_parity.R
data-raw/query_habitat_thresholds_obs.R
data-raw/query_habitat_thresholds_mad.R
research/bcfishpass_parity.md
