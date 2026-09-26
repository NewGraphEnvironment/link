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

## Phase 1 — observation use vs availability (2026-09-26)

> **Superseded numbers.** This section records the first run. Code-check round 1 made every
> statistic accessible-only and fixed the NULL-width river-polygon label. The quantiles,
> counts and the bridge share below are therefore pre-fix. `research/habitat_thresholds.md`
> and the committed CSVs hold the current values. Kept as the record of what was seen before
> the post-hoc change.

Evidence: `data-raw/logs/habitat_thresholds_284/` (ledger, quantiles, selection, candidates).
Final use sets after dedup: CH 1,745 locations (232 spawn-staged, 507 rear-staged),
BT 2,560 (no stage), DV-in-BT-WSGs 2,822 (76 spawn, 1,002 rear).

- **B1 confirmed**, then handled: 4840/4870 BT and 3532/3550 CH obs in `fresh_default` sit
  within 1 m of a break. The upstream segment is chosen, and the 100 m FWA window gradient
  tracks it closely (CH_spawn P95 0.052 segment vs 0.049 window; BT_any 0.131 vs 0.144).
- **DV proxy rule as planned was empty**: presence marks DV in 140 of 158 BT WSGs, so
  "BT and not DV" kept nothing. Replaced (before looking at stage numbers) with "DV where
  the WSG has BT", matching the pipeline's `BT;DV`, capped at low confidence.
- **Decision-rule correction**: the "keep when the ratio just above the cutoff is ≥ 1"
  clause is inverted. A ratio ≥ 1 above a cutoff means fish select habitat the cutoff
  excludes, which argues for loosening. It fired only for BT spawn gradient (DV evidence,
  low confidence, so keep either way). The research doc records the corrected reading.
- CH spawning: selection falls below 1 at 2–3 %; 3–5 % is ~0.4–0.5; **0 of 232** spawn obs
  in (0.05, 0.055] over 2,140 km available. The P95 (0.052) interpolates across that gap, so
  the mechanical rule says 0.0549 while the bin it adds has no use.
- CH spawn width: 69 non-river-polygon spawn obs, P5 6.4 m; selection ≥ 1 from 6 m; 0 obs
  in 4–6 m (3,335 km available). River polygons (156 of 232 spawn obs) bypass width anyway.
- CH rear gradient P95 0.063; use thins but persists to ~10 %.
- BT_any gradient P95 0.131 (n 2,457); selection < 1 from 3 %, ~0.6 flat from 5 to 12 %,
  dropping to 0.37 at 12–15 %. DV rear evidence is ≥ 1 all the way to 12 %.
- BT width: selection ≥ 1 from 3 m; P5 1.85 m. DV spawn: ≥ 1 already at 1.5–2 m (n 6).
- `spawn_gradient_min`: CH spawn selection in [0, 0.0025] is **2.8** (41 % of spawn obs
  there), BT/DV 2.3. A floor would cut the most selected bin. Keep 0 — consistent with the
  reverted 0.0025 floor in `research/default_vs_bcfishpass.md` ("Follow-up: spawn gradient minimum design").
- BT bridge (G9): only 2.4 % of BT obs sit on segments that pass the rear predicate yet
  have `rearing = FALSE`. Keep 0.05.
- Width NULL (G3): 49 % of accessible BT stream length has NULL width, yet only 4.1 % of BT
  obs on those streams sit there (selection 0.08). *(Corrected in round 3; first written as
  45 % / 2.5 %.)* Under-sampling of order-1 headwaters and absence cannot be told
  apart here; FISS absences are the check.
- G7: 636 CH locations fall inside `user_habitat_classification` spawning reaches (242 of
  them spawn-staged). UHC was built partly from these observations, so the overlap is not
  independent evidence.
- Project dominance: largest single CH source is Nechako Fry Emergence (7.9 %); 10.4 % of
  CH locations have no `source_ref`. No BT project exceeds 3.5 %.

## Phase 2 — FISS site evidence (2026-09-26)

> The "±40–50 %" width error below was corrected in round 2 to a p10–p90 of 0.69–1.56 (about
> −30 % / +55 %).
> The committed `fiss_stamp.txt` records knowledge@14afc0d (a parallel session committed
> there mid-run); the `fiss_sites_*_all.csv` inputs are byte-identical to 20f0a5a, so no
> FISS number changed.

Evidence: `fiss_presence.csv`, `fiss_width_error.csv` (knowledge@20f0a5a; COTR, LNTH,
PINE, UNTH, UPCE; 9,679 sites, 362 with measured width).

- **B3 sidestepped**: `knowledge` already parses the FISS data-submission `.xls` (site,
  effort, catch, NFC). No bcdata or `fshclctn_id` join is needed.
- `average_gradient_percent` holds proportions (all ≤ 0.43). This is reported upstream in
  the draft, not corrected silently.
- BT present at measured sites (n 16): width P5 1.9 m, none < 1.5; gradient P95 0.106
  (n 15). Absences are smaller and steeper (median 1.46 m, 8 %).
- CH: no presence at a site with measured width. Snapped presence sites (n 20) sit on
  segments with median width 34.7 m, P5 5.4 m.
- **Modelled width error**: at 18 sites the modelled segment width is median 0.97 × measured,
  p10–p90 0.69–1.56. That is roughly ±40–50 %, the resolution any width cutoff has. The 81
  FIELD_MEASURMENT segments match at ratio 1.00 because fwapg derived them from these same
  sites (G11 — circular).
- Individual-fish (step 3) sheets are not parsed, so there is no fish length. Draft issue in
  `planning/active/draft_knowledge_issue.md`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| DV proxy "BT and not DV" kept 0 rows | Presence marks DV nearly everywhere BT is; use DV where BT present, low confidence |
| `sprintf('%d')` on a numeric from DBI count | `as.integer()` (DBI returns int64/numeric) |
| FISS `site_key` fan-out on join | Reports span groups; distinct per (site_key, wsg), keep closest snap |

## Code-check round 1 (2026-09-26) — two published candidates flipped

`review-round1.md`. The gradient P95s behind `candidates.csv` included observations on
`accessible = FALSE` segments, while the selection ratios and the floor rule used accessible
rows only. Made consistent (accessible everywhere):
- CH spawn P95 0.052 → 0.044, and CH rear 0.063 → 0.060. **Both now "keep"**, which
  withdraws the CH `rear_gradient_max` 0.0649 candidate set earlier in this session.
- BT rear P95 0.131 → 0.125, so the candidate goes from **0.1349 to 0.1249**.
- River polygons with NULL width fail the R rule's `BETWEEN 0 AND 9999`. There are 55 such
  obs, all with spawning and rearing FALSE, 31 in UPCE/TABR/LPCE. Correcting them drops the
  BT bridge loss share from 2.4 % to 1.2 % (still keep). This is noted in the research doc as
  a model behaviour worth an issue.
- Other fixes: availability is no longer rounded before binning; BT_any_dv is deduplicated
  across BT and DV; the obs query is ordered by `observation_key` (deterministic dedup);
  the stamp carries a dirty flag, the installed fresh and the fresh that built
  `fresh_default` (0.32.0 / 0.33.0, 4 logged runs); FISS width-error rows carry
  `independent`.
- Literature (Phase 3) arrived; `planning/active/literature.md` is the record.
- `parameters_fresh.csv`: evidence says keep both `spawn_gradient_min` and
  `cluster_bridge_gradient`, so `default_tuned` does **not** take its own copy. The gate
  decision allowed for one; an identical copy would only drift.
