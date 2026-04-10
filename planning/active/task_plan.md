# Task Plan: ADMS End-to-End Habitat Connectivity

## Goal
Validate link + fresh pipeline against bcfishpass v0.5.0 reference.

## Current Phase
Phase 3 — sub-basin validated, full WSG has access gating bug

## Phases

### Phase 1: Consolidate function surface (#17)
- [x] 12 functions → 8
- [x] 121 tests pass
- **Status:** complete

### Phase 2: Sub-basin comparison (#16)
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
- **Status:** complete — sub-basin validates core pipeline

### Phase 3: Full WSG comparison
- [x] Run full ADMS
- [ ] **BUG**: Access gating too aggressive at full scale (1,288 vs 5,262 BT accessible)
- [ ] Investigate: hypothesis 1 — min_length=0 generating DEM noise barriers
- [ ] Investigate: hypothesis 2 — BARRIER crossings (39) blocking access when they shouldn't
- [ ] Fix and rerun
- **Status:** blocked on access bug investigation

### Phase 4: SK spawning + lake proximity
- [ ] fresh#120: SK spawning requires connected rearing lake
- [ ] Test on full ADMS (has lakes ≥ 200 ha)
- **Status:** blocked on Phase 3

### Phase 5: Tests and cleanup
- [ ] Consolidated tests for lnk_match, lnk_override, lnk_score
- [ ] Code-check, PR to main
- **Status:** pending

## Sub-basin test target
wscode: `100.190442.999098.995997.058910.432966`
- 711 fresh segments (with all gradient breaks), 293 bcfishpass segments
- 74 crossings, 0 falls
- 5-10 second iteration cycles

## Key findings
- Sub-basin: CH/CO spawning EXACT match. All metrics within 2%.
- Full ADMS: access gating blocks ~96% of segments (should be ~67%)
- Two hypotheses to investigate (see findings.md)
