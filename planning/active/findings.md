# Findings — #367

## Issue context

**If done:** the next provincial `default` run (#361) is built at a release whose output is reproducible run to run and whose Columbia groups see the US dams below them. **If never:** that run ships with both known gaps, and the next run that fixes either has to re-model every group again.

## Scope

One branch, released as v0.68.0 before the run is dispatched. Cyphers reset to `origin`, and every log row stamps the link version, so this has to be tagged first.

1. **#277: make the PSCIS-to-modelled-crossing pick deterministic.** When two modelled candidates share a `linear_feature_id`, the pick ties (`R/lnk_pipeline_pscis_build.R`), so two identical builds can differ by a segment. That happened on 8 lines across the four parity-scored groups at v0.66.6 (#362). Fix: end the ordering on a unique key. Test: build the tie and assert one answer.
2. **#244: `cabd_additions` dams become barriers.** The `usa` CTE in `.lnk_pipeline_prep_dams()` hardcodes `passability_status_code` NULL, and `.lnk_crossings_union()` has no arm for it, so Grand Coulee, Chief Joseph and Ross are dropped. Dams never block access, so this moves mapping codes (the `DAM` token in Columbia groups), not accessible km.
   - `lnk_wsg_downstream_check()` applies the same filter and documents that the placeholders "never appear" (`R/lnk_wsg_downstream_check.R:176-178`). Decide whether the guard should now report them for Columbia groups, and keep the two in step.
   - Re-pin the golden dams test while it is open (#345: 8 ADMS dams pinned, 7 in `cabd.dams`).

## Measured and left out: #316

Construction lines (1200 / 1400) inside wetlands reach no rear rule in `default`. Since #364, 1050 / 1150 lines there rear through the stream door, so the question was whether admitting 1200 / 1400 the same way would matter. Measured on `fresh_default` (run `20261017_004619-3f4c713b`, 241 groups; lines matched to `fwa_wetlands_poly` by `waterbody_key`):

| edge type | km in wetlands | km with a channel width | km passing BT's stream test (width ≥ 1.5 m, gradient ≤ 0.1049) | of which BT-accessible |
|---|---|---|---|---|
| 1200 | 10,294 | 320 | 173 | 92 |
| 1400 | 5,190 | 190 | 155 | 64 |

97 % of these lines have no width, so they would fail the stream door anyway. At most 156 km province-wide would become BT rearing. They stay out of this run; the measurement is recorded on #316.

## Verification

- Prepare once and re-classify (CLAUDE.md, "Full-run digests are not reproducible on main") on ADMS, one Columbia group (SLOC or KOTL) and NATR, reporting the change in mapping codes and rearing km per species.
- Two builds of the same group from the same inputs give identical digests (#277).
- Release bar: `devtools::test()`, `devtools::check()`, `lintr::lint_package()`.

## Not in scope

#326 (breaks only where access changes), #327 (order-1 exception in `default`) and fresh#258 (break tolerance) stay out of this run.

Relates to #361, #277, #244, #316, #345, #364.


## Phase 1: the PSCIS pick (link#277), measured 2026-10-22

Measured with `.lnk_pipeline_pscis_build()` into a scratch schema on the local fwapg (primitive load 2026-10-17). Step 2 builds `pscis_streams_150m` province-wide whatever the AOI, so these counts are province-wide. Script: a scratchpad copy of the queries below, rerunnable by building the table and querying it.

- `pscis_stream_candidates`: 37,992 rows, 37,992 distinct `(stream_crossing_id, linear_feature_id)`, so each PSCIS x stream pair is one candidate.
- Rows passing the pick filter: 33,611, of which 13,481 have no modelled crossing.
- **Under the old order** (`name_score DESC, weighted distance, linear_feature_id`), 1,618 PSCIS crossings had more than one row tied at the top:
  - 931 tied between two or more different modelled crossings: the #277 case, which changes which modelled crossing the PSCIS covers, and so which one stays a separate modelled barrier.
  - 673 tied between rows with no modelled crossing (rows the B-side dedup nulled and the close-enough reset let back in). These differ only in `modelled_xing_dist`.
- **Under the new order**, 116 groups of rows share the whole key (`stream_crossing_id, linear_feature_id, modelled_crossing_id, modelled_xing_dist`), and none of them differ in any column except `geom_snapped`, which comes from the shared candidate. So the pick is deterministic in what it passes on.
- Mutation check: with the old three-term order, the synthetic tie in the new DB test picks 101854 in one row order and 100122 in the other; with the new order, 100122 both times.

### Audit of orderings on the crossings path

| where | ordering | verdict |
|---|---|---|
| `lnk_points_snap()` (Step 1) | `ORDER BY s.geom <-> pt LIMIT k` | Ties only at the k-th boundary decide which segments become candidates. Left: a second sort key would cost the KNN index scan, and ties at the boundary are not what #362 measured. |
| Step 3 B-side `to_retain` | `modelled_crossing_id, modelled_xing_dist, stream_crossing_id` | Rows still tied share the retained `stream_crossing_id`, so the UPDATE is the same. Deterministic. |
| Step 4 pick | `.lnk_pscis_pick_order` | Fixed (above). |
| Step 4c DBSCAN dedup | `cid, distance_to_stream, assessment_date DESC, modelled_crossing_id` | Could tie between two PSCIS with equal distance and date and the same (or no) modelled crossing, and then pick either id. Fixed: ends on `p.stream_crossing_id ASC`. |
| Step 4d `(blue_line_key, downstream_route_measure)` dedup | ends `stream_crossing_id ASC` | Deterministic. |
| Step 5 xref branches | `u.stream_crossing_id, u.branch_rank` | One row per branch per PSCIS. Deterministic. |
| `.lnk_crossings_union()` | no ordering | Nothing picked. |
| Dam snap (`.lnk_dams_matched_sql()`) | inner `ORDER BY <-> LIMIT 1` | A dam equidistant from two segments at a shared node could take either `linear_feature_id`; the measure on the blue line is the same either way. Left, noted. |
| Dam prep `usa` CTE | `row_number() OVER ()` | Placeholder `dam_id`s can swap between runs. Harmless while they are dropped; fixed in Phase 2, where they become barriers. |

## Phase 2: the cabd_additions placeholders (link#244), measured 2026-10-22

- **Where they sit** (all on mainstems, `blue_line_key = watershed_key`), with ids now numbered by `(blue_line_key, downstream_route_measure)`:

  | dam_id | name | line | group |
  |---|---|---|---|
  | 1200000001 | Grand Coulee | Little Sheep Creek | LARL |
  | 1200000002 | Grand Coulee | Big Sheep Creek | LARL |
  | 1200000003 | Ross | Skagit River | SKGT |
  | 1200000004 | Grand Coulee | Kettle River | KETL |
  | 1200000005 | Grand Coulee | Columbia River (border) | LARL |

  Before this change the ids came from `row_number() OVER ()`, so they could swap between runs; harmless while the rows were dropped, not once they are barriers.
- **bcfishpass does the same as link's `bcfishpass` bundle** (`smnorris/bcfishpass@f8db4b9` local clone): `load_dams.sql` inserts the placeholders with `passability_status_code` NULL, and `load_crossings.sql` builds dam crossings from `bcfishpass.dams_vw` inner-joined to `cabd.dams` on `cabd_id`, which holds no placeholder. So they never reach crossings there either. Its comment ("create placeholders on BC streams … and add those to bcfishpass.dams") suggests they were meant to count; owed: a draft note, not posted.
- **Under `default` after this change**, prep gives the three LARL placeholders, KETL's and SKGT's `passability_status_code` 1; under `bcfishpass`, NULL as before.
- **Segments that may take `DAM`** (from `fresh_default`, built 2026-10-17): mapping codes whose second token is `NONE` in the three groups that hold placeholders: KETL RB 6,743 and WCT 5,430; LARL BT 1,131, RB 1,097, WCT 1,055; SKGT BT and RB 2,070 each. `NONE` means no anthropogenic barrier downstream; which of these the placeholders reach is Phase 3's measurement. Upstream of the Columbia border placeholder, BT codes with no anthropogenic token are rare outside LARL (KOTL 76, BULL 26, KHOR 17, KOTR 15, UARL 12 segments), because Keenleyside, Brilliant and the other BC dams come first.
- **#345:** a current `cabd.dams` (2,592 rows, load 2026-10-17) gives ADMS 7 dams. The bcfishpass reference DB's `bcfishpass.dams` holds the same 7 ids for ADMS, so the eighth left CABD upstream; neither database still holds it, so it cannot be named. The golden test now pins the 7 ids.

## After the plan review: the missing bcfp step and the repeat-build evidence (2026-10-22)

- **bcfp keeps one modelled crossing per PSCIS per blue line** (`02_pscis_streams_150m.sql`, the `nearest` UPDATE after the close-enough reset); link skipped it. Ported as Step 3b.
- **Repeat builds of the pick** (`.lnk_pipeline_pscis_build()` for ADMS, which builds the candidate table province-wide; 17,377 PSCIS picked), main from a frozen worktree against the branch, each twice, minutes apart:

  | comparison | different modelled crossing | different stream / measure |
  |---|---|---|
  | main vs main | 464 | 0 |
  | branch vs branch | 0 | 0 |
  | main vs branch | 656 | 56 |

  So main's pick was not reproducible within one session over unchanged inputs, and the branch is. The 56 stream changes come from Step 3b: a non-nearest modelled match no longer gets the 0.9 distance weighting, as in bcfp.
- **Census after the change:** no PSCIS has a top-ranked tie whose rows differ in any column the pick passes on. Non-null rows: 15,019, distinct keys 14,995; the 24 extra rows are exact duplicates from the `fwa_rivers_poly` LEFT JOIN (several polygons per `waterbody_key`), which bcfp's query has too.
- **Source keys:** `fresh.modelled_stream_crossings` 524,578 rows and ids; `whse_fish.pscis_assessment_svw` 19,905 rows and ids.
- **Snap timing** with `linear_feature_id` added after the KNN distance: 1.6-1.8 s for the province-wide snap and build, main and branch alike.
- **Placeholder ids in CSV order:** 1200000001 Kettle (KETL), 1200000002 Columbia at the border (LARL), 1200000003 Big Sheep, 1200000004 Little Sheep (LARL), 1200000005 Ross (SKGT). The Phase 2 table above lists the position-ordered ids, now replaced.

## Phase 3: verification on real groups (2026-10-23)

Record: `data-raw/logs/provincial_prep_367/` (README there).
- **Reproducible:** ADMS and ELKR built twice at the branch are identical in every persisted table, barriers included.
- **The placeholders as barriers** (LARL, KETL, SKGT, recomputed): segments and habitat identical; per-species access and `has_barriers_<sp>_dnstr` identical (0 segments differ); the five placeholder rows are the only barrier difference; 19,065 mapping codes change, all `NONE` to `DAM` in the second token: KETL RB 6,778 and WCT 5,358; LARL BT 1,000, RB 1,038, WCT 978; SKGT BT 1,931, RB 1,982.
- **Main against branch** (ADMS, ELKR, NATR): accessible km identical; at most 0.094 km of spawning or rearing per species moves (ADMS CH spawning +0.088, rearing -0.009; ELKR GR +0.027; NATR GR rearing +0.094), from 1-2 extra segments per group.
- **Harness defect, not a code one:** a race on `CREATE SCHEMA IF NOT EXISTS` between the two lanes failed the first LARL build. Rebuilt; recomputes re-run in order.

## Enumeration: every ordering construct in `R/` (code-check, after round 2, 2026-10-23)

Round 2 found a defect inside a fix (falls ids ordered on position alone, while a falls point in a segment overlap joins two segments), so the loop ends on an enumeration. Mechanism: **an ordering that names a row's position but not its identity, after a join that can repeat a position.** Candidate set: every `row_number()`, `DISTINCT ON` and `ORDER BY ... LIMIT` in `R/` (`grep -nE "row_number\(\)|DISTINCT ON|LIMIT [0-9%]" R/*.R`, 58 hits). Existence probes (`SELECT 1 ... LIMIT 1`, `LIMIT 0`, the skip-scan in `utils.R`) shape no output and are left out; the rest:

| where | ends on | unique? |
|---|---|---|
| `lnk_barriers_unify.R` gradient ids | blk, measure, label | yes: no repeated position province-wide (`fresh_default`, 241 groups) |
| `lnk_barriers_unify.R` falls ids | blk, measure, joined `linear_feature_id` | yes (fixed round 2; USIK's repeat differs in `linear_feature_id`; the other 2 repeats are identical rows) |
| `lnk_barriers_unify.R` user-definite ids | blk, measure, joined `linear_feature_id` | yes (same join shape as falls) |
| `lnk_barriers_unify.R` subsurface ids | blk, measure | yes: no join, no repeated position |
| `lnk_pipeline_prepare.R:776`, `lnk_pipeline_break.R:238` `id_segment` | blk, measure | yes: one segment per position within a group |
| `.lnk_dams_matched_sql()` inner snap / outer `DISTINCT ON (dam_id)` | distance, `linear_feature_id` / dam_id, distance, `linear_feature_id` | yes (fixed) |
| `.lnk_dams_usa_sql()` ids | `csv_row` | yes |
| `lnk_points_snap()` KNN | distance, `linear_feature_id` | yes (fixed) |
| `lnk_pipeline_pscis_build.R` B-side retain | modelled id, distance, `stream_crossing_id` | rows still tied share the retained PSCIS, so the UPDATE is the same |
| Step 3b `nearest` | PSCIS, blk, instream distance, modelled id, `linear_feature_id` | yes up to the rivers-polygon copies, which are identical rows |
| Step 4 pick | `.lnk_pscis_pick_order` | no output-changing tie left (census) |
| Step 4c DBSCAN dedup | ..., `stream_crossing_id` | yes (fixed) |
| Step 4d blk/measure dedup | ..., `stream_crossing_id` | yes |
| Step 5 xref branches | PSCIS, `branch_rank` | one row per branch per PSCIS: the xref CSV is one row per PSCIS |
| `lnk_discharge.R` fill laterals | measure, `linear_feature_id` | yes |
| `lnk_habitat_validate.R:885`, `:1286` snap laterals | exact-start first, then measure DESC | yes within a blue line and group |
| `lnk_match.R` 1:1 dedup | id, distance | **no**: ties at equal distance fell to row order. Not on the pipeline path (no caller in `R/` or `data-raw/`); fixed anyway: ends on the other side's id |
| `lnk_log.R:682`, `lnk_scenario_export.R:273`, `lnk_habitat_validate.R:470` latest log row | group, `date_start` DESC (export adds `run_id`) | log rows of one group differ in `date_start` by construction |

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `duplicate key value violates unique constraint "pg_namespace_nspname_index"` from two concurrent `CREATE SCHEMA IF NOT EXISTS` | Harness race between lanes; rebuild the group, and recompute in order once every group exists |
