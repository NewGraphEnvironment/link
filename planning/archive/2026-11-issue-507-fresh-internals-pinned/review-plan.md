# Plan review: #507 (fresh's internals pinned by argument, at fresh 0.56.0)

Blockers raised: 0
Owner forks: 1

Plan agent, synchronous, 2026-11-23, on the drafted `task_plan.md`. Each finding probed where cheap; verdicts below. The owner fork is the existing 0.56.0-vs-0.57.0 decision, which the review sharpened (finding 12).

1. Gap: `identical()` too strict at run time (the floor is `>=`, the check gates launches at `study_area_run.sh:1019`, `cypher_prep.sh:237`, `worker_prep.sh:105`). **Folded:** leading run plus defaults at run time, `identical()` in the test.
2. Gap: fresh#329 asks for names, not order. **Folded:** the owed comment says the list is ordered.
3. Gap: the walker read the first argument positionally; a named `ns`/`x` call misreads; a non-literal `ns` would be skipped; `utils:::` head. **Folded:** `match.call()` normalisation, refuse non-literal `x` or `ns`, reuse `pretest_ns_calls()`'s shape.
4. Gap: `get(…, asNamespace("fresh"))`, `$`, `getExportedValue()` unseen. **Folded** as a stated known limit; `fresh:::` in R/ already caught by the exports guard.
5. Gap: a namespace walker cannot be tested on a plain function. **Folded:** per-function helper `.lnk_fresh_internal_calls_in()`.
6. Gap: `data-raw/query_habitat_thresholds_mad.R:164` calls `fresh:::.frs_rule_to_sql`. **Confirmed** (grep); named in the plan and the owed fresh#329 comment, not pinned (off the run path).
7. Assumption: the gate never reads `RemoteSha`; `FRESH_GIT_SHA` is accepted. **Accepted** (`R/lnk_stamp.R` tier 1).
8. Assumption: a gate record clears a launch only when its fresh SHA equals the installed one (`data-raw/pretest.R:590`, confirmed). **Folded:** Phase 5 runs `--pick-only`; the full gate is owed after merge and the shared-library install.
9. Assumption: 0.56.0's refusals are near a no-op for link. **Folded** into Phase 3's check; `compare_adms.R`'s `frs_habitat()` noted.
10. Ordering: run the gate's fresh reach at v0.56.0 (`test-pretest.R:584`, confirmed). **Folded** into Phase 3.
11. Ordering: version bump before the gate is fine. **Accepted**, no change.
12. Open decision: 0.57.0 also tightens rules-file loading, which reaches `lnk_rules_build()`'s output. **Folded** as a second reason to defer; still the owner's.
13. Scope: two arguments carry one list. **Folded:** `.lnk_fresh_required_internal()` derived from the formals list's names.
14. Scope: the drivers' "missing required symbols" line (`study_area_run.sh:1027`, confirmed). **Folded** as a Phase 1 checkbox.
15. Acceptance: #507 says "with the pre-run gate run on it". **Folded:** the PR and closing comment say it is owed.
16. Acceptance: "tests pass" ambiguous across libraries. **Folded:** two named runs.

## Files the plan names

R/lnk_preflight_fresh.R
tests/testthat/test-lnk_preflight_fresh.R
DESCRIPTION
RUNBOOK.md
NEWS.md
CLAUDE.md
man/lnk_preflight_fresh.Rd
data-raw/pretest_inputs.csv
data-raw/pretest.R
data-raw/pretest_run.sh
data-raw/pretest_reach_fresh.R
data-raw/study_area_run.sh
data-raw/cypher_prep.sh
data-raw/worker_prep.sh
data-raw/logs/fresh_pin_481/
data-raw/query_habitat_thresholds_mad.R
R/lnk_pipeline_connect.R
R/lnk_config.R
R/lnk_discharge.R
R/lnk_pipeline_persist.R
R/lnk_pipeline_classify.R
R/lnk_stamp.R
tests/testthat/test-pretest.R
