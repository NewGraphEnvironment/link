# Code-check round 3 (#367), branch 367-before-the-next-provincial-default-run-a vs 67a410e2

## Checklist read

- code-check.md: the prose of all fourteen H3s under `## Mechanisms` (`|` rows and evidence blocks skipped). Standalone / Security / Spreadsheet headings: 0 of 25 read beyond their index lines (no shape in this diff).
- code-check-r.md: "Postgres row order is never fixed unless the query fixes it" read in full. Index lines only for the other 110 (round 2 read the DB-type, `$` partial-match, `deparse`, yaml, `match()`, testthat-error and `skip_if_not` sections; nothing in them changed since).
- code-check-spatial.md: 0 of 92 read in full this round (round 2 read "FWA `upstream_route_measure` misses the next segment's start", which the finding below rests on).
- code-check-shell.md: no shell in the diff outside data-raw/logs; 0 of 67 read.

## Findings

- **[severity: fragile]** R/lnk_pipeline_prepare.R:428-435 (`.lnk_pipeline_prep_gradient`, unchanged on this branch). `UPDATE gradient_barriers_raw g SET wscode_ltree, localcode_ltree FROM fwa_stream_networks_sp s WHERE <measure in [drm, urm)>` is a pick from a multi-row match: a gradient point in the ~1 mm overlap of two FWA segments joins both, and Postgres documents that an `UPDATE ... FROM` with several join rows uses one of them, which one "not readily predictable". It is the same mechanism as round 2's falls finding (a join that repeats a position, then a choice that names no identity), in a construct the enumeration's grep (`row_number()|DISTINCT ON|LIMIT`) cannot see.
  - Measured on `fresh_default.barriers` (241 groups): 7,237,349 gradient positions, 3,513 matching two segments, **1,530 of them (183 groups) where the two segments' `localcode_ltree` differ** (`wscode_ltree` never differs). Today all 1,530 took the lower segment's localcode, so the plan has been stable; nothing guarantees it (a hash or parallel join plan reaches the rows in another order).
  - It changes output if it flips: on ADMS, BULK and ELKR, 26 such positions give a different `fwa_upstream()` answer for 42 tributary segments depending on which localcode the barrier carries (the tributary joining at that node is above the barrier under one localcode and not the other).
  - What reads it: `lnk_barriers_unify()`'s gradient source (persisted `barriers.localcode_ltree`, so the RUNBOOK §2b / NEWS 0.68.0 claim that builds from the same inputs give identical barriers rests on the plan), the per-model break sets (`.lnk_pipeline_prep_minimal`, `barriers_<model>`), and `lnk_barrier_overrides()`'s `fwa_upstream(b.…localcode…, o.…)` observation count, which decides lifts.
  - Fix that moves nothing today: pick the lower segment explicitly, e.g. `UPDATE … FROM (SELECT DISTINCT ON (g.ctid) g.ctid, s.wscode_ltree, s.localcode_ltree FROM … g JOIN … s ON <range> ORDER BY g.ctid, s.downstream_route_measure, s.linear_feature_id) x WHERE g.ctid = x.ctid`, and add the row to the enumeration.

## The enumeration: completeness

The candidate set was chosen by syntax (`row_number()`, `DISTINCT ON`, `ORDER BY … LIMIT`). The mechanism is semantic: **any statement that keeps one of several rows a join produced, without naming which.** Checked beyond the grep:

| construct | sites in `R/` | verdict |
|---|---|---|
| `UPDATE … FROM` with >1 matching row | prepare.R:429 (gradient ltrees) | **the finding above** |
| same | access.R:240 (`id_segment` key), discharge.R:344 (`.lnk_discharge_sql()` one row per `linear_feature_id`), load.R:155 / apply_overrides.R:71 (constant SET), pscis_build Step 3b (`nearest` one row per key), apply_overrides.R:60 / override.R:153 (per-id CSV rows) | one row per target, or the SET does not depend on the row |
| `string_agg` / `array_agg` / `percentile_cont` | habitat_validate_band.R:256 (`ORDER BY id_segment`), aggregate.R:184, score.R:239 | ordered or order-free |
| `ON CONFLICT DO NOTHING` | barrier_overrides.R:210, :251 (insert only key columns), log.R | set semantics |
| range joins that keep every match | classify.R:231-272, prepare.R:474-491, :640-647, barriers_unify falls / user-definite | both rows kept; no pick (falls/user-definite ids fixed in round 2) |
| DBSCAN cluster ids (Step 4c) | `ST_ClusterDBSCAN(geom, 5, 1)` | minpoints 1: every point is core, so membership is order-free; only the cid labels vary |
| R-side `[1]` on query results | pipeline_access.R:287-291 (`anth[1]`), :317 | first element of fresh's `frs_network_features` array: the fresh-side ordering already noted as out of scope |
| R-side `order()` / `duplicated()` / `[1]` elsewhere | habitat_validate.R:972-980 (`order(loc, observation_key)`), species_pooling.R:146, export / log helpers | outside the build's output or keyed on a unique id |

Each "unique? yes" verdict in the enumeration that I re-checked holds: falls / user-definite (blk, measure, `linear_feature_id`) after the range join; gradient (blk, measure, label) and subsurface (no join); `id_segment` (blk, measure unique in working streams); the dam snap and `lnk_points_snap()` (distance, `linear_feature_id`); `.lnk_dams_usa_sql()` (`csv_row`; the half-open rounded join cannot match a placeholder twice); Step 3b (matches bcfp `02_pscis_streams_150m.sql` `nearest`, which nulls `a.id != n.id`); Step 4d; Step 5 branches; `lnk_match()` (text ids, a total order).

Minor: the enumeration says the grep gives 58 hits; at HEAD the same command gives 68.

## Second mechanism: a new argument whose default is the old behaviour

| argument | callers in `R/` | pinned by |
|---|---|---|
| `.lnk_pipeline_prep_dams(cfg = NULL)` | prepare.R:130 passes `cfg` | spy test "lnk_pipeline_prepare passes cfg to prep_dams" |
| `.lnk_dams_usa_sql(barrier = FALSE)` | prepare.R:920 (`.lnk_cabd_additions_barriers(cfg)`), guard :345 (`additions`) | DB test "prep_dams makes the placeholders barriers under default only" (psc 1 only if prep_dams wires `barrier`); DB test "the guard sees the cabd_additions dams only when they are barriers" (`additions = TRUE` reaches the SQL) |
| `.lnk_dams_blocking_downstream(additions = FALSE)` | guard :487 | spy test "lnk_wsg_downstream_check passes the bundle's knob to the probe" (TRUE for default, FALSE for bcfishpass) |
| `.lnk_cabd_additions_rows(key = "cabd_additions")` | prepare.R:847 and guard :225 both pass `key` | default only adds `csv_row` to a non-additions frame, which nothing reads; a dropped call fails loud in prep (`a.csv_row` missing) |
| `frs_candidates_pick(order_by = .lnk_pscis_pick_order)` | pscis_build :308 | test-lnk_pipeline_pscis_build.R:67 |

Every data-raw caller of `lnk_wsg_downstream_check()` passes a `cfg` (required, class-checked). No unpinned caller.

## Verified, no issue

- Placeholder ids (1200000001-5) cannot collide with modelled ids (1e9 + max 24,764,034) or PSCIS ids.
- Docs (NEWS, RUNBOOK §2a/§2b/§8c, CLAUDE.md) state the guard consequence for schemas built before 0.68.0.
