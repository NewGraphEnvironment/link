# Findings — Research: calibrate CH and BT gradient and channel-width thresholds from observations (#284)

## Issue context

**If we do it:** CH and BT habitat in the `default_tuned` bundle rests on measured fish distributions and cited literature, with a recorded verdict per threshold. **If we never do:** both species keep inherited bcfishpass cutoffs, and the size difference that separates them (big-river CH spawning vs small-stream BT) is represented only by `spawn_channel_width_min` 4 vs 2.

## Problem

Current values (fresh `parameters_habitat_thresholds.csv`; link `default/parameters_fresh.csv`):

| | spawn gradient max | spawn cw min | rear gradient max | rear cw min | MAD | access gradient max |
|---|---|---|---|---|---|---|
| CH | 0.0449 | 4 | 0.0549 | 1.5 | spawn ≥ 0.46, rear 0.28–100 (**unused**: no WSG uses the `mad` method and streams carry no `mad_m3s` — fresh#114) | 0.15 |
| BT | 0.0549 | 2 | 0.1049 | 1.5 | — | 0.25 |

Rearing-to-spawning connection is identical for both (`cluster_rearing = TRUE`, direction `both`, `cluster_bridge_gradient 0.05`, `cluster_bridge_distance 10000`). For BT the 5 % bridge is shorter than its 10.49 % rearing cutoff, so steep rearing only survives with spawning upstream of it. Whether that is right is untested.

Channel width is mostly modelled: on the local `fresh.streams`, 1.38 M segments modelled, 98.5 k field-measured, 90 k river polygons and 2.19 M NULL. NULL fails every width test, and order-1 streams are NULL (fresh#28), which likely removes BT headwater rearing wholesale.

## Proposed Solution

1. **Empirical distributions.** For CH and BT, join `bcfishobs.observations` (after `observation_exclusions`; release records removed) to segments. Plot gradient and channel width at observation points by life stage where known, by region, against the current cutoffs. Use measured channel width where it exists, and report modelled vs measured separately.
2. **Site-level evidence.** Add per-site measured width/gradient, effort, absences and fish size from FISS data submissions (individual-fish sheets) as an input table, to separate adult (spawning) from juvenile (rearing) evidence, especially for BT, where the provincial layer has no life stage.
3. **Literature.** One cited value or range per threshold, including CH stream-type vs ocean-type and BT life-history forms.
4. **Candidates.** Set values in the `default_tuned` bundle (per-bundle thresholds, #282) for spawn/rear gradient max, channel width min, `spawn_gradient_min` (see the reverted 0.0025 floor in `research/default_vs_bcfishpass.md`), and BT `cluster_bridge_gradient`.
5. **Score.** Run `default` and `default_tuned` on pilot WSGs with both species present and good sampling (e.g. UNTH, LNTH, BULK, MORR — confirm against `wsg_species_presence`), then compare with the observation validation (#283).
6. **Verdict** in `research/habitat_thresholds.md`, revised in place per species.

Out of scope here: MAD (fresh#114), temperature/GSDD (#21), channel-class segmentation (#52).

Relates to #20, #282, #283

## Errors Encountered

| Error | Resolution |
|-------|------------|
