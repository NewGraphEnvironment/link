## Status update (2026-05-11)

The three mechanisms identified at the bottom of this doc as "Open work" have been addressed:

| Original gap | Resolution |
|---|---|
| PSCIS records with `modelled_crossing_id` set in BCDC but not in xref CSV → bcfp catches via unique constraint, link doesn't | **link#154** (queued) will wire `frs_point_snap(num_features = N)` + `fresh::frs_candidates_pick` + `fresh::frs_point_match` to reproduce the snap+pick+match chain byte-identically. Both fresh primitives shipped (v0.30.0 + v0.31.0). |
| `(blue_line_key, downstream_route_measure)` position collisions | Same as above — the 3-step composition in link#154 mirrors bcfp's unique-constraint-driven dedup via bidirectional dedup in `frs_point_match` + scored-candidate selection in `frs_candidates_pick`. |
| `user_modelled_crossing_fixes.structure` filter — bcfp excludes NONE/CBS, link only flips status | Will be handled in link#154 implementation alongside the rest of the snap rewrite. |

See `research/bcfp_compare_mapping_code.md` for the live Phase A numbers + 3-step composition recipe.

---

# bcfp ↔ link table relationship map

Built 2026-05-10 to reason about per-WSG mapping_code divergences from a
strong foundation rather than chasing SQL details. References bcfp's
`model/01_access/README.md`, `model/01_access/pscis/README.md`,
`model/01_access/modelled_stream_crossings/README.md`, and link's
pipeline source.

## Sources (raw inputs)

| Source | bcfp pulls via | link pulls via | Notes |
|---|---|---|---|
| 4× PSCIS BCDC views (assessment, design proposal, habitat confirmation, remediation) | `pscis.sh` loads all 4; UNIONs into `pscis_points_all` | `bcdata bc2pg` in `snapshot_bcfp.sh` loads all 4 into `whse_fish.pscis_*` — but only `pscis_assessment_svw` is consumed by `lnk_pipeline_crossings` |
| Modelled stream crossings (bchamp gpkg, generated from roads ∩ FWA) | Refreshed periodically into `bcfishpass.modelled_stream_crossings`; preserves stable `modelled_crossing_id` | `snapshot_bcfp.sh` curls + ogr2ogrs into `fresh.modelled_stream_crossings` |
| CABD dams (CABD public API, BC filter) | `load_dams.sql` from `cabd.dams` | `snapshot_bcfp.sh` ogr2ogrs into local `cabd.dams` |
| Observations (bchamp parquet) | `bcfishobs/process.sh` → `bcfishpass.observations` | `snapshot_bcfp.sh` ogr2ogrs into `bcfishobs.observations` |
| Falls | bcfp's `load_falls.sql` (custom curation) | Same data source, loaded via fresh primitives |
| User-curated CSVs | Lives in `bcfishpass/data/` | Bundled into link's config (`inst/extdata/configs/<bundle>/overrides/`) — synced via `data-raw/sync_bcfishpass_csvs.R` |

## User-curated override / xref CSVs (the "manual fix" layer)

bcfp + link share the same CSV inputs. These are mature data products
maintained by bcfp + redistributed by link.

| CSV | What it does | When applied |
|---|---|---|
| `pscis_modelledcrossings_streams_xref.csv` | Force-match PSCIS crossing → specific modelled_crossing_id (or specific linear_feature_id, or no match) | bcfp's `pscis.sh` step 3 (`04_pscis.sql` injects xref rows into output `bcfishpass.pscis` first); link's `lnk_crossings_union` excludes modelled crossings whose IDs appear in xref |
| `user_pscis_barrier_status.csv` | Override PSCIS `barrier_status` (e.g. assessor said PASSABLE but PSCIS data says BARRIER) | bcfp's `load_crossings.sql` CASE in PSCIS branch; link's `lnk_crossings_apply_overrides` UPDATE after union |
| `user_modelled_crossing_fixes.csv` | Mark modelled crossing as `OBS` (bridge), `NONE` (no crossing), or `CBS` (default culvert). 5 distinct values seen in BULK: `NONE` 275, `""` 135, `OBS` 111, `PASSABLE` 1, `CBS` 1 | bcfp's `load_crossings.sql` filter (excludes non-OBS structure fixes!) + CASE for barrier_status; link's `lnk_crossings_union` keeps all rows + `lnk_crossings_apply_overrides` flips `barrier_status='PASSABLE'` for NONE/OBS |
| `user_barriers_definite.csv` | User-added barriers not in other sources | bcfp's `barriers_user_definite.sql`; link's `lnk_pipeline_prepare` |
| `user_barriers_definite_control.csv` | Mark some user-definite barriers as non-overridable by observations | Same, gated per-species |
| `user_habitat_classification.csv` | Override habitat eligibility per segment range | fresh's habitat classify reads this |
| `wsg_species_presence.csv` | Which species "exist" per WSG (NULL/t for each) | bcfp reads at model selection time; link reads via `lnk_presence` (with salmon-group expansion) |
| `cabd_exclusions`, `cabd_blkey_xref`, `cabd_passability_status_updates`, `cabd_additions` | CABD dam edits (drop, snap, override passability, add US placeholder dams) | bcfp's `load_dams.sql`; link's `lnk_pipeline_prepare` mirrors line-for-line |

