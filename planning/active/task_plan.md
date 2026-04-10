# Task Plan: ADMS End-to-End Habitat Connectivity

## Goal
Validate link + fresh pipeline against bcfishpass reference using sub-basin
iteration for fast development cycles.

## Current Phase
Phase 3 — fixing differences

## Phases

### Phase 1: Consolidate function surface (#17)
- [x] 12 functions → 8
- [x] 121 tests pass, committed on adms-comparison branch
- **Status:** complete

### Phase 2: Write and run compare_adms.R (#16)
- [x] Write `data-raw/compare_adms.R` with sub-basin iteration (5s cycles)
- [x] fresh#96: frs_habitat accepts any AOI (merged)
- [x] Falls included as blocked break sources
- [x] Crossings break geometry only (gradient_0), don't block access
- [x] Document results in findings.md
- **Status:** complete — BT rearing within 3%, others need work

### Phase 3: Fix differences
- [x] BT rearing: -2.7% ✓ (validates core pipeline)
- [ ] BT spawning: +13.8% — segmentation boundary effects + spawn_gradient_min
- [ ] CO spawning: +37.8% — rearing not linked to spawning spatially
- [ ] CO rearing: +34.6% — same cause as CO spawning
- [ ] Fix "accessible" label blocking in fresh (frs_access_label_filter)
- [ ] Investigate rearing-downstream-of-spawning requirement
- **Status:** in progress

### Phase 4: Tests and cleanup
- [ ] Consolidated tests for lnk_match, lnk_override, lnk_score
- [ ] Code-check, PR to main
- **Status:** pending

## Sub-basin test target
wscode: `100.190442.999098.995997.058910.432966`
- 385 fresh segments, 293 bcfishpass segments
- 74 crossings, 0 falls in sub-basin
- 5 second iteration cycles

## Architecture (confirmed from bcfishpass source)
- bcfishpass gates habitat on **natural** access (gradient barriers + falls)
- Crossings are anthropogenic — break geometry but don't block access
- Species use different access arrays:
  - BT: `barriers_bt_dnstr` (25% gradient)
  - CO: `barriers_ch_cm_co_pk_sk_dnstr` (15% gradient)
- Rearing requires spatial connection to spawning (cluster analysis)
- ADMS uses model = "cw" (channel width, not MAD)

## Key issues for fresh
1. "accessible" label treated as blocking (frs_access_label_filter bug)
2. MAD not used in classification (matters for mad-model WSGs)
3. Rearing not spatially linked to spawning (inflates CO rearing)
