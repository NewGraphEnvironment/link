# Progress — link `frs_order_child` wire-up

## Session 2026-05-01

### What landed (fresh)

- **fresh 0.27.1** — validator allows `channel_width_min_bypass` predicate (PR #194 merged)
- **fresh 0.27.2** — false-start patch (removed `stream_order_max` reference based on misread); superseded by 0.27.3
- **fresh 0.27.3** — `frs_order_child` derives `stream_order_max` per BLK via CTE (PR #196 merged)
- **fresh 0.27.4** — validator allows `distance_max` key inside `channel_width_min_bypass` block (PR #197 merged)

### What's staged on link `96-frs-order-child-wire` branch (uncommitted)

- 3 new columns in `dimensions.csv` (both bundles): `rear_stream_order_bypass`, `rear_stream_order_parent_min`, `rear_stream_order_distance_max`
- `lnk_rules_build` emits all three into `channel_width_min_bypass:` block in rules.yaml
- `lnk_pipeline_classify` reads the block, calls `fresh::frs_order_child` per species
- Bundle defaults: `bypass=yes, parent=5, dmax=300` for BT/CH/CO/ST/WCT in both bundles
- New tests in `test-lnk_rules_build.R` for the new columns

### Calibration runs (HORS BT, m4 + local fwapg)

- `data-raw/logs/20260501_15_preflight_hors_post_272.txt` — 0.27.2 broken predicate, +23.9%
- `data-raw/logs/20260501_17_preflight_hors_post_273.txt` — 0.27.3 with `stream_order_max`, +13.9%
- `data-raw/logs/20260501_18_preflight_hors_explicit_child.txt` — child=1 explicit (default-equivalent), +13.9%
- `data-raw/logs/20260501_19_preflight_hors_dmax_300.txt` — dmax=300 added, **−0.5%**
- `data-raw/logs/20260501_20_preflight_hors_child35_dmax300.txt` — child=3..5 exploratory, returns to −7.7% baseline

### Maps (HTML snapshots in `data-raw/maps/`)

- `HORS_BT_rearing_BEFORE_158.html` — pre-fix baseline
- `HORS_BT_rearing_AFTER_158.html` — broken predicate state
- `HORS_BT_rearing_AFTER_273.html` — `stream_order_max` only
- `HORS_BT_rearing_AFTER_274_dmax300.html` — calibrated (dmax=300)
- `HORS_BT_rearing_AFTER_274_child35_dmax300.html` — child=3..5 exploration

`_lnk_map_compare.R` was updated to split layers into `rearing_link_only` / `rearing_bcfp_only` / `rearing_both` toggle-able layers (plus `spawning_link` / `spawning_bcfp`).

### What we relitigated this session that we shouldn't have

The fresh#158 issue body already documented:
- `stream_order_max` is for direct-child semantics
- `distance_max` is a parametric flex with whole-segment overshoot trade-off
- Post-cluster placement is intentional
- bcfp parity is NOT the goal — link's default bundle should tune from BABL inspection

I rediscovered each of these as if they were new findings. fresh#156 (closed in favor of #158) explicitly rejected the "rule-grammar predicate at classify time" approach with the same analysis we re-did. **Lesson saved to memory** — check originating issue bodies first.

### Parked

Methodology decision pending. Don't merge link `96-frs-order-child-wire`. Don't run 15-WSG. Re-pick when there's bandwidth to either:
- Inspect the calibration on a wider WSG sample (BABL or LFRA next, per fresh#158)
- Decide to ship `bypass=no` defaults and keep the infrastructure parametric

### Next session quick-start

1. Read this file
2. Read `findings.md`
3. Read fresh#158 issue body (canonical design)
4. Decide: ship default-on (BABL inspection first) or default-off (commit infra without enabling)
