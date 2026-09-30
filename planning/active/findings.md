# Findings — #284 step 5 (scoring)

## Issue context

**If we do it:** CH and BT habitat in the `default_tuned` bundle rests on measured fish distributions and cited literature, with a recorded verdict per threshold. **If we never do:** both species keep inherited bcfishpass cutoffs, and the size difference that separates them (big-river CH spawning vs small-stream BT) is represented only by `spawn_channel_width_min` 4 vs 2.

## Status (2026-09-26)

Steps 1–4 and 6 are done; the verdicts are in [`research/habitat_thresholds.md`](https://github.com/NewGraphEnvironment/link/blob/main/research/habitat_thresholds.md). **Step 5 (scoring) is unblocked once #290 merges (PR #291).** DV→BT pooling now comes from `default`'s `species_pooling.csv`, by region. Step 1 was re-run under the regional rule, and no #284 number moved: all 55 WSGs are in pooled regions, so only the province-wide ledger step 3 changes (DV 8,888 → 6,138). The #283 baseline also re-runs byte-identical. The step 5 plan below stands. Its pilot WSGs are all pooled under the Hazelton split (BULK and MORR are above Hazelton).

- **The Skeena is decided (2026-09-27): DV pools into BT only above Hazelton.** Skeena DV is a current name, not a legacy one. Under the split:
  - pooled BT rearing gradient P95 is 0.1309, n 3,988 (was 0.1348, n 4,764);
  - the rule still gives **0.1349**, but only 0.0009 above the line that would give 0.1249;
  - no verdict moves. Details: [`research/species_pooling.md`](https://github.com/NewGraphEnvironment/link/blob/290-region-scoped-dv-bt-observation-pooling/research/species_pooling.md).
  - **Step 5 must score both 0.1349 and 0.1249.**
  - The tracker's new `obs_year_max` (pool only pre-1995 interior records, scenario S4) would keep 0.1349 by 0.0010.

- **Step 5 plan (agreed 2026-09-26, run after #290):**
  - Prepare each WSG once, then re-classify it per variant, so every variant shares its segmentation. `default` is re-run in the same harness: the existing `fresh_default` BULK is pre-#223, with 42,860 segments against 87,639.
  - Seven variants: `default`, `default_tuned`, BT rear 0.1249 and 0.1449, CH spawn 0.0549 and 0.0299, and CH rear 0.0649.
  - WSGs: BT is read on ELKR and BULL (held out), with PARS, KOTL, BULK and MORR in-sample. CH is read on UNTH and LNTH (held out), with BULK and MORR in-sample.
  - Rule, fixed before the runs: the marginal band is habitat when its observation density per km is ≥ 0.5× the incumbent's. It is read on held-out WSGs and needs n ≥ 10, else keep. The literature veto stands.
  - Everything is species-agnostic: variants, WSG roles and absence taxa are data.

- **One value moves:** BT `rear_gradient_max` 0.1049 → 0.1349, in `default_tuned` (high confidence: BT and DV records pooled, n 4,764 accessible, P95 0.135; Isaak et al. 2015's 15 % natal envelope agrees). BT records alone give 0.1249, and both are recorded. Every other CH/BT gradient maximum and width minimum is kept, as are `spawn_gradient_min` (CH spawning selects the flattest bin, ratio 2.8) and the bridge (1.2 % of BT observations lost to clustering). So `default_tuned` still inherits `parameters_fresh.csv`.
- **Vetoed by the literature:** CH spawning width 6.6 m (Cooney & Holzer, Busch and Woll all put the minimum at 3.6–4 m).
- **Changed after the numbers were seen:** restricting use to accessible segments moved three verdicts (CH spawning 0.0549 → keep, CH rearing 0.0649 → keep, BT rearing 0.1349 → 0.1249, before pooling brought BT back to 0.1349). Scoring should test the retired CH values too.
- **Coverage is not interior-only:** about a third of the CH locations are in the lower Fraser and coastal Skeena, where ocean-type runs occur. The CH rearing verdict is sensitive to the gradient measure: the 100 m window gradient would give 0.0649 rather than keep.
- **BT and DV are pooled.** Inland, DV records are bull trout recorded under the other name; on the coast either occurs, and their habitat biology is treated as equivalent. BT has no life stage anywhere in bcfishobs, so the staged evidence is the DV records. With full confidence the rule would loosen BT spawning gradient (0.1949) and width (1.2 m); the literature vetoes both.
- **Step 2 route:** the FISS data-submission parse in `knowledge` (per-site width, gradient, effort, no-fish-captured) covers COTR, LNTH, PINE, UNTH and UPCE. Modelled width is good to about −30 % / +55 % of measured.

## Problem

Current values (fresh `parameters_habitat_thresholds.csv`; link `default/parameters_fresh.csv`):

| | spawn gradient max | spawn cw min | rear gradient max | rear cw min | MAD | access gradient max |
|---|---|---|---|---|---|---|
| CH | 0.0449 | 4 | 0.0549 | 1.5 | spawn ≥ 0.46, rear 0.28–100 (**unused**: no WSG uses the `mad` method and streams carry no `mad_m3s` — fresh#114) | 0.15 |
| BT | 0.0549 | 2 | 0.1049 | 1.5 | — | 0.25 |

Rearing-to-spawning connection is identical for both (`cluster_rearing = TRUE`, direction `both`, `cluster_bridge_gradient 0.05`, `cluster_bridge_distance 10000`). In fresh's `.frs_cluster_both()`, a rearing cluster is kept if spawning lies anywhere upstream of it, with no gradient test. Failing that, it is kept if a downstream trace reaches spawning within 10 km through reaches under the bridge gradient. So the 5 % bridge governs only rearing that sits above spawning. *(Corrected 2026-09-26: this previously said steep BT rearing "only survives with spawning upstream of it", which leaves out the downstream route.)*

Channel width is mostly modelled: on the local `fresh.streams`, 1.38 M segments modelled, 98.5 k field-measured, 90 k river polygons and 2.19 M NULL. NULL fails every width test, and order-1 streams are NULL (fresh#28), which likely removes BT headwater rearing wholesale. *(Measured 2026-09-26: 49 % of accessible BT stream length in `fresh_default` has NULL width, while 4 % of BT observations on those streams sit there, a selection ratio of 0.08. That does not separate under-sampling of headwaters from absence.)*

## Proposed Solution

1. **Empirical distributions.** For CH and BT, join `bcfishobs.observations` (after `observation_exclusions`; release records removed) to segments. Plot gradient and channel width at observation points by life stage where known, by region, against the current cutoffs. Use measured channel width where it exists, and report modelled vs measured separately.
2. **Site-level evidence.** Add per-site measured width/gradient, effort, absences and fish size from FISS data submissions as an input table, to separate adult (spawning) from juvenile (rearing) evidence, especially for BT, where the provincial layer has no life stage. *(Fish size is not parsed yet: the `knowledge` parse covers site, collection and habitat sheets, not individual fish.)*
3. **Literature.** One cited value or range per threshold, including CH stream-type vs ocean-type and BT life-history forms.
4. **Candidates.** Set values in the `default_tuned` bundle (per-bundle thresholds, #282) for spawn/rear gradient max, channel width min, `spawn_gradient_min` (see the reverted 0.0025 floor in `research/default_vs_bcfishpass.md`), and BT `cluster_bridge_gradient`.
5. **Score.** Run `default` and `default_tuned` on pilot WSGs with both species present and good sampling, then compare with the observation validation (#283).
6. **Verdict** in `research/habitat_thresholds.md`, revised in place per species.

Out of scope here: MAD (fresh#114), temperature/GSDD (#21), channel-class segmentation (#52).

Relates to #20, #282, #283







## Plan review and power check (2026-09-29)

`review-plan.md` holds every finding and what was done with it. The one that changed the
design: held-out observation locations per band window (FWA gradient, upper bounds,
`data-raw/logs/habitat_score_284/power_windows.txt`, now deterministic through
`bool_or` per location — the first `DISTINCT ON` draft moved staged CH counts by one
between runs):

| window | ELKR+BULL / UNTH+LNTH | widened BT set | 8 pilots | non-calibration |
|---|---|---|---|---|
| BT 0.1049–0.1249 | 10 | 43 | 66 | 95 |
| BT 0.1249–0.1349 | 1 | 33 | 15 | 45 |
| BT 0.1349–0.1449 | 0 | 22 | 17 | 35 |
| CH spawn 0.0299–0.0449 | 0 | | 2 | 35 |
| CH spawn 0.0449–0.0549 | 1 | | 1 | 19 |
| CH rear 0.0549–0.0649 | 2 | | 2 | 17 |

The reviewer's "best single held-out CH WSG holds 6" was close but not exact: the densest
WSGs hold 5 (OWIK), 2 (LISR) and 5 (CARR). OWIK + BELA + KITR would reach 11 for CH
spawning 0.0299–0.0449, so the doc says "three to six more WSGs per step" rather than
"no small set".

Operator decisions: BT only, with the widened held-out set; an underpowered step
leaves `default_tuned` as it is.

## Phase 1 refactor is byte-identical

`habitat_validate.R`, re-run with the absence taxa as data and the loaders sourced from
`habitat_validate_inputs.R`, with `knowledge` pinned at `508bf44` through `git archive`,
reproduces all six #283 CSVs byte for byte. The `knowledge` repo had moved (5 FISS site
files, about 11.8k lines), so an unpinned re-run would have differed for input reasons.
Removing the `BT,caught,Dolly Varden` row moves BT absences 1535 → 1539 (the data drives
the rule).

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `DISTINCT ON` probe gave staged CH counts differing by one between runs | aggregate per location with `bool_or`, as the validator dedups |