## bcfp's crossings build (the canonical reference)

bcfp builds `bcfishpass.crossings` via a SINGLE TABLE with multi-stage
`INSERT ... ON CONFLICT DO NOTHING`. The conflict mechanism is the dedup.

### Schema constraints on `bcfishpass.crossings`

```
PRIMARY KEY  (aggregated_crossings_id)        -- text PK
UNIQUE       (blue_line_key, downstream_route_measure)
UNIQUE       (modelled_crossing_id)
UNIQUE       (stream_crossing_id)
```

These constraints drive the dedup logic. INSERTs that would violate any
of them are silently dropped via `ON CONFLICT DO NOTHING`.

### Insert sequence (bcfp `load_crossings.sql`)

```
Step 1: PSCIS-on-modelled crossings
  - PSCIS rows where pscis.modelled_crossing_id IS NOT NULL
  - aggregated_crossings_id = stream_crossing_id (text)
  - modelled_crossing_id = pscis.modelled_crossing_id  ← claims that modelled_crossing_id
  - carries road tenure info from the modelled side
  - INSERT ... ON CONFLICT DO NOTHING

Step 2: Standalone PSCIS crossings
  - PSCIS rows where pscis.modelled_crossing_id IS NULL
  - aggregated_crossings_id = stream_crossing_id (text)
  - modelled_crossing_id = NULL
  - INSERT ... ON CONFLICT DO NOTHING

Step 3: CABD dams
  - aggregated_crossings_id = cabd_id (text)
  - INSERT ... ON CONFLICT DO NOTHING

Step 4: User-misc crossings
  - aggregated_crossings_id = user_crossing_misc_id + 1.2e9 (text)
  - INSERT ... ON CONFLICT DO NOTHING

Step 5: Modelled crossings (the rest)
  - aggregated_crossings_id = modelled_crossing_id + 1.0e9 (text)
  - WHERE (f.structure IS NULL OR f.structure = 'OBS')
    → excludes user_modelled_crossing_fixes structure='NONE','CBS','PASSABLE', etc.
  - INSERT ... ON CONFLICT DO NOTHING
    → any modelled_crossing_id already claimed by Step 1 silently dropped
    → any (blue_line_key, downstream_route_measure) already in table silently dropped
```

### Implicit dedup the unique constraints provide

Modelled crossings get silently dropped if:

