# Findings — Break streams only where a present species' access changes (both configs); bcfishpass config takes the order-1 exception (#326)

## Issue context

**If done:** both configs break streams only where a present species' access changes, which is how bcfishpass breaks them. Segment counts roughly halve, and BT habitat stops flipping on breaks that gate no fish present. The `bcfishpass` config also takes bcfishpass's order-1 rearing exception. **If never:** BT-only groups (no 15 / 20 % species present: PCEA, FINA, PARS) keep 71–85 km of two-way BT rearing disagreement under a 0.5–1.9 % net (#324), and every group carries 2–3× the segments it needs.

Step-by-step comparison and history: `research/bcfp_segmentation_parity.md`.

## Why the breaks differ

- bcfishpass (`smnorris/bcfishpass@620dbe4`, `model/01_access/01_model_access_natural.sh`) builds each model's barriers after its observation and habitat lifts, keeps the downstream-most per flow path, then breaks there. Models build only where their species are present.
- link (`.lnk_pipeline_prep_minimal()`) builds a set for every configured species whatever is present (#45), and since #223 breaks at every position. Before #223 it reduced, but before the lifts, so a lifted mainstem barrier pruned real tributary frontiers. #223 fixed that by dropping the reduction instead of moving it after the lifts.
- PCEA: link 106,079 segments vs bcfishpass 37,957; link holds all but 1 of bcfishpass's 24,393 breaks plus 68,118 extra.

## Scope

1. **Break where access changes, both configs.** Per species present in the WSG, reduce its post-lift barrier set (`barriers_<sp>_access`) to the downstream-most position per flow path, and break there. No config switch: it is the general rule, and `default` follows.
2. **Order-1 rearing exception in the `bcfishpass` config.** bcfishpass admits an order-1 line with parent order ≥ 5 whose known width is below the minimum (BT, CH, CO, ST, WCT; `load_habitat_linear_bt.sql:90-97`); NULL widths never qualify. Needs a width test in fresh's `frs_order_child()`; then set `rear_stream_order_bypass` in the bundle. PARS BT: −24.78 km. `default`'s position is a separate issue.
3. **Optional, lowest priority: strict `>` on the spawning size minimum in the `bcfishpass` config** (bcfishpass `channel_width > spawn_channel_width_min` and `mad_m3s > spawn_mad_min`; fresh tests `>=`). `default` keeps `>=` (`research/default_vs_bcfishpass.md` §6). BT 1.8–5.3 km per group, all at exactly 2.0 m. Needs a fresh option; drop it if it costs more than that.

## Not in scope (known divergences, annotated)

- `ct_dv_rb`: bcfishpass builds it only in a fixed list of 14 groups (CCIRA, LDEN / UDEN, COWN), outside the groups we model. link has no such model.
- The 1.8 km PCEA access residual (three segments at subsurface-flow or falls barriers).

## Before landing

- [ ] Confirm on FINA blk 359209845 that reducing the post-lift set keeps the frontier at 3,835 m (#223's case).
- [ ] Re-verify accessible-km parity, 11 WSGs × 8 species (`data-raw/parity_crosssection.R`).
- [ ] Measure BT habitat against bcfishpass with `data-raw/habitat_diff_segments.R` on PCEA / FINA / PARS / LKEL: segmentation churn and the width-exception km should go.
- [ ] State the run decisions before re-modelling: every persisted group re-segments, plus the post-consolidate recompute.
- [ ] Update the stale "matches bcfishpass" comment in `R/lnk_pipeline_prepare.R`, close #225 (the table is minimal again), and retire taxonomy `hors-class-stream-order-bypass`.

Relates to #324, #223, #45, #225.


## Errors Encountered

| Error | Resolution |
|-------|------------|
