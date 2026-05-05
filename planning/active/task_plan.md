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

## Phase 2: `lnk_pipeline_access` (in flight, partial)

**Primitive lives in fresh, not link** — investigation found that `bcfishpass.load_dnstr` is the canonical SQL pattern, and the right home for it is fresh's `frs_network_*` family. Shipped as fresh#201 → `frs_network_features()` (v0.28.0). Direction-agnostic (`direction = c("downstream", "upstream")`), generic over any FWA-snapped point dataset. ADMS PSCIS parity: 1031 / 1031 byte-identical to bcfp's `streams_dnstr_barriers`.

**Orchestration in link**: `lnk_pipeline_access(conn, segments, aoi, ...)` composes `frs_network_features` calls across species + observations into a `streams_access` wide-table tibble + optional dest-table write.

- [x] Investigate existing primitives. → fresh#201 `frs_network_features` is the right tool.
- [x] Add `R/lnk_pipeline_access.R`. Returns a tibble keyed by segment_id with per-species `has_barriers_<sp>_dnstr` boolean + per-species `access_<sp>` integer code (-9 / 0 / 1 / 2). Optional `to` arg writes scalar columns via `dbWriteTable`.
- [x] Live test on bcfp tunnel ADMS BT: `access_bt` distribution **byte-identical to bcfp** when collapsing 1/2 (ours 10500 / 5262 vs ref 10500 / 5262 after collapsing observed-upstream into modelled-accessible).
- [x] Roxygen + lint clean.
- [x] fresh#204 SHIPPED as v0.29.0 (PR #205). Per-side wscode/localcode overrides + R list-column return.
- [x] `lnk_pipeline_access` updated to use the new ergonomics: drops substring-grepl in favor of `%in%`, drops redundant observation_key call, passes `features_wscode_col = "wscode"` for observations.
- [x] **ADMS BT byte-identical to bcfp** — `streams_access.access_bt` distribution `0/1/2 = 6728 / 3043 / 687`. Full 1/2 distinction now correct.
- [ ] Multi-species sweep across (BT, CH, CO, SK, ST, WCT, etc.) on ADMS.
- [ ] Wire into `lnk_pipeline_persist` so `streams_access` accumulates across WSGs alongside `streams_habitat_<sp>`.
- [ ] Verification: per-species `access_<sp>` distinct distribution on test WSGs byte-identical to bcfp.
- [ ] `/code-check` + commit.

## Phase 3: `streams_mapping_code` derivation (DONE — ADMS byte-identical)

Slightly more plumbing than the original "pure derivation" framing — needed to extend `lnk_pipeline_access` with a `barrier_sources = list()` arg so it emits `has_barriers_<source>_dnstr` booleans for the bcfp-shape sources (anthropogenic, pscis, dams) that the mapping_code SQL reads.

- [x] `lnk_pipeline_access` extended with `barrier_sources` arg + auto-NA propagation when a source table has zero rows in the AOI (mirrors bcfp's `barriers_<sp>_dnstr IS NULL` semantics for absent species like ST/WCT in ADMS).
- [x] Added `lnk_pipeline_mapping_code(access, habitat, feature_code, ...)` — pure derivation (no SQL). Resident vs anadromous flavors of `mapping_code_barrier`, per-species token1 with spawn-only species (CM/PK) handled, INTERMITTENT flag from `feature_code = "GA24850150"`.
- [x] Vocabulary documented in roxygen: `{ACCESS|SPAWN|REAR|""} ; {NONE|DAM|MODELLED|ASSESSED|REMEDIATED} [;INTERMITTENT]`.
- [x] **ADMS parity: 15762/15762 byte-identical for all 8 species** (BT, CH, CM, CO, PK, SK, ST, WCT).
- [ ] Caveat — uses bcfp's pre-computed `dam_dnstr_ind` + `remediated_dnstr_ind` for full BT/WCT parity. Computing those from primitives in link is a Phase 5 polish item — sequence-aware "next downstream barrier IS a dam" logic, not just presence.
- [ ] Wire as `<schema>.streams_mapping_code` write in `lnk_pipeline_persist`.
- [ ] `/code-check` + commit.

## Phase 4: `build_species_views.R` parity sibling view (DONE)

- [x] Added `--bcfp` flag to `build_species_views.R`. When passed AND `<schema>.streams_mapping_code` exists, also emits `streams_<sp>_bcfp_vw` per species. Existing `streams_<sp>_vw` (5-bucket categories) retained unchanged.
- [x] Updated QGIS symbology hints in the script's footer to cover both views.
- [x] `lnk_pipeline_mapping_code` gained a `to=` arg (with `conn=`) so callers can write `streams_mapping_code` for the view to consume.
- [x] No changes to `streams_habitat_<sp>` (boolean accessible stays — input to mapping_code, not a replacement).

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
