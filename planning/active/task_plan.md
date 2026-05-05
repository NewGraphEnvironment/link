# Task: Stream-crossing accessibility labels — bcfishpass parity layer (#124)

link can't reproduce bcfishpass's stream-crossing accessibility vocabulary. We need to add three additive layers (none replacing existing structure) so that:

- crossings carry a `barrier_status` ∈ {PASSABLE, POTENTIAL, BARRIER, UNKNOWN} from PSCIS field result + override CSV (mirror of `bcfishpass.crossings.barrier_status`)
- segments carry a per-species `access_<sp>` ∈ {-9, 0, 1, 2} integer code + per-source downstream-barrier arrays (mirror of `bcfishpass.streams_access`)
- segments carry a per-species `mapping_code_<sp>` semicolon-token compound `{ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED} [;INTERMITTENT]` (mirror of `bcfishpass.streams_mapping_code`)

link's existing `severity` (high/moderate/low) + 5-bucket `mapping_code` (INACCESSIBLE / SPAWN / SPAWN_NO_REAR / REAR / ACCESSIBLE) are preserved unchanged — they're a separate flexibility layer for project-specific metrics.

## Phase 1: `barrier_status` passthrough on crossings (~1 day)

- [ ] Add `lnk_barrier_status(conn, crossings, pscis_overrides)` — returns a tibble with the link-side crossing primary key + `barrier_status` ∈ {PASSABLE, POTENTIAL, BARRIER, UNKNOWN}. CASE mirrors `bcfishpass/model/01_access/sql/load_crossings.sql:66-69`: user_barrier_status if set, else current_barrier_result_code.
- [ ] Wire into `lnk_pipeline_load` so the working schema's crossings table carries `barrier_status` from the start.
- [ ] Test against bcfp tunnel: identical (crossing_id, barrier_status) pairs for a sample WSG.
- [ ] Document distinction from `severity`: barrier_status is bcfp-parity (PSCIS field result + CSV override); severity is link's own scoring of culvert geometry. Both can coexist on the same crossings row.

## Phase 2: `streams_access` table per schema (~2 days)

- [ ] Add `lnk_pipeline_access(conn, aoi, cfg, loaded, schema)` — runs after `lnk_pipeline_classify` returns. Builds `<schema>.streams_access` with bcfp-mirror columns:
  - `id_segment` (link-side equivalent of bcfp's `segmented_stream_id`)
  - per-source dnstr arrays: `barriers_pscis_dnstr`, `barriers_anthropogenic_dnstr`, `barriers_dams_dnstr`, `barriers_dams_hydro_dnstr`, `crossings_dnstr`
  - per-species dnstr arrays: `barriers_bt_dnstr`, `barriers_ch_cm_co_pk_sk_dnstr`, `barriers_ct_dv_rb_dnstr`, `barriers_st_dnstr`, `barriers_wct_dnstr`
  - per-species access codes: `access_bt`, `access_ch`, … ∈ {-9, 0, 1, 2}
  - observation arrays: `observation_key_upstr`, `obsrvtn_species_codes_upstr`, `species_codes_dnstr`
  - indicators: `dam_dnstr_ind`, `dam_hydro_dnstr_ind`, `remediated_dnstr_ind`
- [ ] SQL implementation: array_agg over downstream barriers for each segment; CASE for access integer code per species. Mirror `model/01_access/sql/load_streams_access.sql`.
- [ ] Add to `lnk_pipeline_persist` so the table accumulates across WSGs alongside `streams_habitat_<sp>`.
- [ ] Test: row count + sample-row equality vs bcfp `streams_access` on one WSG.
- [ ] `/code-check` on staged diff.

## Phase 3: `streams_mapping_code` table per schema (~1 day)

- [ ] Add `lnk_pipeline_mapping_code(conn, aoi, cfg, loaded, schema)` — runs after `lnk_pipeline_access`. Per species, applies the bcfp CASE that combines `access_<sp>`, `spawning_<sp>`, `rearing_<sp>`, the dnstr-source arrays, and the segment's `feature_code` (intermittent flag) into a semicolon-token compound.
- [ ] Output: `<schema>.streams_mapping_code` with `id_segment` + `mapping_code_<sp>` for each species in `cfg$species`.
- [ ] Vocabulary documented in roxygen: `{ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED} [;INTERMITTENT]`.
- [ ] Test: distinct value counts of `mapping_code_bt` on one WSG match bcfp's distribution.
- [ ] `/code-check` on staged diff.

## Phase 4: `build_species_views.R` parity option (~0.5 day)

- [ ] Add an optional flag to `build_species_views.R` that ships a sibling view `streams_<sp>_bcfp_vw` per species, surfacing the bcfp-shaped mapping_code. Existing `streams_<sp>_vw` (5-bucket categories) retained.
- [ ] Update QGIS symbology hints in the script to cover both views.
- [ ] No changes to `streams_habitat_<sp>` (boolean accessible stays — it's an input to mapping_code, not a replacement).

## Phase 5: parity validation + release (~1 day)

- [ ] On a test WSG (ADMS), run the full pipeline + the three new phases. Compare row-by-row against `bcfishpass.crossings.barrier_status`, `bcfishpass.streams_access`, `bcfishpass.streams_mapping_code` on the same WSG.
- [ ] Quantify any departures (expected: small, from methodology differences already documented). Stamp results in `data-raw/logs/<TS>_link124_parity_validation.txt`.
- [ ] `NEWS.md` 0.30.0 entry — additive new functions, qualifies for minor under R-package conventions.
- [ ] `DESCRIPTION` 0.29.1 → 0.30.0.
- [ ] PR body: closes #124, includes parity numbers from Phase 5.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
