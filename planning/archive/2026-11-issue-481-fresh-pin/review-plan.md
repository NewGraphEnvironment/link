# Plan review of #481 (park review), 2026-11-22

Blockers raised: 1
Owner forks: 2

A Plan subagent read the draft against #481, #452 (and its comment), #288, #222, fresh's NEWS and source at v0.55.1, and link at `origin/main` (be06e2b4). Each finding was probed or checked against the code before it was folded into `task_plan.md`.

## Blocker

- **B1: the floor must be 0.55.1, not 0.55.0.** Confirmed: `tests/testthat/test-lnk_preflight_fresh.R:162-170` asserts the `Remotes:` tag equals `.lnk_fresh_floor()`. Folded: the Decided line and Phase 2.

## Gaps

- **G1: delegating to `frs_db_conn` trips the drift guard** (`test-lnk_preflight_fresh.R:124-136`). Folded: Phase 2 adds it to `.lnk_fresh_required()` under decision 1 (a).
- **G2: `data-raw/wsg_vignette_data.R` wants the tunnel through `PG_*_SHARE`.** Confirmed at `:201-210`; the draft's "8 data-raw scripts call it bare" was wrong. Folded: Open decision 1 lists the real bare calls, Phase 4 gives that script explicit arguments and fixes the comments.
- **G3: the validator must check the column before passing TRUE.** Folded: Open decision 2 (a) and Phase 3.
- **G4: the validator fixtures lack the column and insert positionally.** Folded: Phase 3's tests.
- **G5: `test-lnk_db_conn.R` and the no-environment default change under delegation.** Folded: Open decision 1, Phase 4.
- **G6: fresh's deprecation message fires with explicit arguments.** Confirmed in fresh v0.55.1 `.frs_conn_resolve()` (environment read before arguments). Folded: Open decision 1.
- **G7: the digest list left tables out.** Folded: Phase 1 names all eight persisted kinds.
- **G8: the gate can fall back to a database without `public.wsg_outlet`.** Folded: Phase 5 skips on `to_regclass`.

## Ordering

- **O1: Phases 2-5 cannot `load_all()` against the shared library after the bump.** Folded: Decided at the gate, `R_LIBS` throughout.
- **O2: installing into the shared library before the merge moves other sessions.** Folded: moved to Owed.
- **O3: the province schemas' migration takes a lock and rewrites rows.** Folded: Open decision 2 and Owed; the backfill is `WHERE linear_feature_id IS NULL`.

## Assumptions

- **A1: `R CMD INSTALL -l` writes no `RemoteSha`.** Folded: Phase 1 sets `FRESH_GIT_SHA`.
- **A2: scratch schemas need the downstream guard off and a quiet host.** Folded: Phase 1.
- **A3: the variants probe's result is knowable from fresh's code and would modify a kept schema.** Folded: Phase 6 documents it, no probe; Owed rebuilds the bases.
- **A4: NULL rows can arrive by consolidate from an unmigrated host.** Folded: G3's check.

## Scope

- **S1: Open decision 2 lacked "add the column, pass FALSE".** Folded as option (c).
- **S2: `data-raw/logs/minimal_breaks_415/proof.R:317` would break if re-run.** Left as a record; noted in Phase 3.

## Acceptance

- **AC1: "predicates agree with the build" was not measurable.** Folded: Phase 6's three checks.
- **AC2: Phase 5's proof must point `PG*` elsewhere.** Folded.
- **AC3: four scratch schemas, not two.** Folded.
- **AC4: the mocked connection test's details.** Folded: Phase 4.

## Owner forks (under `## Open decisions` in task_plan.md)

1. #288: which variables both connection helpers read (the backlog's named gate).
2. #452: what the persisted rows hold and what the validator passes, and when the province schemas migrate.

The review also named the variants bases and the shared-library timing; both were taken as mechanism (Owed, and `R_LIBS` until merge).

## Files the plan names

DESCRIPTION
R/lnk_preflight_fresh.R
R/lnk_persist_init.R
R/lnk_pipeline_persist.R
R/lnk_habitat_validate.R
R/lnk_log.R
R/lnk_db_conn.R
R/lnk_wsg_resolve.R
data-raw/pretest_inputs.csv
data-raw/pretest.R
data-raw/schema_consolidate.R
data-raw/habitat_variants_build.R
data-raw/wsg_vignette_data.R
data-raw/host_vintage.R
data-raw/study_area_buckets.R
tests/testthat/setup.R
tests/testthat/test-lnk_preflight_fresh.R
tests/testthat/test-pretest.R
tests/testthat/test-lnk_persist_init.R
tests/testthat/test-lnk_pipeline_persist.R
tests/testthat/test-lnk_habitat_validate.R
tests/testthat/test-lnk_db_conn.R
tests/testthat/test-lnk_wsg_resolve.R
RUNBOOK.md
CLAUDE.md
NEWS.md
