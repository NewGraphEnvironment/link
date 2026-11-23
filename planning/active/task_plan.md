# Task: Backlog move 10: Crossings: snapping, and habitat upstream of each crossing (#478)

**If we do it:** points snap by one rule and never to placeholder lines, and each crossing's upstream habitat is summed over its whole network and checked against bcfishpass. **If we never do:** a crossing's upstream habitat misses every tributary.

Move 10 of link's backlog (`planning/backlog.md`): batch 14 (snapping: #313, #314, #383) and batch 15 (habitat upstream of each crossing: #321, #232, #356). One phase per batch, one PR.

## Decided at the gate

Parked by the coordinator (`park review`); the four open decisions were answered by the operator at the resume, 2026-11-23, each as recommended.

1. **#314: wrap `lnk_points_snap()`** on `fresh::frs_point_snap(to =)`. It gains an id argument (fresh needs a unique `col_id`) and keeps link's output columns (`snapped_blue_line_key`, `geom_snapped`, `distance_to_stream`, the ltrees, measure), so the PSCIS build is unchanged and #313's placeholder exclusion comes from fresh.
2. **The tie rule is fwapg's:** `downstream_route_measure DESC` ahead of `linear_feature_id` in the PSCIS pick order (`.lnk_pscis_pick_order`, R/lnk_pipeline_pscis_build.R) and in the dam snap (R/lnk_wsg_downstream_check.R). This departs from bcfishpass's `04_pscis.sql` and can move #232 parity; the departure is stated where the rule lives.
3. **`lnk_aggregate()` writes a long table to a caller-named `to =`** (crossing id, config, species, metrics). Nothing new in the persist schema; today's add-columns behaviour is replaced, a breaking change to an exported function with no callers, recorded in NEWS.
4. **The cut token turns on measurement.** Phase 1 compares the before and after snap-and-pick tables province-wide. If any picked crossing changes `blue_line_key`, measure or presence: new `cut` rows (`cut-full-top-3`, `cut-full-ssf-all-3`), a minor bump, and the groups holding a moved crossing re-modelled in scratch schemas under both configs and diffed against `main` builds. The provincial re-model of both schemas is owed, on the operator's word.

5. **A tie between two different streams follows `[ds, us)`** (met in Phase 1, answered 2026-11-23). fwapg's "higher measure" means nothing across two streams: on the CABD dams it moved one lower Fraser barrier (LFRA, the Crescent Slough confluence) from the slough's mouth (15 segments upstream) to the top end of an unnamed line (17,656 segments, 7,892 km). The tie key is therefore: a candidate whose snapped position is not at its segment's upstream end first, then the higher segment start, then the lower `linear_feature_id`. It equals fwapg's rule on all 49 same-stream dam ties, keeps the slough dam where it was, and departs from fwapg and fresh only across streams; a fwapg/fresh issue is drafted, not filed.

## Open decisions

None open.

## Phase 1: Snapping (batch 14: #313, #314, #383)

