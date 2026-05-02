## Outcome

Added `falls` as a segmentation break source — closed the implementation drift from `R/lnk_pipeline_break.R`'s docstring (lines 10-13) which already documented bcfp's break order as `observations → gradient_minimal → falls → barriers_definite → habitat_endpoints → crossings`, but the `source_tables` list and `break_order` default both omitted falls. Result: the FWA stream network was never broken at fall positions, so close-paired falls produced segments that spanned the second fall and incorrectly classified its upper portion as accessible.

Fix: one entry in `source_tables`, one in the default `break_order`, and `"falls"` added to both bundle configs (`bcfishpass`, `default`). Falls are NOT minimal-reduced — each fall is its own barrier.

HORS BLK 356357296 evidence case verified: pre-fix segment 12671 (1447 m straddling fall #2 at DRM 67565) split into 12677 (17 m below) + 12678 (1429 m above, `accessible=FALSE`). HARR BLK 356361157 (7 falls in 13 km) — all 7 fall positions now have segment breaks. 4-WSG regression (HARR/HORS/LFRA/BABL) showed small expected reductions (BT ~0.6–1.5 km on HARR/HORS; ~0.4 km × 7 species on LFRA; 0.94–1.59 km × 4 species on BABL); all deltas negative — fix correctly removes segments above falls.

Closed by: PR #99 → link v0.23.0 (commit `5fdd378`). Tests in `tests/testthat/test-lnk_pipeline_break.R` (33 PASS, was 29). Research doc `research/bcfishpass_comparison.md` § "falls in break_order (#96)" carries the evidence trace + regression table.
