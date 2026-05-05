# Task: Stream-crossing accessibility labels — bcfishpass parity layer (#124)

link can't reproduce bcfishpass's stream-crossing accessibility vocabulary. We need three additive surfaces (none replacing existing structure):

- crossings carry `barrier_status` ∈ {PASSABLE, POTENTIAL, BARRIER, UNKNOWN} from PSCIS field result + override CSV (mirror of `bcfishpass.crossings.barrier_status`)
- segments carry per-species `access_<sp>` ∈ {-9, 0, 1, 2} integer code + per-source downstream-barrier arrays (mirror of `bcfishpass.streams_access`)
- segments carry per-species `mapping_code_<sp>` semicolon-token compound `{ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED} [;INTERMITTENT]` (mirror of `bcfishpass.streams_mapping_code`)

link's existing `severity` (high/moderate/low) + 5-bucket `mapping_code` (INACCESSIBLE / SPAWN / SPAWN_NO_REAR / REAR / ACCESSIBLE) are preserved unchanged — they're a separate flexibility layer for project-specific metrics.

**Approach restructure (post-exploration)**: build abstract primitives, not bcfp-shaped tables. The bcfp shape becomes one orchestration layer over reusable primitives; future link-specific shapes are different orchestrations over the same primitives. Use existing `lnk_*` families (override / pipeline) and consolidate duplicate code rather than extending it.

## Phase 1: barrier_status — verify + document (DONE)

**Finding from exploration**: `<schema>.crossings.barrier_status` is already populated correctly by `lnk_pipeline_load` via `.lnk_pipeline_apply_fixes` + `.lnk_pipeline_apply_pscis`. ADMS parity test: 7/7 distribution buckets match bcfp tunnel; 2-row diff out of 3597 (likely bcfp build SHA drift in fresh's bundled CSV).

**Consolidation idea dropped**: the two apply helpers have genuinely different semantics (constant remapping `SET barrier_status='PASSABLE' WHERE structure IN ('NONE','OBS')` vs value-driven `SET barrier_status = override.user_barrier_status`). Forcing both through `lnk_override` would add complexity, not subtract. Memory-driven lesson: consolidate where there's real reuse, not where there's surface similarity.

- [x] Pre-flight verification: ADMS link CSV vs bcfp tunnel `barrier_status` distribution (7/7 buckets, 2-row drift).
- [x] Document in roxygen on `lnk_pipeline_load` that `barrier_status` is bcfp-parity (PSCIS field + CSV override), distinct from `severity` (link's culvert-geometry scoring). Both can coexist on the same crossings row.
- [x] Commit (Phase 1 done).

## Phase 2: `lnk_dnstr_*` primitive + `streams_access` orchestration (~2 days)

**Abstract primitive (the system layer)**: given any segments table + any barriers table, return per-segment array of barrier IDs that lie downstream. The PostGIS/wscode-ltree join logic is identical for every (source, species) combo — write it once.

**Orchestration (the parity layer)**: compose the primitive across bcfp's (source × species) combinations to produce `<schema>.streams_access` matching bcfp's shape.

- [ ] Investigate fresh's exports + link's existing pipeline phases for an existing dnstr-trace primitive. If fresh has it, use it. If link has a partial helper, extend rather than re-write.
- [ ] If neither: add `lnk_dnstr_barriers(conn, segments, barriers, ...)` — small SQL helper. Returns a tibble keyed on `id_segment` with a `barrier_ids` text[] column. No bcfp-specific knowledge.
- [ ] Add `lnk_pipeline_access(conn, aoi, cfg, loaded, schema)` — pipeline phase that runs after `lnk_pipeline_classify`. Composes `lnk_dnstr_barriers` across the bcfp source set:
  - per-source: `barriers_pscis_dnstr`, `barriers_anthropogenic_dnstr`, `barriers_dams_dnstr`, `barriers_dams_hydro_dnstr`, `crossings_dnstr`
  - per-species: `barriers_<sp>_dnstr` (driven by species barrier-filter rules already in the config)
  - per-species access codes: `access_<sp>` derived via CASE on (wsg_species_presence, dnstr-empty, observation_upstr-empty)
- [ ] Wire into `lnk_pipeline_persist` so `<schema>.streams_access` accumulates across WSGs alongside `streams_habitat_<sp>`.
- [ ] Verification: per-species `access_<sp>` distinct distribution on test WSG within parity tolerance of bcfp tunnel.
- [ ] `/code-check` + commit.

## Phase 3: `streams_mapping_code` derivation (~0.5–1 day)

**No new primitive needed** — mapping_code is a CASE over the columns `streams_access` (Phase 2) already exposes + the segment's spawning/rearing booleans + edge_type for the INTERMITTENT flag. Pure derivation.

- [ ] Add `lnk_pipeline_mapping_code(conn, aoi, cfg, loaded, schema)` — runs after `lnk_pipeline_access`. Per species, applies the bcfp CASE that combines `access_<sp>`, `spawning_<sp>`, `rearing_<sp>`, the dnstr-source arrays, and `feature_code` into a semicolon-token compound.
- [ ] Output: `<schema>.streams_mapping_code` with `id_segment` + `mapping_code_<sp>` for each species in `cfg$species`.
- [ ] Vocabulary documented in roxygen: `{ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED} [;INTERMITTENT]`.
- [ ] Verification: distinct value counts of `mapping_code_bt` on test WSG within parity tolerance of bcfp.
- [ ] `/code-check` + commit.

## Phase 4: `build_species_views.R` parity sibling view (~0.5 day)

- [ ] Add an optional flag to `build_species_views.R` shipping a sibling per species: `streams_<sp>_bcfp_vw` surfacing the bcfp-shape mapping_code. Existing `streams_<sp>_vw` (5-bucket categories) retained unchanged.
- [ ] Update QGIS symbology hints to cover both views.
- [ ] No changes to `streams_habitat_<sp>` (boolean accessible stays — input to mapping_code, not a replacement).

## Phase 5: parity validation + release (~1 day)

- [ ] On a test WSG (ADMS), run the full pipeline + the three new phases. Compare row-by-row against `bcfishpass.crossings.barrier_status`, `bcfishpass.streams_access`, `bcfishpass.streams_mapping_code` on the same WSG.
- [ ] Quantify departures (expected: small, methodology-driven). Stamped log under `data-raw/logs/<TS>_link124_parity_validation.txt`.
- [ ] `NEWS.md` 0.30.0 entry (additive new functions = minor bump per R-package conventions).
- [ ] `DESCRIPTION` 0.29.1 → 0.30.0.
- [ ] PR body: closes #124, parity numbers from Phase 5.

## Total revised effort: ~4 days (was 4.5–5.5)

Phase 1 collapsed to consolidation + verify (~0.5 day). The mapping_code phase is pure derivation (~0.5–1 day). The plan's heart now lives in Phase 2 — the abstract primitive — which gives us free downstream reuse for any future "what's-downstream-of-X" question.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
