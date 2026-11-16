# Plan review, #470 (Plan agent, 2026-11-16, read against HEAD `20f44d74` and the uncommitted Phase 2 work)

Findings as the reviewer returned them, condensed to one line each with the evidence it cited.
What was done with each is in progress.md.

## Blocker
1. Undated WCT records drop under `lift_floor`: default's WCT `observation_date_min` is `1900-01-01`
   (configs/default/parameters_fresh.csv:12), and `observation_date >= date_min` is NULL for a NULL date.
   Set WCT's floor to NA (lifts unchanged: NA becomes 1900-01-01 at R/lnk_barrier_overrides.R:144); test it.
2. "Model species" must mean every presence column, not `cfg$species` (CT, DV, RB, KO are not modelled; today
   every present species' records cut and feed the province table). The WIP is right; say so and pin it.
3. Phase 3 cannot build until an acc row exists (`lnk_pipeline_run()` resolves the vocabulary first, R/lnk_pipeline_run.R:178).

## Gap
1. Cut tokens: RUNBOOK §6b (~991) names the CT alias expansion in observation breaks as a code change that moves cuts
   with no spec change. The record rule moves `top_per_species` tops and bcfishpass's `all` positions: `cut-full-top`
   and `cut-full-ssf-all` need successors, or the record rule goes into the cut spec.
2. Hash the resolved map, not the raw tracker (species_groups.csv and wsg_regions.csv also decide it; rationale edits must not).
3. Persist lists for `barrier_override_evidence`: `_HOSTS_PERSIST_CORE` (data-raw/study_area_hosts.sh:434, test-study_area_hosts.R:926),
   test-lnk_persist_init.R:252, test-schema_consolidate.R:364-372, `.lnk_validate_persist_table()`, the init/consolidate test.
4. Pre-run gate map: a row for R/lnk_observation_records.R (test-pretest.R:36); `obs_upstream` on R/lnk_pipeline_prepare.R,
   species_pooling/species_groups (row 99), wsg_regions (row 161), parameters_fresh (rows 92-94).
5. dictionary_species_pooling.csv `consumed_by` refs drift (test-dictionaries.R:278); scope_level text.
6. Presence check drops non-species codes before pooling (line 84); `lift_readers` reads `observation_species`;
   tests at test-lnk_presence_check.R:88, :241, :259 pin today's behaviour.
7. The measures ignore presence, so they need the every-species-present resolution, not the pipeline's map.
8. data-raw/wsg_species_presence_check.R:263-266 keeps its own alias sensitivity vector (DV/BT→DV, RB/CT→RB, a `" RB"` code);
   wsg_species_presence_map.R:87; doc text in R/lnk_log.R:988, RUNBOOK 643-655 and 770, dictionary_parameters_fresh.csv:19.
9. `lnk_habitat_validate()`'s default `species_obs = list(BT = c("BT","DV"))` ignores the tracker; say whether the
   validator follows the tracker and whether date floors apply there.
10. Provenance checksums in config.yaml for every edited bundle file.
11. Tests pinning today: test-lnk_vocabulary.R ~100 (acc-v5, acc-bcfp-4), test-lnk_pipeline_prepare.R SQL shape,
    test-lnk_species_pooling.R:146.
12. Records filed with stray whitespace or case (`" RB"`) never match the exact SQL join; count them.
13. No path if bcfishpass keeps CT aliases (moot if Phase 1 confirms).

## Ordering
1. Provisional `acc-v6` / `acc-bcfp-5` (and cut successors) at the start of Phase 3; recompute after #426 and #427.
2. Phase 1 should record its counts before the code states them as fact.
3. #427 moves the acc spec again: Phase 3's numbers come from an earlier spec than the released one; say so.

## Assumption
1. Pooling follows the record's own group (consistent with the province table): a DV record in pooled upper Skeena
   lifts BT and makes BT code 2 in LSKE downstream. State it, add a cross-boundary fixture, record the group in the evidence.
2. Lift lists that mix date floors would silently take the stricter one under `lift_floor`; refuse them or record the floor.
3. Aliases are one hop (ADV never reaches BT through DV). Two-way rows must stay in lockstep with DV→BT (test).
   A typo'd alias code matches nothing silently: restrict, or check against bcfishobs codes.
4. Fan-out: nothing double-counts (distinct keys, distinct species, DISTINCT positions). The evidence table must take
   DISTINCT over (barrier, species, key). Expect BT's own top to give way to a higher pooled DV record.
5. `lnk_barrier_overrides()` is exported and may get raw bcfishobs (no `species_code_recorded`): fall back, keep evidence optional.
   Habitat lifts still read `observation_species` against habitat rows.

## Scope
- #398 cannot show `access_ct` in a build (CT is modelled by neither bundle): the fixture is the acceptance.
- default_extrabreaks / default_rearbreaks have no tracker and lose CT alias admission; note it.

## Acceptance
- The verify assertion: restrict to the run's groups; NOTE, not FAIL, where the evidence table is absent.
- Fixtures: undated WCT; DV in a pooled group above a barrier in an unpooled one; two-way lockstep; mixed floors refused;
  evidence de-duplicated over a duplicated position; gate map rows.
- "Moves only where a counted or dropped record sits" is too strict: trace each change to a record a cut, lift or
  code 2 now counts or drops.
