# Progress — Unified <persist_schema>.barriers (#152)

## Session 2026-05-11

- Plan-mode exploration — phases approved by user.
- Created branch `152-unified-persist-schema-barriers` off main.
- Scaffolded PWF baseline from #152 with approved phases.
- Driving motivation: PARS BT 60.64% → ≥99% closure; Skeena regional run unblocked.
- Next: start Phase 1 — `cols_barriers` + persist DDL.

## Session 2026-05-11 (Phase 1)

- Added `cols_barriers` vector in `R/lnk_persist_init.R` (13 columns + PK on `(id_barrier, watershed_group_code)`).
- Extended `lnk_persist_init()`: CREATE TABLE + 5 indexes (GIN blocks_species, btree wsg/source/blk_drm, GIST geom).
- Test coverage in `test-lnk_persist_init.R` — asserts table DDL + each index emitted.
- 35 PASS / 0 FAIL on this test file. Lint clean for new lines (pre-existing indent warnings unchanged).