1. **Linked via PSCIS** (`pscis.modelled_crossing_id` non-null) — Step 1 already claimed that `modelled_crossing_id`. The xref CSV is one source of this linkage; PSCIS data itself can also carry the linkage.
2. **Same network position as a PSCIS** (`(blue_line_key, drm)` collision) — Step 1 or 2 already inserted at that exact position.
3. **Filtered by user fix** (`f.structure` exists and isn't OBS) — Step 5 WHERE clause.

## link's crossings build

link reproduces the same logical output but with different mechanics:

### Schema (working `<schema>.crossings`)

Built by `.lnk_crossings_union` as a `CREATE TABLE AS SELECT ... UNION ALL ...`. **No unique constraints**; no `ON CONFLICT DO NOTHING`. Dedup must be explicit in the UNION SQL.

### Union branches

```
PSCIS branch:
  - Reads <schema>.pscis_assessment_snapped (from lnk_points_snap of pscis_assessment_svw)
  - aggregated_crossings_id = stream_crossing_id::text
  - INNER JOIN to fwa_stream_networks_sp on linear_feature_id (drops PSCIS not on FWA)

CABD branch:
  - Reads <schema>.dams (from lnk_pipeline_prepare's snap+filter of cabd.dams)
  - aggregated_crossings_id = dam_id::text
  - CASE on passability_status_code → barrier_status text
  - INNER JOIN to fwa_stream_networks_sp on linear_feature_id

Modelled branch:
  - Reads fresh.modelled_stream_crossings + LEFT JOIN xref + LEFT JOIN crossing_fixes
  - aggregated_crossings_id = (modelled_crossing_id::bigint + 1e9)::text
  - CASE on modelled_crossing_type → barrier_status (CBS→POTENTIAL, OBS→PASSABLE)
  - INNER JOIN to fwa_stream_networks_sp on linear_feature_id
  - WHERE modelled_crossing_id NOT IN (xref's modelled_crossing_id)
    → only filters modelled crossings explicitly listed in the xref

apply_overrides (post-union):
  - UPDATE barrier_status from user_pscis_barrier_status (PSCIS rows)
  - UPDATE barrier_status to PASSABLE for cross_fix.structure IN ('NONE','OBS')
```

### Differences from bcfp's dedup

| bcfp's mechanism | link's equivalent | Gap |
|---|---|---|
| `pscis.modelled_crossing_id` populated in source; Step 1 claims that modelled_crossing_id | xref CSV `pscis_modelledcrossings_streams_xref.modelled_crossing_id` → `NOT IN` exclusion | **link only sees xref-curated linkages**. If pscis source has `modelled_crossing_id` set in BCDC for a row not in xref, bcfp catches it via conflict; link doesn't exclude. |
| `(blue_line_key, drm)` unique constraint | None | **link doesn't dedup on position collision**. PSCIS at same (blk, drm) as a modelled crossing → link keeps both. |
| `WHERE f.structure IS NULL OR f.structure = 'OBS'` (excludes NONE/CBS/PASSABLE/other fixes) | `apply_overrides` flips status to PASSABLE for `structure IN ('NONE','OBS')` but keeps the row | **link keeps the row as PASSABLE**. For anthropogenic-barrier filter (`barrier_status IN ('BARRIER','POTENTIAL')`), PASSABLE rows are excluded anyway — but the row exists in `crossings`. CBS fixes are not in link's apply path; link keeps them as default POTENTIAL where bcfp would exclude them. |

## Hypotheses for BULK's +1336 modelled POTENTIAL

Given the table map, here's what could account for BULK's drift (in priority order):

1. **PSCIS records with `modelled_crossing_id` set in BCDC but not in xref CSV.** bcfp catches these via Step 1; link doesn't exclude them. If BULK PSCIS source has many such rows, link's modelled branch keeps the corresponding modelled crossings while bcfp drops them.

2. **`(blue_line_key, downstream_route_measure)` position collisions** between PSCIS and modelled crossings. bcfp's unique constraint silently drops the modelled; link keeps both.

3. **user_modelled_crossing_fixes structure='CBS'** rows. There's 1 in BULK fixes. bcfp excludes via WHERE; link keeps as POTENTIAL.

4. **Snap differences** — link's `lnk_points_snap` lateral KNN vs bcfp's stream-name-aware 150m snap. Could place PSCIS at a different `linear_feature_id`, causing different `(blue_line_key, drm)` than bcfp.

The cleanest test for hypothesis 1: count BULK PSCIS rows in `whse_fish.pscis_assessment_svw` that have a `modelled_crossing_id` set but aren't in the xref CSV.

## Open work surfaced by this map

- [ ] Verify hypothesis 1 for BULK (count PSCIS records with modelled_crossing_id outside xref).
- [ ] Verify hypothesis 2 (count PSCIS-modelled position collisions in BULK).
- [ ] Decide on dedup strategy for link: extend xref-based exclusion, OR add explicit `(blue_line_key, drm)` dedup in the union SQL, OR add a unique constraint to `<schema>.crossings` + use upsert. (Probably the last for parity with bcfp's mechanism.)
- [ ] Document why link only uses `pscis_assessment_svw` and not the other 3 PSCIS BCDC views (or extend to all 4).
- [ ] Document modelled_stream_crossings_fixes.csv treatment — does link's `user_modelled_crossing_fixes` correspond to bcfp's `modelled_stream_crossings_fixes.csv`? (They appear different — one drives barrier_status, the other drives modelled_crossing_type during the modelled crossings table build itself.)

## Column value coding — `fresh.streams_vw_bcfp` (parity predicate)

The tunnel-free bcfp reference view codes its per-species habitat/access columns as
**integers 0/1/2/3, NOT boolean 0/1**. When comparing link vs bcfp accessible /
spawning / rearing km, use the right predicate:

| bcfp column | presence predicate | notes |
|---|---|---|
| `access_<sp>` | `IN (1, 2)` | 1 = modelled, 2 = observed. Equivalent to `barriers_<group>_dnstr = ''` (empty string, char varying — NOT `text[]`). |
| `spawning_<sp>` | `IN (1, 2)` | a bare `= 1` UNDER-counts (drops 2/3); `> 0` OVER-counts (includes 3, a category link doesn't credit). |
| `rearing_<sp>` | `IN (1, 2)` | no `rearing_cm` / `rearing_pk` columns — chum & pink don't rear in freshwater. |

Salmon (CH/CM/CO/PK/SK) share one accessible barrier column
`barriers_ch_cm_co_pk_sk_dnstr`; BT = `barriers_bt_dnstr`, ST = `barriers_st_dnstr`,
WCT = `barriers_wct_dnstr`.

**Link side:** `streams_habitat_<sp>` uses BOOLEAN `spawning`/`rearing`;
`streams_access.access_<sp>` is the int. Sum `streams.length_metre` (length lives on
`streams`), joining streams+access+habitat on the full PK
`(id_segment, watershed_group_code)` (#203 — a bare `id_segment` join fans out
cartesian).

Getting this wrong (`= 1` instead of `IN (1,2)`) manufactured a false "+42% ST /
+24% CO spawning divergence" during #223 validation; real parity is exact. Canonical
harness: `data-raw/parity_crosssection.R`. Known parked departure: BULK SK
spawning/rearing (fresh#190 dual-rearing-lake topology). Species link doesn't model
but bcfp does (residence, #189): exclude, don't assert.
