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

## Session: 2026-04-10 to 2026-04-11

### Phase 3: Full ADMS comparison (major progress)
- BARRIER label fix: "blocked" → "barrier" (crossings don't block natural access)
- River polygon rearing: waterbody_type=R rule added (~150km CH/CO missing)
- Double clustering: removed external frs_cluster (fresh 0.12.3 does it internally)
- CSV-driven YAML: rewrote both builders to read from dimensions CSV (closes #22)
- Commit: 589df81

### Phase 4: bcfishobs (complete)
- Homebrew libpq installed (psql on PATH)
- MacPorts removed, Homebrew GDAL 3.12.3 with Parquet driver installed (rtj#65)
- bcfishobs setup.sh: removed fragile idempotency checks, fixed MultiPoint geometry
- Clean build: 372,420 observations (matches tunnel 372,418), 592 in ADMS
- Commit on bcfishobs nge-setup branch

### Issues updated with prompts
- fresh#69: observation-based access override with bcfishpass thresholds (BT>=1, CH/CO>=5, date/buffer filters)
- fresh#90: override CSVs moving to link with weekly sync from bcfishpass
- fresh#124: gradient_recompute parameter
- rtj#65: updated with Parquet blocker, GDAL consolidation plan

### Current comparison (fresh 0.12.3)
BT -8.6% rearing, CH -20.7%, CO -23.3%. Remaining gap: gradient_recompute + observations.

### Next
- fresh#124: gradient_recompute=FALSE should close spawning gap
- fresh#69: wire bcfishobs observations into access model
- fresh#120: SK lake proximity
- Phase 6: tests, cleanup, PR to main
