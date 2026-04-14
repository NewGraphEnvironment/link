# Findings

## Non-minimal barrier removal
Single biggest factor in segment count. bcfishpass deletes barriers that have another barrier downstream (same model table). fwa_upstream self-join. 27,443 → 677 for ADMS. Without: +149% segments. With: -1.3%.

## Base segment filters
fresh loaded 1,062 extra segments missing `localcode_ltree IS NOT NULL`. Adding bcfishpass filters closed base segment count to exact match (10,458).

## Index performance
.frs_index_working not called on manually-built tables. Missing ltree gist indexes caused 30,000x slower access gating (nested seq scans). Classification: 228s → 6.6s on ADMS. Filed fresh#150.

## user_barriers_definite_control regression
Applying control table via LEFT JOIN in lnk_barrier_overrides caused -13% regression on ADMS. bcfishpass applies this at barrier table BUILD step (model_access_bt.sql), not during override computation. The control prevents barriers from being removed from per-model tables — it's a filter on which barriers enter the model, not on which overrides apply. Needs architectural rethink.

## Channel width data
Local Docker had 32,376 field measurements vs tunnel 75,736. Synced from tunnel via pg_dump. Tightened results by ~0.5% across species.

## SK spawning BULK regression  
ADMS +2.6% but BULK -39.9%. The two-phase algorithm (downstream trace + upstream lake proximity with ST_ClusterDBSCAN + st_dwithin to lake polygon) diverges with complex multi-lake geometry. Reopened fresh#147.

## Break source data alignment
All break positions pre-computed — no snapping during pipeline. Observations filtered by wsg_species_presence (592 → 179 unique positions, bcfishpass 178). Habitat endpoints use both DRM and URM (143 vs 145). observation_exclusions: 1 SK data_error in ADMS, no impact.

## CABD CSVs require external data
The 4 CABD CSVs (additions, blkey_xref, exclusions, passability_updates) groom `cabd.dams` and `cabd.waterfalls` tables. These come from the Canadian Aquatic Barriers Database loaded by bcfishpass. Our falls come from `fresh::falls.csv` (fwapg `fwa_localize`). Without CABD schema loaded, the CSVs are inoperable. Need to align falls data source or load CABD.

## Groom tables before pipeline, don't add switches inside engine
The user_barriers_definite_control regression taught: apply filters at the right level. bcfishpass uses the control table at barrier table BUILD (barriers_gradient.sql) and observation counting (model_access_*.sql), not during override computation. Applying it via LEFT JOIN in lnk_barrier_overrides was wrong level — caused -13% regression from 6 fewer overrides on major tributaries. Proper fix: lnk_habitat builds per-model barrier tables (grooming), then passes clean tables to fresh (engine).

## Pipeline performance hierarchy
1. Indexes on ltree columns — 35x speedup (228s → 6.6s classification)
2. WSG filter on breaks table — prevents cross-WSG bloat (61k → 27k)
3. Pre-computed downstream barrier index — not yet implemented, biggest remaining opportunity
4. UNLOGGED working tables — not yet tested, estimated 2-3x for bulk inserts
