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
- Commits: 88e5af4, pending stream order commit
