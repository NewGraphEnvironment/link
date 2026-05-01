# Task Plan — link 96-frs-order-child wire-up (parked)

Branch: `96-frs-order-child-wire` (local, not pushed)
Canonical design doc: [fresh#158](https://github.com/NewGraphEnvironment/fresh/issues/158) — read its issue body for the full decision record. Predecessor [fresh#156](https://github.com/NewGraphEnvironment/fresh/issues/156) closed in favor of #158. Spawning-side misread: [link#23](https://github.com/NewGraphEnvironment/link/issues/23) (closed not-a-bug 2026-04-28).

## Phase 1 — fresh ships (DONE)

- [x] fresh 0.27.1 — validator allows `channel_width_min_bypass` predicate (PR #194)
- [x] fresh 0.27.3 — `frs_order_child` derives `stream_order_max` per BLK via CTE (PR #196). 0.27.2 was a false-start patch superseded by 0.27.3.
- [x] fresh 0.27.4 — validator allows `distance_max` key inside the bypass block (PR #197)

## Phase 2 — link wiring (DONE, parked uncommitted)

- [x] `dimensions.csv`: 3 new columns (`rear_stream_order_bypass`, `rear_stream_order_parent_min`, `rear_stream_order_distance_max`) — both bundles
- [x] `lnk_rules_build`: emits all three into `channel_width_min_bypass:` block
- [x] `lnk_pipeline_classify`: reads block, calls `fresh::frs_order_child(parent_order_min, child_order_min/max, distance_max)`
- [x] Tests added in `test-lnk_rules_build.R` for the new columns

## Phase 3 — single-WSG calibration (DONE)

- [x] HORS BT preflight at `bypass=yes, parent=5, child=1, dmax=300`: link 394 km / bcfp 396 km on `rearing_stream`
- [x] Five iteration snapshots saved as HTML in `data-raw/maps/HORS_BT_rearing_AFTER_*.html`

## Phase 4 — parked

Methodology decision pending. fresh#158 design intent: link is **not** chasing bcfp parity for `frs_order_child` — it's a link primitive expressing the biology of *"small streams plugging into big rivers support rearing despite low estimated CW"*, with parametric flex (`stream_order_max`, `distance_max`). HORS calibration result is numerical proximity by accident; methodology is divergent from bcfp by design.

- [ ] Decide whether to ship as link methodology default or keep `rear_stream_order_bypass=no` until a wider sample (BABL inspection per fresh#158) informs the call
- [ ] If shipping default-on: 15-WSG `tar_make` to confirm calibration generalizes (or doesn't)
- [ ] If shipping default-off: keep the wire-up infrastructure but bundle CSVs ship `bypass=no`

## Notes for next session

- Don't re-derive `stream_order_max` / `distance_max` rationale — fresh#158 issue body has it
- Don't re-derive bcfp parity gap — bcfp's bypass also lacks `stream_order_max` filter, and runs *inside* its 3 connectivity-aware phases (rearing-on-spawning / DS-of-spawn cluster / US-of-spawn cluster). Our `frs_order_child` runs post-cluster, post-classify; it's an additive primitive, not a parity replicator. fresh#158 documents this trade-off.
- The `dmax=300` HORS calibration is exploratory, not a final value
