# Progress — streams_habitat_<sp>.accessible disagrees with streams_access.access_<sp> (#349)

## Session 2026-10-19

- Plan-mode exploration: read #336 and #351, traced `.lnk_pipeline_classify_build_breaks()`,
  fresh's `accessible` CTE and override anti-join, `lnk_barriers_views()`,
  `lnk_pipeline_access()` / `frs_network_features()`, `.lnk_pipeline_prep_observations()`,
  `lnk_barrier_overrides()`, `lnk_pipeline_run()`'s phase order; five read-only probes on
  `fresh_default` (findings.md). Four mechanisms found: metre rounding at classify, link's
  ltree/1 m near-equal rule, AOI-filtered breaks vs province-wide access view, and
  observation lifts counted from the barrier's own group only.
- Gate decisions taken by the operator (task_plan.md "Decided at the gate"): streams_access
  authoritative with a persist-side settle step; RB observation rule + province-wide
  observation counting ("an oversight, nothing to debate"); verification on DUNC + CARP in
  scratch `fresh_349`; the `fresh_default` re-gate owed after merge.
- Design review by a Plan agent (22 findings, `review-plan.md`), run in plan mode on the
  design draft before the plan was final; the load-bearing findings were verified against
  the code and folded into task_plan.md. Not re-run on the final plan.
- Phases approved by the operator as **parked**.
- Created branch `349-streams-habitat-sp-accessible-disagrees` off main.
- Scaffolded PWF baseline from issue #349 with the approved phases.
- Next: parked 2026-10-19; resume with the command below, then "start Phase 1".

### Resume

```bash
cd ~/Projects/repo/link && git fetch -q origin && git checkout 349-streams-habitat-sp-accessible-disagrees && git pull --ff-only && git merge origin/main
```

The parked approval covered the baseline only; the run-to-PR mandate starts when the operator
says to resume.

## Session 2026-10-19 (evening, Vancouver) — run to PR

- Resumed on the operator's "Complete all phases of 349 to PR".
- Phase 1: `data-raw/access_disagree_349.R` written and run province-wide (4.0 min). Classes sum
  to the issue's totals for every species. A / A′ ≈ halves; B is every whole-group case (RB,
  KO, GR and BT TURN); residual is small, RB's is ELKR's Flathead. Corrected the plan's KO
  location claim (findings.md). bcfishpass scope pinned at `@620dbe4`.
- Phase 2: `lnk_habitat_gate()` (tests first; the DB test goes red with the UPDATE stubbed out,
  3 failures). `n_lifted_settled` needs the access from before a recompute, so the gate takes
  `table_access_prior`; `wsg_recompute_one.R` and `habitat_variants_build.R` snapshot it.
  `lnk_pipeline_run()` gates after the second persist and builds mapping codes from persist
  through `.lnk_mapping_code_persist()`, now shared with the recompute. Log columns
  `habitat_gate_{n,km,lifted,species}` on `log` and `log_recompute`, written in a second soft
  statement. `study_area_verify.sql` asserts no `accessible AND access_<sp> = 0` row; the
  negative test's new case 6d fires, 12 / 12 cases right on `fresh_default`'s run. Note:
  verify on `fresh_default` itself now fails until decision 4's re-gate runs.
