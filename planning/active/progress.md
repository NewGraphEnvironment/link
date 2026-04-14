# Progress

## Session 2026-04-13 (continued)
- Tested per-model non-minimal on BABL, ELKR, ADMS — no effect on ST/WCT
- Tested label_block with crossings — -52% regression, confirmed crossings don't block in bcfishpass
- Read load_streams_access.sql: access uses ONLY natural barriers, NOT anthropogenic
- Found bcfishpass access_st bug: checks 'SK' instead of 'ST' (filed bcfishpass#9, link#33)
- Read load_habitat_linear_st.sql line by line
- Found stream order exception: tested, +3 points on ST rearing, not the main cause
- Found rearing waterbody filter OR vs AND — not verified as cause
- Found three-phase rearing pattern — not verified as cause
- Read all 8 load_habitat_linear_*.sql files for cross-species comparison
- **Key lesson: stop guessing from SQL differences, compare segments directly against tunnel**
- Commits: 88e5af4, 67b67b6, 7b5e888

## Session 2026-04-14
- Segment-level ST comparison: loaded bcfishpass_ref.st_babl + diff tables for QGIS
- Found 382/383 bcfishpass-only segments are inaccessible in our system
- Traced to falls at BLK 360886207 not overridden for ST
- Root cause: observation_species = "ST" should be "CH;CM;CO;PK;SK;ST"
- Fix: one CSV cell. ST spawning -22% → +3.8%, rearing -25% → +2.4%
- Also fixed WCT: added observation_threshold=1, species=WCT (not yet tested)
- **Key lesson: segment-level comparison finds root causes in minutes, guessing from SQL wastes hours**
- SK spawning: traced to wrong lake outlet ordering in frs_connected_spawning line 1385
  ORDER BY downstream_route_measure picks wrong BLK. bcfishpass uses wscode_ltree ordering.
  Proven: corrected query gives 24.41 km vs bcfishpass 24.38 km (+0.1%)
