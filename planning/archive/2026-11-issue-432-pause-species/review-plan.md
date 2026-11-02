# Plan review for #432 (Plan agent, 2026-11-02, read against the branch at 557cc647 + Phase 3 in the working tree)

Findings, each with what was done about it.

## Blocker
1. **Multi-host runs: KO/RB rows stay in the dispatcher's schema.** Hosts would init persist with the filtered `cfg$species`, so they hold no `streams_habitat_ko/rb`; `schema_consolidate.R` replaces per bucket only in tables both sides share (`:493-495`, `:586`), and the clearing ran on the host. **Done:** `lnk_persist_init()` adds `cfg$species_paused` itself, so a pause never changes the schema's shape on any host and consolidate's per-group replace reaches the paused tables. Verifier assertion added: no `streams_habitat_<sp>` rows for a run group whose newest finished log row of the run does not list `<sp>`.

## Ordering
2. Phase 4's "before" build cannot run on the branch (acc-v4 retired). **Done:** the before arm runs from a worktree at 07203cde, the after arm from the Phase 3 commit; plan wording changed.
3. Clearing ran after the second persist. **Done:** moved right after the first persist (which replaces the group's streams).
4. `paste0()` over an empty species vector. **Done:** column generators and `lnk_access()` guarded; `wsg_recompute_one.R` guards its prior table.

## Gaps
5. `streams_near_river` stale rows. **Done:** the clearing deletes the group's rows for pairs the build no longer owns (`.lnk_near_river_pair_sets()`, shared with persist).
6. `lnk_mapping_code()` direct callers stop on a group with no habitat. **Left:** fails loud for a direct call; the pipeline path writes base rows.
7. Compare fails on paused-only groups. **Done:** `study_area_compare.R` skips them with a NOTE, and exits 0 when none is left.
8. Variants harness. **Done:** the base builds paused-only groups; the focal gate is skipped when empty; a variant on a paused species is refused.
9. `wsgs_run_host.R` / `wsgs_dispatch.sh` filter on `cfg$species`. **Left:** the pre-#175 dispatchers, superseded by `study_area_run.sh`; noted.
10. Habitat endpoints of KO/RB rows in `user_habitat_classification.csv` still cut streams. **Kept, stated:** break sources other than gradient stay on presence/overrides (as observation tops do); Phase 4 attributes only gradient breaks to the pause.
11. Validator `--species` accepts paused species. **Done:** refused. Pre-pause groups' logged near-river pairs may differ from the filtered resolver; expected, noted.
12. Existing tests asserting the old refusals. **Done** (persist, run; views test passes as written).
13. Observation walk wasted for paused-only groups. **Done:** `observations = NULL` when nothing is classified.
14. The pause is not snapshotted in the run log. **Left:** `config_hash` covers it and `log.species` records the result.

## Assumptions
15. Barrier and override rows do not depend on `cfg$species`. **To pin in Phase 4:** MURT's persisted barriers identical in both arms.
16. Orphan gradient classes use the lowest access gradient over `cfg$species`; CH (0.15) keeps it unchanged. Noted.
17. Presence group expansion: RB present wherever CT or DV is. **Done:** NBNK added to Phase 4; 73 groups lose a gradient class counted with expansion.
18. 241 or 242? **Settled:** `lnk_wsg_resolve()` province mode gives 241 paused (234 without the paused-species fix); CHUK's only cell is DV, so the filter has always dropped it. Test added.
19. Shared `fresh` schema: the clearing removes another bundle's rows for the group. Correct (its segments were replaced); noted.
20. Partial runs before the provincial run leave a mixed schema. Noted in Owed.
21. Habitat view redefinition lock. **Moot:** the view's species set does not change (paused tables kept).
22. CT/DV-only groups are still unmodelled. Pre-existing scope; noted.

## Acceptance
23. Single-host proof misses Blocker 1. **Done:** verifier assertion; consolidate shape argument above.
24. MURT proof needs `LNK_GUARD_DOWNSTREAM=warn` and a recompute row. **Done in Phase 4:** the after arm runs `wsg_run_one.R` + `wsg_recompute_one.R` under one run_uid, then the verifier.
25. Unit tests. Added for the run path, persist with no species, clearing (habitat and near-river), the paused flag, the closure filter.
