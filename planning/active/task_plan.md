# Task: Backlog move 3: Docs, and a check that fails on warnings (#471)

Move 3 of `planning/backlog.md`. One PR for five small issues: #456 (README wording), #279 (research index and flagged files), #275 (one study-area scope document), #385 (clear R CMD check warnings, then gate on them), #493 (a test whose grep matches a comment). No gate. Cheap, and every later move is checked on warnings.

## Decided at the gate

- 2026-11-22, owner approved this plan as a `park review` (baseline only; the Plan review ran before the baseline and is folded in below, see `review-plan.md`).
- **Split #279.** This PR takes the CLAUDE.md link, the index check, the 9 "mark historical" headers and the `**Verified:**` lines that can be checked cheaply. The six "grown into a log" files (`habitat_thresholds.md`, `study_area_run.md`, `bcfp_segmentation_parity.md`, `bcfishpass_parity.md`, `bcfishpass_comparison.md`, `bcfp_compare_mapping_code.md`) are consolidated in their own issue; #279 stays open for them.
- `research/README.md` already exists with an index; #279's first item is a check and a fill of gaps.
- The claim on #471 read `dispatch:link_471` while the session is `link_m1_471` (same worktree, no `link_471` session exists); treated as this session's, replaced by the branch claim.
- Version and NEWS: docs, CI, `man/` and error-string changes only, so a patch. `/gh-pr-merge` infers the bump; state in the PR body that no behaviour changes.

## Phase 1: #493, fix the failing test
- [x] `tests/testthat/test-lnk_pipeline_prepare.R` (~l.1185): drop comment lines first (`grep("^\\s*#", remote, invert = TRUE, value = TRUE)`), then `grep("wsg_run_one.R", ...)`, so only the command at `data-raw/study_area_remote.sh:115` matches; keep the `export LNK_HABITAT_GATE=0 &&` check.
- [ ] Fails on `main` first, passes after; restoring a comment match fails it.

## Phase 2: #385, clear the warnings, then gate
Review changed this phase: run `devtools::check()` first and fix what it names.
- [x] Non-ASCII in code lines: 12 files (`R/lnk_access.R`, `lnk_barrier_overrides.R`, `lnk_compare_mapping_code.R`, `lnk_compare_rollup.R`, `lnk_crossings_union.R`, `lnk_pipeline_load.R`, `lnk_pipeline_prepare.R`, `lnk_pipeline_pscis_build.R`, `lnk_stamp.R`, `lnk_wsg_downstream_check.R`, `lnk_wsg_resolve.R`, `lnk_rules_build.R`). Em dashes in `stop()`/`paste0()` strings become `—` escapes (message text unchanged); in code comments, ASCII. Roxygen-only non-ASCII does not warn: leave it. `grep -rn "—" tests` first, since a test may match a message.
- [x] Rd links: `[cols_barriers]` (`R/lnk_barriers_unify.R:6`, internal object) to backticks; `lnk_override_validate`, `lnk_override_apply` (`R/lnk_load.R:5,29`) and `lnk_score_severity` (`R/lnk_source.R:11,15`) name functions with no `R/` file: rewrite the sentences or use backticks. Check `R/lnk_source.R:41,108` and `R/lnk_load.R:73-75` (examples and a runtime message that call them).
- [x] Undocumented `presence`: add `@param presence` to `R/lnk_pipeline_access.R` (l.134; beside `wsg_presence`, l.76; an `lnk_presence` object that overrides it, l.164-171) and `R/lnk_pipeline_mapping_code.R` (l.97). `lnk_preflight_vintage` has no such argument: not in scope.
- [x] `devtools::document()`: if the installed roxygen differs from `RoxygenNote`, revert unrelated `man/` and `DESCRIPTION` churn (`git diff --stat`).
- [x] `devtools::check()` 0 warnings, 0 errors; notes listed in the PR. Non-ASCII check prints nothing: `for f in R/*.R; do grep -nP '[^\x00-\x7F]' "$f" | grep -vP '^\d+:\s*#'; done`.
- [x] `devtools::test()` after the string edits.
- [x] Last, same commit as the clean check: delete `error-on` and its comment from `.github/workflows/R-CMD-check.yaml`. The PR's CI run is the final evidence (it uses the shared workflow at `flows@v1`).

## Phase 3: #456, README wording
- [x] `README.md` l.9 ("rule and threshold", "the rules that produced it") and l.27 ("its rules are tables"): "fish habitat definitions" at first mention, "habitat definitions" after, never "definitions" alone. Keep l.93's bcfishpass "rules".
- [x] `grep -n -i rule README.md` leaves only l.93; also check `DESCRIPTION`'s Description and the pkgdown home (built from the README).

## Phase 4: #275, one study-area scope document
- [x] `study_area_scope_and_funders.md` stays canonical for scope. In `data-raw/study_area_buckets.R` (l.635-672) replace only the funder table and prose (l.641-661) with a pointer; keep the computed "focal set is all N groups; M modelable" paragraph (l.662-670).
- [x] Regeneration needs `fresh::frs_wsg_outlets()`, `frs_wsg_drainage()` and a database: hand-edit `research/study_areas.md`'s section to match the generator, and say so in its header. Keep `study_area_scope_and_funders.md:8` consistent.
- [x] `research/study_area_run.md` l.16 and l.34: the scope file for scope, the generated file for buckets.
- [x] `grep -rn study_areas.md` returns only the allowed hits: pointers, `RUNBOOK.md:3276`, `research/README.md:49`, the generator header (l.45, 81, 109, 628), NEWS history.

## Phase 5: #279, research index (this PR's share)
- [ ] `CLAUDE.md`: add one line linking `research/README.md` (none exists; l.4374 is floodplains'); keep individual citations only where a rule depends on the file.
- [ ] `research/README.md`: every file has a row; cutover line and "Related work" present.
- [ ] Mark the 9 dated records historical (header line: dated record, naming the topic file that carries the finding).
- [ ] `**Verified:**` on the 10 living files only where the file was actually checked against the code; otherwise a header line saying it is unverified. Never date an unchecked file.
- [ ] Consolidation issue for the six grown files filed and linked from #279's body and the backlog move text.

## Open decisions

(none: the Plan review raised no owner forks)

## Owed at the end (reported, done after merge)

- [ ] Consolidation issue for the six grown research files, filed and linked from #279 (issue body review first).

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: `devtools::test()` (grep FAIL/ERROR), `lintr::lint_package()`, `devtools::check()` 0 warnings, `/Users/airvine/Projects/repo/soul/skills/_shared/research_check.sh` flags only the six consolidation files, the grep checks in phases 2 to 4.
