# Progress — accessible_km segmentation-frontier fix (#223)

## Session 2026-07-03

- Root-caused the BT/ST `accessible_km` over-credit to `gradient_barriers_minimal`
  being fed the `frs_barriers_minimal()` downstream-most reduction as a segmentation
  source (`lnk_pipeline_prepare.R:592`). Verified `frs_barriers_minimal` is single-use,
  `gradient_barriers_minimal` is segmentation-only, and `barriers_<sp>_access` is built
  independently — so the fix is isolated.
- Filed **#223** with root-cause framing + embedded PNG (`research/blk359209845_bt_accessible_km.png`,
  committed `1a26f7d` on the 221 branch; raw URL pinned for the issue embed).
- Committed the research doc + 221 findings to the 221 branch (`4549713`), pushed 221.
- Created branch `223-access-segmentation-frontier` off `origin/main`; unset its
  main-tracking upstream (safety).
- User decisions: fix branch off main (own PR, closes #223); keep table name now +
  file a separate rename issue once confirmed.
- Scaffolded PWF baseline.
- Next: Phase 1 — write `data-raw/accessible_km_fix_validate.R` and confirm it fails pre-fix.
