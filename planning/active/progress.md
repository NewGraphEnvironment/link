# Progress Log

## Session: 2026-04-07

### Phase 1: Function consolidation
- **Status:** complete
- Actions:
  - Renamed lnk_break_source -> lnk_source
  - Renamed lnk_habitat_upstream -> lnk_aggregate
  - Renamed lnk_override_load -> lnk_load
  - Merged override validate+apply -> lnk_override
  - Merged 3 match functions -> lnk_match
  - Merged 2 score functions -> lnk_score
  - Filed issues #16 (ADMS comparison) and #17 (consolidation)
  - Filed fresh issues #92 (frs_feature_find) and #93 (frs_feature_index)
- Files: 42 changed, 121 tests pass

## Session: 2026-04-08 to 2026-04-09

### Phase 2: Sub-basin comparison
- **Status:** complete
- Actions:
  - Wrote compare_adms.R with sub-basin iteration (5s cycles)
  - Drove 10 fresh issues to resolution (#96, #98, #100, #101, #102, #107, #113, #116, #118)
  - Built bcfishpass-matching rules YAML (build_bcfishpass_rules_yaml.R)
  - Built NGE defaults rules YAML (build_habitat_rules_yaml.R)
  - Created parameters_habitat_dimensions.csv (13 species x 8 habitat dimensions)
  - Created parameters_fresh_bcfishpass.csv (spawn_gradient_min=0 override)
  - Sub-basin: CH/CO spawning EXACT match, all within 2%
- Commits: b50ee18 (consolidation), c05b08f (planning update)
- Key learning: bcfishpass only breaks streams at species access barriers (15/20/25/30%), not at 5/7/10/12%

### Phase 3: Full ADMS (started)
- Ran full ADMS — confirmed ~93% undercount across all species
- Documented two hypotheses for access gating bug
- Filed fresh#120 (SK spawning lake proximity)

## Session: 2026-04-10

### Phase 3: Access bug investigation (continued)
- Identified hypothesis 2 (BARRIER crossings) as most promising lead
  - Sub-basin had 0 BARRIER crossings, full ADMS has 39
  - bcfishpass natural access does NOT use crossing barrier_status
  - Fix: change label_map BARRIER from "blocked" to non-blocking

### Phase 4: bcfishobs (started)
- Synced bcfishobs fork with smnorris upstream (65 commits behind, clean fast-forward)
  - Upstream completely restructured: Makefile -> shell scripts, parquet from NRS object storage
  - Output table now `bcfishobs.observations` (was `fiss_fish_obsrvtn_events_vw`)
- Created local `main` branch tracking upstream/main
- DB migration in progress — needs pgcrypto extension on Docker fwapg
- Decision: use bcfishobs as-is (don't reimplement snapping in fresh)

### Next
- Complete bcfishobs DB setup (migrations + load_supporting_data.sh + process.sh)
- Test hypothesis 2 for access bug (BARRIER label change)
- Test hypothesis 1 if needed (DEM noise barriers)
- Rerun full ADMS with fix(es)
