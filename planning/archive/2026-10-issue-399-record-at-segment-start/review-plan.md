# Plan review — #399 (Plan agent, 2026-10-30, before the parked baseline)

Reviewer: one `Plan` subagent, read-only, given `task_plan.md`, `findings.md`, the code and
harness the plan names, RUNBOOK §2c / §6b, fresh's walk and bcfishpass's observation SQL.
Each finding was checked against the file it cites before being folded into `task_plan.md`
(all eleven held). Most severe first.

1. **Blocker (acceptance script).** `observation_breaks_396/pre_post_diff.R:120-121,159-171`
   counts any access change on an unmoved start (`dir = 0`) as a violation. In #399 no cut
   moves, so every expected 2 → 1 piece is `dir = 0` and the inherited script aborts on the
   first one. The #399 script asserts `dir = 0` on every piece and `seg_pre = seg_post`, then
   permits exactly one change class (2 → 1 at a record); every other difference is the
   violation. Folded into Phase 3.
2. **Gap.** The walk reads `working_<wsg>.observations` (`R/lnk_pipeline_run.R:295`,
   `wsg_run_one.R:137` `cleanup_working = FALSE`), rebuilt by every run, so after Phase 3 each
   working schema holds whichever config ran last, and the two configs filter differently.
   #396 rebuilt the filtered set with `build_obs.R` into `zz396_cuts` on m4, not m1. Add a
   `build_obs.R` step writing `zz399_obs.<config>_<wsg>` with
   `.lnk_pipeline_prep_observations()`; never read `bcfishobs.observations` for the predicate
   (any group, no exclusions). Folded into Phase 3.
3. **Gap.** `tests/testthat/test-lnk_log.R:797` asserts `'acc-v1'` in `default_tuned`'s log
   INSERT; `CLAUDE.md:42` names the shipped tokens. Both added to Phase 2.
4. **Gap.** The fixture as sketched returns `c(1L, 1L)`: every `fwa_upstream` arm first requires
   `wscode_ltree_b <@ wscode_ltree_a`. Columns written into Phase 1 (segments
   `id_segment, watershed_group_code, blue_line_key, downstream_route_measure, wscode_ltree,
   localcode_ltree`; observations `species_code, blue_line_key, downstream_route_measure,
   wscode, localcode` with the same ltree codes and `wscode = localcode`; `barriers_x` with
   `barriers_x_id` and the four keys, empty). Pass `wsg_presence = list(x = TRUE)`; compare by
   `id_segment`, not row order (`segments_sql` has no ORDER BY); `pg_temp` tables suffice.
5. **Acceptance.** Only the same-line arm differs between `TRUE` and `FALSE`, so a piece
   differs iff a same-line record of the species lies in `[s − 1, s + 1)` and nothing of the
   species is upstream; given POST = 1 the second half is implied. The predicate becomes
   `at_record` over that half-open interval, read from `zz399_obs`. Folded into Phase 3.
6. **Assumption.** bcfishpass's `spp` CTE has no group filter on the observations side; link's
   walk reads the group-filtered table (#401), so a residual on a main stem below an upstream
   group is possible. Classify any residual piece by mechanism (`upstream_group` flag reading
   `observations_province`) rather than require ≈ 0. The new `parity_pieces.sql` header states
   the new rule; #403's copy stays frozen. Folded into Phase 3.
7. **Assumption.** `introduced` cannot be edited once committed (`vocab_append_only`), so
   `0.72.0` in the table commits the release to a minor bump. Phase 4: the PR body tells
   `/gh-pr-merge` to bump minor to 0.72.0.
8. **Confirmed.** The vocabulary change passes the invariants test (spec uniqueness is over
   live rows only), the append-only check, and `.lnk_vocabulary_match()`. The "retired and
   live share a spec" case belongs in the existing test at `test-lnk_vocabulary.R:263-274`.
9. **Confirmed.** The mocked call-log test is not redundant: the fixture skips without the
   docker DB, so in CI the call-log test is the only guard on the argument.
10. **Scope.** Missed readers: `research/known_suspected_km.md:18, :74` (body text, not only
    the new section), `CLAUDE.md:42`. Correctly untouched: `R/lnk_barrier_overrides.R:165`
    (barriers, downstream), the validator's "segment starting within 1 m" (segmentation, not
    code 2), `NEWS.md` history, vignettes. Folded into Phases 2 and 4.
11. **Ordering.** None beyond item 1. The recompute omission is right; PRE resolves `acc-v1`,
    POST `acc-v2`.
