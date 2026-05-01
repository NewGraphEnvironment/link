# Progress — Falls not used as segmentation break source (#96)

## Session 2026-05-01

- Created branch `96-falls-break-order` off `origin/main` (post-link v0.22.0 ship)
- Archived wire-up PWF (fresh#158 work) to `planning/archive/2026-05-fresh158-frs-order-child-wire/`
- Scaffolded PWF baseline from issue #96 body
- Phase 1 applied: `falls` added to `source_tables` + `break_order` default in `R/lnk_pipeline_break.R`; both bundle configs (`bcfishpass`, `default`) opt in. Doc comment + `## Break sources` table reflect the new ordering (`observations → gradient_minimal → falls → barriers_definite → ...`).
- Phase 3 HORS verified: BLK 356357296 segment 12671 (1447m, was rearing=t) split at DRM 67565 into 12677 (17m below fall #2) + 12678 (1429m above fall #2, `accessible=FALSE`). Total `rearing_stream` unchanged on HORS (affected segment is edge_type 1250 = Horsefly River construction line, excluded from `rearing_stream` metric). Total `rearing` (broader bucket including 1250) dropped 1.43 km.
- Phase 3 HARR verified: BLK 356361157 (7 falls between DRMs 16634-29797) — all 7 fall positions now have segment breaks. Rollup diff vs pre-#96 baseline: BT `rearing` -0.63 km, BT `rearing_stream` -0.64 km. Other species/metrics unchanged.
- Map cache helper `_lnk_map_compare.R` hardened — stale 0-row caches (from cross-WSG pipeline overwrites) now refetch instead of erroring on missing CRS.
- Next: Phase 2 (test for new break source), Phase 4 (4-WSG regression vs baseline), Phase 5 (research doc + commit + PR).
