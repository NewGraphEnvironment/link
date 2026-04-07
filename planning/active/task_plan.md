# Task Plan: ADMS End-to-End Habitat Connectivity

## Goal
Run link + fresh pipeline for ADMS, compare per-crossing upstream habitat km against bcfishpass reference. Validate the pipeline produces correct results.

## Current Phase
Phase 2

## Phases

### Phase 1: Consolidate function surface (#17)
- [x] 12 functions → 8 (lnk_load, lnk_override, lnk_match, lnk_thresholds, lnk_score, lnk_source, lnk_aggregate, lnk_db_conn)
- [x] 121 tests pass, committed on adms-comparison branch
- **Status:** complete

### Phase 2: Write and run compare_adms.R (#16)
- [ ] Write `data-raw/compare_adms.R`
- [ ] Step 1: lnk_load + lnk_override — prepare ADMS crossings on local Docker DB
- [ ] Step 2: fresh::frs_habitat("ADMS") — segment + classify with bcfishpass params
- [ ] Step 3: lnk_aggregate — roll up habitat per crossing from fresh output
- [ ] Step 4: Query tunnel DB for bcfishpass reference
- [ ] Step 5: Compare on aggregated_crossings_id, report differences
- [ ] Document results in findings.md
- **Status:** pending

### Phase 3: Fix differences
- [ ] Investigate any crossings with >10% difference
- [ ] Fix parameter or logic issues
- [ ] Re-run until totals within 5%
- **Status:** pending

### Phase 4: Tests and cleanup
- [ ] Consolidated tests for lnk_match, lnk_override, lnk_score
- [ ] Code-check, PR to main
- **Status:** pending

## What we compare
| Column | bcfishpass ref (126 crossings) |
|--------|-------------------------------|
| bt_spawning_km | 2,227 km |
| bt_rearing_km | 3,792 km |
| co_spawning_km | 1,852 km |
| co_rearing_km | 2,105 km |

## Success criteria
- Correlation > 0.99 per crossing
- Total km within 5%
- Any >10% per-crossing difference investigated

## Critical facts
- bcfishpass breaks at ALL crossings (not just barriers)
- barrier_status affects access classification, not segmentation
- spawn_gradient_min = 0 to match bcfishpass
- ADMS species: BT and CO (model = "cw")
