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

### Phase 3: Full ADMS access bug
- [x] Run full ADMS — confirmed ~93% undercount across all species
- [ ] **Hypothesis 2 (BARRIER crossings)**: Change label_map for BARRIER from "blocked" to non-blocking, rerun
  - Sub-basin had 0 BARRIER crossings (why it worked). Full ADMS has 39.
  - bcfishpass natural access = gradient + falls only. Crossing barrier_status does NOT block natural access.
  - This is the simpler fix — test first.
- [ ] **Hypothesis 1 (DEM noise barriers)**: Analyze gradient barrier distribution
  - fresh#118 set min_length=0. Single noisy DEM vertices at >15% create spurious barriers.
  - Count single-vertex vs sustained barriers. Compare against bcfishpass barrier counts.
- [ ] Rerun full ADMS with fix(es), validate within 5%
- **Status:** blocked on hypothesis testing

### Phase 4: bcfishobs observations
- [x] Sync bcfishobs fork with smnorris upstream (NGE fork on `main` branch)
- [ ] Run DB migrations (v0.2.0 through v0.3.2) — needs pgcrypto extension
- [ ] Run load_supporting_data.sh (species_cd + wdic_waterbodies)
- [ ] Run process.sh (pulls parquet from NRS, snaps to FWA, builds bcfishobs.observations)
- [ ] Verify bcfishobs.observations table has ADMS data
- [ ] Determine how observations affect access in compare_adms.R
  - bcfishpass uses observations to upgrade access (unknown -> known accessible)
  - fresh#69: observation-based break validation design
- **Status:** bcfishobs fork synced, DB setup in progress

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
