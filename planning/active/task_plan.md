# Task: Falls not used as segmentation break source — implementation drift from documented break_order (#96)

`falls` is not used as a segmentation break source in the pipeline, so the FWA stream network is never broken at fall positions. When a fall sits between FWA-native segment boundaries and no other `break_order` source coincides with it, the resulting `fresh.streams` segment spans across the fall — its upper portion is incorrectly classified as accessible because the segment as a whole has no barrier between it and downstream.

`R/lnk_pipeline_break.R` lines 10–13 already document bcfp's break order as `observations → gradient_minimal → barriers_definite → falls → habitat_endpoints → crossings` (note `falls`). But the `source_tables` list (line ~107) omits `falls`, and the `break_order` default (line ~97) doesn't include it either. Implementation has drifted from the documented intent.

## Phase 1: Fix the implementation drift

- [ ] Add `falls = paste0(schema, ".falls")` to `source_tables` in `R/lnk_pipeline_break.R`
- [ ] Add `"falls"` to the `break_order` default vector in same file (between `gradient_minimal` and `barriers_definite` per the doc comment ordering)
- [ ] Add `"falls"` to `cfg$pipeline$break_order` in `inst/extdata/configs/bcfishpass/config.yaml`
- [ ] Add `"falls"` to `cfg$pipeline$break_order` in `inst/extdata/configs/default/config.yaml`
- [ ] Update the doc comment + `## Break sources` table in `R/lnk_pipeline_break.R` if needed (the comment lists falls but the table may omit the entry)

## Phase 2: Tests

- [ ] Add unit test in `tests/testthat/test-lnk_pipeline_break.R` (or extend existing) that confirms `frs_break_apply` is invoked with `<schema>.falls` when `falls` is in `break_order`
- [ ] Confirm `devtools::test()` clean (no new failures vs main)

## Phase 3: HORS verification (the issue's evidence case)

- [ ] Re-install link locally
- [ ] Run HORS preflight (`Rscript /tmp/preflight_hors.R`)
- [ ] Query `fresh.streams` on BLK 356357296 around DRMs 67000–68000 → confirm a new segment break at DRM 67565
- [ ] Query `fresh.streams_habitat` on the upper-fall segment → confirm `accessible = FALSE` (gets the natural-barrier treatment from `prep_natural`'s falls + `barrier_overrides`)
- [ ] Re-render HORS BT compare map (`bt_rearing_HORS.R`) — segment 12671's upper portion should leave the `link_only` rearing layer

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
