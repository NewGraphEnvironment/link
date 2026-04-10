# Task Plan: ADMS End-to-End Habitat Connectivity (#16)

## Goal
Validate link + fresh pipeline against bcfishpass v0.5.0 reference for ADMS (BT, CH, CO, SK).

## Phases

### Phase 1: Consolidate function surface (#17)
- [x] 12 functions -> 8
- [x] 121 tests pass
- **Status:** complete

### Phase 2: Sub-basin comparison
- [x] Write compare_adms.R with sub-basin iteration (5s cycles)
- [x] fresh#96: frs_habitat accepts any AOI
- [x] fresh#98: gate + label_block
- [x] fresh#100: edge_type filtering
- [x] fresh#101: breaks_gradient
- [x] fresh#102: expose params on frs_habitat
- [x] fresh#107: frs_cluster (rearing connectivity)
- [x] fresh#113: rules YAML format
- [x] fresh#116: per-rule threshold overrides
- [x] fresh#118: min_length filter fix
- [x] bcfishpass-matching rules YAML + params_fresh override
- [x] Sub-basin: CH spawn exact, CO spawn exact, all within 5%
- **Status:** complete

### Phase 3: Full ADMS comparison
- [x] Run full ADMS — confirmed ~93% undercount across all species
- [x] **BARRIER label fix**: Changed label_map from "blocked" to "barrier" — fixed ~93% undercount
- [x] **River polygon rearing**: Added waterbody_type=R rule — fixed CH/CO rearing (-65% → -21%)
- [x] **Double clustering**: Removed external frs_cluster call (fresh 0.12.3 does it internally)
- [x] **CSV-driven YAML**: Rewrote both builders to read from dimensions CSV (#22)
- [ ] Remaining gap: -13 to -23% (channel width data, cluster connectivity)
- [ ] fresh#120: SK spawning lake proximity (explains +127%)
- **Status:** BT within 13%, CH/CO within 23%. Remaining gaps are data/config, not bugs.

### Phase 4: bcfishobs observations
- [x] Sync bcfishobs fork with smnorris upstream (NGE fork on `main` branch)
- [x] Run DB migrations (v0.2.0 through v0.3.2) — pgcrypto + whse_fish schema created
- [ ] Install bcdata in uv venv (blocked on rtj#66 — portable Python env plan)
- [ ] `bcdata bc2pg -e -c 1 whse_fish.fiss_fish_obsrvtn_pnt_sp` (empty table for schema)
- [ ] Run load_supporting_data.sh (species_cd + wdic_waterbodies)
- [ ] Run process.sh (pulls parquet from NRS, snaps to FWA, builds bcfishobs.observations)
- [ ] Verify bcfishobs.observations table has ADMS data
- [ ] Determine how observations affect access in compare_adms.R
  - bcfishpass uses observations to upgrade access (unknown -> known accessible)
  - fresh#69: observation-based break validation design
- **Status:** DB migrations done, blocked on bcdata install (rtj#66)

### Phase 5: SK spawning + lake proximity
- [ ] fresh#120: SK spawning requires connected rearing lake >= 200 ha within 3km
- [ ] Test on full ADMS (has lakes >= 200 ha, sub-basin doesn't)
- **Status:** blocked on Phase 3 + fresh#120

### Phase 6: Tests and cleanup
- [ ] Consolidated tests for lnk_match, lnk_override, lnk_score
- [ ] Code-check, PR to main
- [ ] Close link#16, link#17
- **Status:** pending

## Sub-basin test target
wscode: `100.190442.999098.995997.058910.432966`
- 711 fresh segments, 293 bcfishpass segments
- 74 crossings, 0 falls, 0 BARRIER crossings
- 5-10 second iteration cycles

## Key findings
- Sub-basin: CH/CO spawning EXACT match. All metrics within 2%.
- Full ADMS: access gating blocks ~96% of segments (should be ~67%)
- Two hypotheses to investigate (see findings.md)
- bcfishobs upstream has moved to parquet-based loading (NRS object storage)