- [x] Baseline before any edit, on the local fwapg: snap all PSCIS crossings with today's `lnk_points_snap()` (150 m, `num_features` 1 and 5) and today's pick into scratch tables. Count placeholder picks and candidates, and ties on one stream before and after the pick.
- [x] Wrap `lnk_points_snap()` on `fresh::frs_point_snap(to =)` (decision 1): add the id argument and refuse a missing or duplicate id. Extend the collision check to fresh's `watershed_group_code`, `gnis_name` and `candidate_rank`. Note the NULL-hint change in the docs (no caller passes `blue_line_key_col`). Fix the roxygen that names the gone `frs_point_snap_knn`, and the stale `pscis_assessment_snapped` line in R/lnk_crossings_union.R:16.
- [x] The tie rule per decision 2: the pick order and the dam snap, or the stated exclusion.
- [x] Mock tests updated for the wrapper. A live test that no snap or pick lands on `wscode_ltree <@ '999'` (#313), skipped without a connection. Its "before" is the old link code, not the database.
- [x] Province-wide before/after diff of the snap-and-pick tables. Decide the token (decision 4); if it moves, add vocabulary rows, NEWS and the bump, then re-model the groups holding a moved crossing under both configs in scratch schemas and diff against `main` builds. (Done under `bcfishpass` on seven groups; `default`'s NASR build stalled in the near-river walk beside another session's, 30 and then 17 min, and was cancelled both times; owed.)
- [x] #383 sweep with `fresh::frs_migration_trial()` on the **local docker fwapg only** (a rollback does not undo everything; record the fwapg sha and migration files from `~/Projects/repo/fwapg`). Run before and after on separate connections, each call under its own `SAVEPOINT` with `SET LOCAL statement_timeout`. Inputs: the PSCIS snaps, the stored measures `lnk_barriers_unify()` locates, and the `fwa_locatealong` calls in data-raw/query_habitat_thresholds_obs.R:201-202. Count where `.lnk_sql_locate()`'s first arm (`FWA_LocateAlong`) is NULL (its COALESCE fallback hides it), ties and errors. The before run reproduces the stored output.
- [x] Migration-gated live tests, for head-measure locates only, which are what depend on the migration. Port fresh's helpers (`indexpoint_current`, strict parsing of `LNK_FWAPG_CURRENT`, a direct connection) into tests/testthat/helper. They skip naming the missing migration, and one fails under `LNK_FWAPG_CURRENT=true`. Show each red before and green under the trial.
- [x] `research/` file for the sweep and the snap diff. Update RUNBOOK's PSCIS-pick paragraph (RUNBOOK.md:167-176, "Both KNN snaps end on `linear_feature_id`").

## Phase 2: Habitat upstream of each crossing (batch 15: #321, #232, #356)

- [x] Confirm the defect on ADMS: today's `lnk_aggregate()` against a network-upstream sum, for crossings with habitat on tributaries.
- [x] Rebuild `lnk_aggregate()` on `fresh::frs_aggregate()` (decision 3 for the output). Build the per-species features as a temp table or view: `streams_habitat_<sp>` joined to `streams` on `(id_segment, watershed_group_code)`, with the polygon class (`.lnk_sql_lake_connection()`). `frs_aggregate()` uses the 4-argument `fwa_upstream`, which counts the crossing's own segment and the main stem below it. Add a `where =` measure test on the same `blue_line_key` (or raise a fresh issue for the measure form) and test it. Fill zeros for crossings with no upstream features (inner join). Place a crossing at a whole-metre stream head (`[ds, us)` ref match) or name it. Metrics per species: `spawning_km`; `rearing_km` with connectors out; `rearing_stream_km`, `rearing_lake_km` and `rearing_wetland_km`; `rearing_lake_connection_km`. Sums exact (`sum(...::numeric)`, cast once; #356). Time it on BULK (no prefilter, fresh#272).
- [x] "Below upstream barriers" totals: stop at the next human-made barrier upstream from link's own set (`lnk_barriers_emit()`, working schema), as bcfishpass's `*_belowupstrbarriers_km` does (main-stem crossings).
- [x] Tests on a hand-built network covering a tributary counted, the main stem below not counted, the barrier stop and a zero row. Also the example, and CLAUDE.md's "Integration with fresh" snippet.
- [x] #232: `data-raw/crossings_parity.R` comparing `<schema>.crossings` with `bcfishpass.crossings_vw` on ADMS and BULK: row coverage, per-branch counts, `barrier_status`, and positions (`blue_line_key` and measure within 1 m). Stamp both sides' versions.
- [x] #321 parity under `bcfishpass` on ADMS and BULK, **with every group upstream of them persisted** (BULK's main stem reads MORR, and so on; check with `lnk_wsg_resolve(expand = TRUE)`). Per crossing and species, link against `bcfishpass.crossings_upstream_habitat`, joined on `aggregated_crossings_id`. Report the distribution of differences and annotate departures (side channels, segmentation #324). Into `research/bcfishpass_parity.md`.
- [x] #356 in `data-raw/query_habitat_thresholds_obs.R` and `_mad.R`: sum `length_metre::numeric` and sort before R reductions. Two reruns byte-identical (obs: every output identical, 2026-11-23; mad: blocked on this host by #481's owed `lnk_persist_init()` on `fresh_default`, same change, not rerun). The committed CSVs (`habitat_thresholds_284/`, `_302/`, `discharge_wet_331/mad_*`) stay as the records of their runs, and a note in each log README says so.

## Owed at the end (reported, done after merge)

- [ ] The `default` config's scratch re-model of the groups holding a moved crossing (NASR, JERV, LILL, GUIC) against `main`: blocked here by the near-river walk stalling beside another session's (#487).
- [ ] #356's two reruns of `query_habitat_thresholds_mad.R`, once a host's `fresh_default` has #481's near-river column.

- [ ] Every persisted group in `fresh_default` and `fresh` re-models at the next provincial run if the cut token moved; the pre-run gate runs again (`R/` changed).
- [ ] The live tests that need fwapg#41 run for real once the shared database is migrated (fwapg#41's upstream review).
- [ ] #341 (barrier rule scenarios) reads the per-crossing table.

## Validation

- [x] Tests pass (full suite 6,360 pass, 0 fail, 4 skip, at a3e38823; touched files re-run after)
- [x] `/code-check branch`: four rounds, ended by enumeration (`review-verdict.md`)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the snap's before/after counts on all PSCIS (placeholder picks 11 → 0, ties resolved by fwapg's rule, no other pick moves); the gated tests shown red before and green after under the trial; scratch re-models diffed against `main` builds; per-crossing parity reported as a distribution against bcfishpass; two reruns of each threshold script byte-identical.
