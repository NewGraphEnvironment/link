# Plan review for #475 (2026-11-22, Plan agent, before the parked baseline)

Blockers raised: 3
Owner forks: 3

Each finding was probed before folding (`config.yaml:93`, `study_area_run.sh:1614`, `state_clean.sh:87-97`, `lnk_publish.R:7,37` read directly).

1. **Blocker: the usage line said `default` writes to `fresh_default`; it resolves to `fresh`.** Confirmed (`inst/extdata/configs/default/config.yaml:93`). Folded: the usage line is accurate, and `wsg_run_one.R`, `wsg_recompute_one.R`, `barriers_views_build.R` get `study_area_run.sh:491`'s schema guard.
2. **Blocker: a required `CYPHER_PREP_CONFIG` breaks the install stage.** Confirmed (`study_area_run.sh:1614` runs `STAGE=install` with no config). Folded: required at `STAGE=all` only, checked at the top.
3. **Assumption: decision 1's minted uid reversed #334's publish gate.** Confirmed (`R/lnk_publish.R:7`). Folded: decision 1 reframed to (b, recommended) / (a′) / (c). Owner fork.
4. **Gap: the decision block's placement and `--preflight-only`.** Folded: print after the overlap block, before the first write; resolve under `--preflight-only` only with focals; species from `study_area_wsgs.R`; capture the primitives date.
5. **Gap: Phase 1 missed live references** (`research/provincial_run_runbook.md`, `RUNBOOK.md:428,3506`, `query_schema_delta.R`, `study_area_buckets.R`, `wsg_pipeline_run.R`), and `R/utils.R` voids the gate too. Folded.
6. **Scope: drivers defaulting to `default`.** Decided in scope: #278's acceptance covers them. Folded into Phase 2.
7. **Blocker: `--tables=` would inherit an unconditional kill step; failures report success; the host model is stale.** Confirmed (`state_clean.sh:87-97`). Folded: skip the kill step and refuse during a live run, check exit statuses, stub `ps`/`kill`/`pkill` in tests. Which hosts it reaches is open decision 3 (owner fork).
8. **Acceptance: data-raw tests skip in CI; the run-uid test needs a database.** Folded: local `devtools::test()` recorded in the PR; the label/uid rule goes in a testable function.
9. **Assumption: decision 2's gate argument was overstated.** Folded: the reason is now the evidence citations and external callers. Owner fork (rename scope).

## Files the plan names

data-raw/wsgs_dispatch.sh
data-raw/wsgs_run_host.R
data-raw/wsgs_run_pipeline.sh
data-raw/wsgs_run_m4_offline.sh
data-raw/trifecta_15wsg.sh
data-raw/trifecta_smoke.sh
data-raw/runs_archive.sh
data-raw/buckets_balance.R
data-raw/progress_check.sh
data-raw/state_clean.sh
data-raw/cypher_prep.sh
data-raw/wsg_compare.R
data-raw/wsg_pipeline_run.R
data-raw/query_schema_delta.R
data-raw/study_area_buckets.R
data-raw/study_area_run.sh
data-raw/study_area_wsgs.R
data-raw/study_area_compare.R
data-raw/study_area_finish.sh
data-raw/study_area_remote.sh
data-raw/study_area_hosts.sh
data-raw/recompute_parity.sh
data-raw/recompute_sweep.sh
data-raw/wsg_run_one.R
data-raw/wsg_recompute_one.R
data-raw/host_stamp.R
data-raw/host_vintage.R
data-raw/barriers_views_build.R
data-raw/parity_crosssection.R
data-raw/access_disagree_349.R
data-raw/habitat_variants_build.R
data-raw/habitat_variants_score.R
data-raw/pretest_run.sh
data-raw/pretest.R
data-raw/worker_prep.sh
data-raw/README.md
R/utils.R
R/lnk_publish.R
RUNBOOK.md
research/provincial_run_runbook.md
research/study_area_run.md
research/README.md
inst/extdata/configs/default/config.yaml
tests/testthat/test-pretest.R
tests/testthat/helper-study_area_hosts.R
