# Findings — lnk_pipeline_crossings: missing PSCIS↔modelled 100m-instream auto-snap layer (#154)

## Issue context

## Problem

`lnk_pipeline_crossings` v0.32.0 carries the PSCIS<->modelled crossing linkage **only from the xref CSV** (`pscis_modelledcrossings_streams_xref`). It's missing bcfp's automatic 100m-instream snap layer that produces the bulk of PSCIS<->modelled linkages.

See `research/bcfp_table_map.md` for the full mechanism analysis. Short version: bcfp's `02_pscis_streams_150m.sql` (at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`, current tunnel state `bcfishpass.log.model_run_id=121` rebuilt 2026-05-05) auto-matches each PSCIS to its nearest modelled crossing within 100m instream distance on the same stream. The xref CSV layers manual overrides on top. link skips the auto-snap entirely.

## Evidence (Phase A bcfp parity, 2026-05-10)

| WSG | extra `<schema>.barriers_anthropogenic` vs tunnel | mapping_code parity (worst species) |
|---|---|---|
| ADMS | +89 | bt 98.53% (211 diffs) |
| BULK | +1391 | bt 76.30% (9357 diffs) |
| WILL | +N (unmeasured) | bt 85.48% (2490 diffs) |
| PARS | cross-WSG dnstr (#152) | bt 56.16% (16445 diffs) |

The +1391 in BULK is the largest single contributor to BULK's mapping_code drift. Closing this gap is expected to bring all WSGs' mapping_code parity into >=99% (modulo cross-WSG dnstr, handled by #152).

## Dependencies

Blocked by **fresh#206** -- the generic `frs_point_match` primitive (point-to-point match on FWA network within instream distance). Once that ships, this issue is a thin integration.

## Proposed solution

Once fresh ships `frs_point_match`:

1. Add `<schema>.pscis` build step in `lnk_pipeline_crossings`, mirroring bcfp's `bcfishpass.pscis`:
   - Source: `<schema>.pscis_assessment_snapped` (already produced by `lnk_points_snap`)
   - Call `fresh::frs_point_match` with `table_a = <schema>.pscis_assessment_snapped`, `table_b = fresh.modelled_stream_crossings`, `table_to = <schema>.pscis`, `distance_max = 100`, `table_a_id_col = "stream_crossing_id"`, `table_b_id_col = "modelled_crossing_id"`
   - Result: PSCIS rows with `modelled_crossing_id` populated where auto-snap found a match
   - Apply xref-CSV overrides on top (xref overrides auto-snap matches)
2. `.lnk_crossings_union` reads from `<schema>.pscis` for the PSCIS branch (instead of `<schema>.pscis_assessment_snapped`).
3. The modelled-branch exclusion changes: drop the xref-based `WHERE NOT IN (xref)` and replace with `WHERE NOT IN (SELECT modelled_crossing_id FROM <schema>.pscis WHERE modelled_crossing_id IS NOT NULL)` -- picks up both auto-snap and xref-derived linkages from the same source.

## Acceptance

- [ ] `<schema>.pscis.modelled_crossing_id` populated where bcfp's `bcfishpass.pscis.modelled_crossing_id` is, for ADMS / BULK / WILL / PARS (within tolerance)
- [ ] `<schema>.crossings` modelled-source row count matches `bcfishpass.crossings` for ADMS / BULK / WILL / PARS (within tolerance)
- [ ] `compare_bcfp_mapping_code.R --wsgs=ADMS,BULK,WILL,PARS` mapping_code parity >=99% for all species except PARS BT (cross-WSG, separately handled by #152)
- [ ] Roxygen + lintr clean

## Out of scope

- Cross-WSG `dam_dnstr_ind` -- #152
- `lnk_pipeline_species` / `lnk_presence` alignment -- #153
- Extending PSCIS to all 4 BCDC views (currently only `pscis_assessment_svw` -- bcfp uses all 4) -- separate question


## Plan-mode exploration (2026-05-11)

### lnk_pipeline_crossings flow (current state)

5 steps in `R/lnk_pipeline_crossings.R` lines 78-120:
1. `lnk_inputs_verify` — required source tables present
2. `lnk_points_snap` (LIMIT 1, single nearest) → `<schema>.pscis_assessment_snapped`
3. `.lnk_crossings_union` — UNION ALL PSCIS + CABD + modelled
4. `.lnk_crossings_apply_overrides` — apply user_pscis_barrier_status + user_modelled_crossing_fixes
5. `lnk_barriers_emit` — emit `crossings_lookup` + 4 `barriers_*` tables

Step 2 is what we replace with the bcfp-shape snap-pick-match chain.

### `.lnk_crossings_union` PSCIS branch contract

Reads from `<schema>.pscis_assessment_snapped`: `stream_crossing_id, current_barrier_result_code, current_pscis_status, linear_feature_id, snapped_blue_line_key, downstream_route_measure, wscode_ltree, localcode_ltree, geom_snapped`. After link#154, reads from `<schema>.pscis` which provides the same superset.

### Modelled-branch xref-exclusion (currently)

```sql
WHERE m.modelled_crossing_id NOT IN
  (SELECT modelled_crossing_id FROM <schema>.pscis_modelledcrossings_streams_xref)
```

Changes to:

```sql
WHERE m.modelled_crossing_id NOT IN
  (SELECT modelled_crossing_id FROM <schema>.pscis
   WHERE modelled_crossing_id IS NOT NULL)
```

The combined snap+xref linkage drives the exclusion from a single source.

### bcfp SQL fragments (extracted verbatim for verbatim embedding in link)

**name_score CASE** (02_pscis_streams_150m.sql lines 101-105):

```sql
CASE
  WHEN replace(UPPER(a.stream_name), ' CR.', ' CREEK') = UPPER(str.gnis_name) THEN 100
  WHEN UPPER(a.stream_name) like '%TRIB%' and UPPER(a.stream_name) like '%'||UPPER(e.name_trimmed)||'%' and UPPER(a.stream_name) != UPPER(str.gnis_name) and distance_to_stream > 15 THEN -100
  ELSE 0
END AS name_score
```

**width_order_score CASE** (02_pscis_streams_150m.sql lines 115-142): 13 WHEN branches over stream_order × downstream_channel_width × distance_to_stream; full text in `research/bcfp_table_map.md` and the bcfp source at `model/01_access/pscis/sql/02_pscis_streams_150m.sql`.

**weighted_distance computation** (04_pscis.sql lines 180-184):

```sql
CASE
  WHEN modelled_xing_dist_instream IS NOT NULL
  THEN distance_to_stream - (distance_to_stream * 0.1)
  ELSE distance_to_stream
END AS weighted_distance
```

**pscis_streams_150m output schema** (the table link must build):

`stream_crossing_id, linear_feature_id, blue_line_key, downstream_route_measure, distance_to_stream, gnis_name, stream_name, name_score, stream_order, downstream_channel_width, width_order_score, crossing_type_code, modelled_crossing_type, modelled_crossing_id, modelled_xing_dist, modelled_xing_dist_instream, waterbody_key, multiple_match_ind`

### fresh primitives wired

- `frs_point_snap(num_features = 5, tolerance = 150)` — multi-stream candidates (one row per (PSCIS, stream) pair)
- `frs_candidates_pick(exp_filter, order_by)` — per-PSCIS pick. exp_score = NULL because scores are pre-computed in Step 2.
- `frs_point_match` is NOT used here — `modelled_xing_dist_instream` is computed inline in Step 2 because the score-based pick uses it in `weighted_distance`. Pulling it out into a separate frs_point_match call would happen AFTER the stream pick, which is the wrong order for byte-identical match.

### DESCRIPTION pin

Currently `Remotes: NewGraphEnvironment/fresh` (no version). Need `Remotes: NewGraphEnvironment/fresh@v0.31.0` + `Suggests: fresh (>= 0.31.0)` for `frs_candidates_pick` availability.

### compare_bcfp_mapping_code.R impact

Tunnel-side per-species barrier staging block (lines ~122-147) STAYS — link#152 (unified barriers) is independent and still needs bcfp tunnel staging for the per-species barriers until that issue lands.
