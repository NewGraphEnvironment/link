# Findings — link `frs_order_child` wire-up

## Summary

`frs_order_child` is a link methodology primitive, not a bcfp parity replicator. The HORS BT pre-flight result (link 394 km / bcfp 396 km on `rearing_stream`, −0.5%) at `bypass=yes, parent=5, child=1, dmax=300` is numerical proximity by accident — bcfp's bypass operates inside 3 connectivity-aware rearing phases (Phase 1: rearing-on-spawn, Phase 2: cluster-DS-of-spawn, Phase 3: cluster-US-of-spawn-with-no->5%-grade-between), and does NOT use a `stream_order_max` filter. Our function runs post-cluster, post-classify, with `stream_order_max` for direct-child semantics and `distance_max` as a biology-tuning cap. Different design, different semantics.

## Biology hook (the why)

The FWA-derived `channel_width` estimate is unreliable on small (1st-order) streams because the MAP (mean annual precipitation) signal isn't carried cleanly on those reaches. When such a small stream plugs directly into a large river, fish *do* use the lower reach for rearing despite the low/missing CW estimate — flow, temperature, cool-water mixing at confluence, backwater habitat all support juvenile use. `frs_order_child` is the parametric primitive expressing this biology.

## Design decisions (verbatim from fresh#158, anchored here for next session)

- **`stream_order = stream_order_max` (per BLK)** — bypass only applies on the mouth-side reach of a BLK, where the BLK's order is at its maximum. Excludes order-1 headwater portions of multi-order BLKs (e.g., a named creek that grows to order 3 at its mouth). Documented as direct-child semantics. **bcfp does NOT use this filter** — our function is structurally tighter on multi-order BLKs by design.
- **`distance_max`** — caps the bypass to the lower N metres of each direct-trib BLK. Whole-segment overshoot is the documented default (Option A in fresh#158). Lets users tune "how far into the trib does the parent-river effect extend" — a biology question, not a parity question.
- **Post-cluster, post-classify placement** — intentional. fresh#158: *"can add segments that frs_cluster removed because they had no connected spawning. For some species this is correct (rear-only species), for others it might over-classify. Mitigation: the accessible guard limits over-reach to accessible network only; the parametric parent_order_min / child_order_min / distance_max lets users tune."* fresh#156 was closed in favor of this approach because the alternative (apply during classify) inflates rearing counts pre-cluster.

## HORS BT pre-flight progression (this session, 2026-05-01)

| Iteration | Predicate | link | bcfp | diff_pct |
|---|---|---|---|---|
| Pre-#158 (no bypass) | — | 366 | 396 | −7.68% |
| 0.27.2 (broken predicate, removed `stream_order_max`) | parent≥5, order=1, no `so_max` filter | 491 | 396 | +23.9% |
| 0.27.3 (`stream_order_max` via CTE) | + `s.stream_order = s.stream_order_max` | 451 | 396 | +13.9% |
| 0.27.4 + dmax=300 | + `downstream_route_measure ≤ 300` | 394 | 396 | −0.5% |

Map snapshots in `data-raw/maps/HORS_BT_rearing_AFTER_*.html`.

The `dmax=300` calibration is exploratory — the 4-iteration trail above shows that the apparent parity at 0.5% under is **not the result of methodology alignment** but a numerical balance: under-credit on long-trib reaches (we cap at 300m, bcfp credits the whole trib up to gradient/access limits) compensates for over-credit on cluster-disconnected segments (we run post-cluster without the bcfp Phase-3 `>5%-grade-between` gradient gate).

## Segment-level evidence

- **BLK 356322947, DRM 3000–4500 (HORS BT):** bcfp credits 5 segments (3223, 3341, 3440, 3542, 4054) as rearing — passes gradient ≤ 0.1049, no DS barriers, `stream_order_max=2` per bcfp's stored column. Our `frs_order_child` predicate excludes them all because `stream_order=1, stream_order_max=2` fails our `s.stream_order = s.stream_order_max` filter. Demonstrates structural divergence from bcfp on multi-order BLKs.
- **BLK 356353593 (Divan Creek), DRM 6009+:** bcfp credits DRM 6009 + 6095 (gradients 0.009 and 0.078, both under 0.1049). Drops DRM 7280 (gradient 0.1008 — under cap, channel_width 1.77 ≥ cw_min 1.5) because Phase 3 cluster trace is blocked by the >5%-grade segment at DRM 7112 between 7280 and downstream spawn. Demonstrates that bcfp's bypass is gated by cluster connectivity to spawn, which we don't replicate.

## What we are *not* doing

- **Not adding gradient ceiling to `frs_order_child`.** bcfp's bypass-eligible segments must pass `gradient ≤ rear_gradient_max`, but link's `frs_order_child` is meant to be additive on `accessible = TRUE` segments regardless of gradient. The `accessible` guard already filters access-blocked segments via the link pipeline's barrier-aware accessibility; gradient-driven exclusion would be a parity-driven addition that contradicts the function's "additive primitive" design.
- **Not adding cluster-aware filtering.** The post-cluster placement is intentional; mitigation is `parent_order_min` / `child_order_min/max` / `distance_max`. If callers want cluster-aware behaviour they can run `frs_order_child` *before* `frs_cluster` instead of after.
- **Not pursuing bcfp parity for this primitive.** fresh#158 was explicit: link's default-bundle should ship parametric defaults tuned from BABL inspection, not a bcfp clone.

## Links

- [fresh#158](https://github.com/NewGraphEnvironment/fresh/issues/158) — design doc (canonical)
- [fresh#156](https://github.com/NewGraphEnvironment/fresh/issues/156) — predecessor, closed in favor of #158
- [link#23](https://github.com/NewGraphEnvironment/link/issues/23) — CH spawning misread, closed not-a-bug
- [research/bcfishpass_comparison.md](../../research/bcfishpass_comparison.md) — pre-#158 68 km gap evidence
