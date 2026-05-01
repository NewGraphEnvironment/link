# Task: Falls not used as segmentation break source — implementation drift from documented break_order (#96)

`falls` is not used as a segmentation break source in the pipeline, so the FWA stream network is never broken at fall positions. When a fall sits between FWA-native segment boundaries and no other `break_order` source coincides with it, the resulting `fresh.streams` segment spans across the fall — its upper portion is incorrectly classified as accessible because the segment as a whole has no barrier between it and downstream.

`R/lnk_pipeline_break.R` lines 10–13 already document bcfp's break order as `observations → gradient_minimal → barriers_definite → falls → habitat_endpoints → crossings` (note `falls`). But the `source_tables` list (line ~107) omits `falls`, and the `break_order` default (line ~97) doesn't include it either. Implementation has drifted from the documented intent.

## Phase 1: Fix the implementation drift

- [x] Add `falls = paste0(schema, ".falls")` to `source_tables` in `R/lnk_pipeline_break.R`
- [x] Add `"falls"` to the `break_order` default vector in same file (between `gradient_minimal` and `barriers_definite` per the doc comment ordering)
- [x] Add `"falls"` to `cfg$pipeline$break_order` in `inst/extdata/configs/bcfishpass/config.yaml`
- [x] Add `"falls"` to `cfg$pipeline$break_order` in `inst/extdata/configs/default/config.yaml`
- [x] Update the doc comment + `## Break sources` table in `R/lnk_pipeline_break.R` (falls row added to the table; observations→gradient_minimal→falls→... ordering reflected in module docstring)

## Phase 2: Tests

- [ ] Add unit test in `tests/testthat/test-lnk_pipeline_break.R` (or extend existing) that confirms `frs_break_apply` is invoked with `<schema>.falls` when `falls` is in `break_order`
- [ ] Confirm `devtools::test()` clean (no new failures vs main)

## Phase 3: HORS verification (the issue's evidence case)

- [x] Re-install link locally
- [x] Run HORS preflight — log at `data-raw/logs/20260501_27_preflight_hors_falls_break.txt`. Total `rearing_stream` unchanged (366 km — affected segment is edge_type 1250, excluded from this metric); broader `rearing` total dropped 1.43 km
- [x] Query `fresh.streams` on BLK 356357296 — segment break landed at DRM 67565 (new segment 12678 starts there with `accessible=FALSE`, length 1429m); old segment 12671 (1447m straddling fall #2) is gone
- [x] Verify upper-fall segment `accessible = FALSE` — yes, 12678 + all upstream segments inaccessible
- [x] Re-render HORS BT map — saved at `data-raw/maps/HORS_BT_rearing_AFTER_falls_break.html`. Map cache helper hardened against stale 0-row caches in `_lnk_map_compare.R`

## Phase 4: 4-WSG regression

- [ ] Run the same 4-WSG regression script (`/tmp/regress_4wsg.R`) against HARR / HORS / LFRA / BABL
- [ ] Compare new rollups to pre-#96 baseline at `data-raw/logs/provincial_parity/`
- [ ] WSGs with close-paired falls SHOULD show diffs (that's the fix landing). WSGs without should be byte-identical
- [ ] Document expected vs unexpected diffs in `progress.md`

## Phase 5: Research doc + ship

- [ ] Update `research/bcfishpass_comparison.md` with a short note on the falls fix and its parity effect
- [ ] `/code-check` on staged diff
- [ ] Atomic commits with PWF checkbox flips
- [ ] PR with `Fixes #96`
- [ ] `/planning-archive` after merge → next session continues from clean active/

## Out of scope (per issue body)

- Per-species barrier overrides for falls (already handled in `prep_natural` for obs/habitat lift)
- Reduction of falls via `barriers_minimal` — falls should NOT be reduced; each fall is its own barrier
- Restoring 12671's link-only credit via `frs_order_child` — different mechanism, parked on the wire-up archive
