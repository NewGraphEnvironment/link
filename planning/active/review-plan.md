# Plan review for #471 (2026-11-22)

Blockers raised: 0
Owner forks: 0

Reviewer: Plan agent, read-only. Each finding probed before folding.

- Gap, wrong path: `soul/skills/_shared/research_check.sh` does not exist in the checkout; it is at `/Users/airvine/Projects/repo/soul/skills/_shared/research_check.sh`. Folded.
- Gap, `lnk_preflight_vintage`: no `presence` argument (grep empty). Probed true; dropped from phase 2.
- Gap, Rd links: `R/` holds no file for `lnk_override_validate`, `lnk_override_apply`, `lnk_score_severity` (`ls R` empty, probed). Backticks or rewrite; check their examples and the runtime message. Folded.
- Gap, non-ASCII: em dashes sit in strings; use `—`, check tests that match messages. Folded.
- Gap, generator: l.662-670 is a computed paragraph; keep it; hand-edit the generated file, since regeneration needs a database. Folded.
- Gap, CLAUDE.md: no link to `research/README.md` exists (probed). "Link once" is an addition. Folded.
- Scope: cap "re-verify" (do not date unchecked files). Folded. Version/NEWS: patch, stated at the gate. Folded.
- Acceptance: non-ASCII grep, allowed-hits list for `study_areas.md`, README and DESCRIPTION grep, CI as final evidence for `error-on`. Folded.
- Assumption: `R CMD check` is runnable here; compare against CI, state the command in the PR.

## Files the plan names
.github/workflows/R-CMD-check.yaml
CLAUDE.md
README.md
DESCRIPTION
data-raw/study_area_buckets.R
data-raw/study_area_remote.sh
tests/testthat/test-lnk_pipeline_prepare.R
R/lnk_access.R
R/lnk_barrier_overrides.R
R/lnk_compare_mapping_code.R
R/lnk_compare_rollup.R
R/lnk_crossings_union.R
R/lnk_pipeline_load.R
R/lnk_pipeline_prepare.R
R/lnk_pipeline_pscis_build.R
R/lnk_rules_build.R
R/lnk_stamp.R
R/lnk_wsg_downstream_check.R
R/lnk_wsg_resolve.R
R/lnk_pipeline_access.R
R/lnk_pipeline_mapping_code.R
R/lnk_barriers_unify.R
R/lnk_load.R
R/lnk_source.R
research/README.md
research/study_areas.md
research/study_area_run.md
research/study_area_scope_and_funders.md
