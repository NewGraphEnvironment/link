# Habitat thresholds — gradient, channel width and discharge

**Verified:** 2026-09-29 (CH/BT gradient and width), 2026-10-02 (MAD), 2026-10-03 (`cw` against `mad`), 2026-10-06 (discharge fill; `default`'s width-converted MAD ranges), 2026-10-07 (wetland floor on `rearing`; lake and wetland rearing connected to spawning) · **Issues:** #284 (gradient and width), #302 (MAD, [below](#mad-discharge-ranges-for-bt-gr-ko-and-rb-302)), #300 (`cw` against `mad`), #305 (discharge fill on main stems), #307 (`default`'s MAD ranges from its width minima), #311 (the wetland floor on `rearing`; fresh#237, fresh#240), #310 (lake and wetland rearing connected to spawning), #290 (the pooling tracker), #283 (the validator, [`habitat_validation.md`](habitat_validation.md)), #282 (`default_tuned`); spawned knowledge#28 (habitat weights) · **Produced by:** `data-raw/query_habitat_thresholds_obs.R`, `data-raw/query_habitat_thresholds_fiss.R` → `data-raw/logs/habitat_thresholds_284/`; step 5 by `data-raw/habitat_variants_build.R` and `data-raw/habitat_variants_score.R` → `data-raw/logs/habitat_score_284/`; literature reviews archived with #284's and #302's PWFs (`literature.md`); MAD by `data-raw/query_habitat_thresholds_mad.R` → `data-raw/logs/habitat_thresholds_302/` and the same scoring scripts → `data-raw/logs/habitat_score_302/`; `cw` against `mad` by the same scripts with `--base=default_tuned` → `data-raw/logs/habitat_score_300/`, and with the fill → `data-raw/logs/habitat_score_305/`; the fill measured by `data-raw/discharge_fill_count.R` → `data-raw/logs/discharge_fill_305/`; `default`'s width-to-discharge conversion by `data-raw/query_width_mad_equivalent.R` → `data-raw/logs/habitat_thresholds_307/`; the wetland floor by `data-raw/logs/wetland_floor_311/run.R`, `summarise.R` and `obs.R` (same directory) · **Status:** BT `rear_gradient_max` 0.1349 **scored and held**; MAD ranges for BT, GR and RB **scored** (the rule refused loosening past P10 except RB spawning), KO unscored; `cw` against `mad` **scored** (size-adjusted); with main stems filled (#305) `mad` drops only little-used water for BT, GR and RB spawning, and RB rearing reads both ways; `default`'s width-converted MAD ranges (#307) are a conversion, not a calibration, and unscored; every other row unscored

## Verdict

| Species | Threshold | `default` | Candidate (`default_tuned`) | Confidence |
|---|---|---|---|---|
| CH | `spawn_gradient_max` | 0.0449 | **keep** | medium |
| CH | `rear_gradient_max` | 0.0549 | **keep** | medium |
| CH | `spawn_channel_width_min` | 4 | **keep** | medium |
| CH | `rear_channel_width_min` | 1.5 | **keep** | medium |
| CH | `spawn_gradient_min` | 0 | **keep** | high |
| BT | `spawn_gradient_max` | 0.0549 | **keep** | medium |
| BT | `rear_gradient_max` | 0.1049 | **0.1349**, scored on held-out WSGs (step 5) | high |
| BT | `spawn_channel_width_min` | 2 | **keep** | medium |
| BT | `rear_channel_width_min` | 1.5 | **keep** | medium |
| BT | `spawn_gradient_min` | 0 | **keep** | medium |
| BT | `cluster_bridge_gradient` | 0.05 | **keep** | medium |

One gradient or width value moves: BT rearing gradient loosens. (`default_tuned` also
carries MAD ranges from #302, [below](#mad-discharge-ranges-for-bt-gr-ko-and-rb-302).) Every other threshold the observations
argued against was vetoed by the literature. `spawn_gradient_min` and
`cluster_bridge_gradient` live in `parameters_fresh.csv`; both are kept, so
`default_tuned` still inherits that file from `default`.

"Unscored" means the row has not been run against the observation validation (#283).
Step 5 scored the one moved value, BT `rear_gradient_max`, and it held. The CH rows
could not be scored with the data available (Step 5, "Why BT only"). The other BT rows
were not tested.

## Method

The rule was fixed before any distribution was looked at, and applied mechanically
(`candidates.csv`). Three changes were made to it afterwards; all are listed at the end
of this section, with what they moved.

- **Use**: CH and BT observations from `bcfishobs.observations`, with
  `observation_exclusions` (`data_error | release_exclude`) and `Releases Database`
  records removed. The rest are restricted to the 55 WSGs persisted in `fresh_default`
  where `wsg_species_presence` marks the species, match types A/B, one per species ×
  `blue_line_key` × metre. That leaves CH 1,745 locations and BT 2,560, plus 1,970 DV
  pooled with BT where `species_pooling.csv` pools them (4,275 BT+DV locations once shared
  locations are counted once; see Change 4). The quantiles,
  selection ratios and floor test use the ones on accessible segments; for gradient that
  means accessible *and* on a stream edge or river polygon (CH 226 spawning-staged and 497
  rearing-staged; BT+DV 3,988, BT alone 2,443). The bridge share and the `user_habitat_classification`
  overlap use all of them. `obs_ledger.csv` has every step.
- **The segment the model tests.** The pipeline breaks streams at every retained
  observation, so 99 % of points sit within 1 m of a break. The segment *starting* at
  the point (the upstream one) is used. A 100 m FWA window gradient from geometry Z
  checks it independently of link's breaks. The two agree for CH spawning (P95 0.044 vs
  0.042) but not everywhere. **CH rearing is 0.060 vs 0.062, and the window value would
  snap to 0.0649 and flip that verdict to "change".** Pooled BT+DV is 0.131 vs 0.145; the
  window value would snap to 0.1449, one step above the candidate. The segment gradient
  is used because it is what the model tests; the window values are why the scoring
  questions below keep the higher values in play.
- **Availability**: accessible length in the same WSGs, stream edges outside waterbodies
  (plus river polygons for gradient). The **selection ratio** is the share of
  observations in a bin divided by the share of accessible length in it.
- **Rule.** Gradient max = use P95, snapped to the `x.xx49` grid, kept when within 0.5
  percentage points of the current value. Width min = use P5 of width on stream edges
  outside any waterbody (the only place the width test applies with a value to test),
  kept when within 0.5 m. A `spawn_gradient_min` floor needs < 5 % of spawning
  use below it *and* a selection ratio < 0.5 there. The bridge is raised if > 10 % of BT
  observations are lost to clustering. Confidence: high = n ≥ 100 and the literature
  agrees; medium = n ≥ 30 or the literature alone; low otherwise. Only medium or better
  moves a value. The FISS sites and the literature can **veto** a candidate; they
  cannot create one.
- **Change 1, after the rule had run: use restricted to accessible segments.** The rule
  as written did not say which observations the P95 and P5 come from. The first run took
  all of them, while the selection ratios and the floor test in the same script used
  accessible segments only. Review caught the mismatch and all statistics were made
  accessible-only, on the grounds that use on a segment the model already blocks cannot
  inform a habitat cutoff. **This was decided after the numbers had been seen, and it
  moved three verdicts**:
  - CH spawning gradient: P95 0.052 → 0.044, rule 0.0549 change → keep;
  - CH rearing gradient: P95 0.063 → 0.060, 0.0649 change → keep;
  - BT rearing gradient, BT records only (then the primary set): P95 0.131 → 0.125,
    0.1349 → 0.1249. On the pooled BT+DV set adopted later (Change 3) the same change
    moves P95 0.140 → 0.135, **0.1449 → 0.1349**.

  The pre-change values are what #283 scoring should test alongside the kept ones.
- **Change 2: one clause is inverted, and is now removed.** "Keep when the selection
  ratio just above the cutoff is ≥ 1" has it backwards: fish selecting habitat the cutoff
  excludes argues for loosening. It is no longer a keep condition in `candidates.csv`,
  which still reports the ratio. It only ever fired for BT spawning gradient, which is
  vetoed by the literature either way.
- **Change 3: BT and DV pooled.** Inland, DV records are bull trout under the old or a
  mistaken name; on the coast either species occurs, and their habitat biology is close
  enough not to separate for this. So BT+DV is the primary BT evidence, and DV is no
  longer capped at low confidence. BT records alone are kept beside it in
  `candidates.csv` (`evidence_role = "comparison: BT records only"`) and `bridge_bt.csv`
  (`set = BT_any`), so the evidence exists both ways. Pooling moved one value: BT rearing gradient 0.1249 → 0.1349. Since #290 the pooling is data, not code (`species_pooling.csv`): the region rule alone moved no number here, and the Hazelton split that followed is Change 4. It also
  lifted the low-confidence cap on DV staged records, which is why the BT spawning
  gradient and width rows below became literature vetoes instead of weak evidence.

- **Change 4 (link#290): DV is pooled with BT only where `species_pooling.csv` says so, and
  the Skeena is split at Hazelton.** The naming history shows interior DV is a legacy name
  but Skeena DV is a current one ([`species_pooling.md`](species_pooling.md)). So DV counts
  as BT in the Fraser, Mackenzie and Columbia, and in the Skeena only above Hazelton
  (BULK, MORR, KISP, BABL, BABR, SUST, MSKE, USKE). 852 DV records in LSKE, KLUM, LKEL and
  ZYMO drop out.
  - **BT rearing gradient:** P95 0.1348 → 0.1309, n 4,764 → 3,988. The rule still gives
    **0.1349**, but it now clears the 0.13 line that would drop it to 0.1249 by only
    0.0009.
  - **BT spawning width:** P5 1.16 → 1.12 m, rule 1.2 → 1.1 m. It is vetoed either way.
  - No verdict moved.

## Chinook (CH)

**Spawning gradient — keep 0.0449.** The P95 of 226 spawning observations is 0.044,
which the rule rounds to the current value. Selection falls below 1 at 2–3 %, sits at
~0.4–0.5 from 3 to 5 %, and **no spawning observation** lies in (0.05, 0.055], across
2,140 km available. The literature would go tighter, not looser:

- Cooney & Holzer (2006, App. C, C-7/C-8) exclude reaches above 5 % for yearling
  (stream-type) CH, which is most of the interior populations here. About a third of the
  CH locations are in the lower Fraser and coastal Skeena, where ocean-type runs occur;
  there Busch applies.
- Busch et al. (2011/2013) score 4–7 % at 0.05.
- Rebellato et al. (2024, Table 1), the documented origin of the bcfishpass values,
  uses 0–3 %.

The observations say 3–4.5 % still carries real spawning (14 observations), so the value
stays where it is. Confidence is medium, not high: the rule's "high" needs the literature
to agree, and here it points lower.

**Spawning gradient floor — keep 0.** The flattest bin (≤ 0.25 %) is the most selected
(ratio **2.8**; 41 % of spawning observations sit there), and no source in the literature
starts spawning habitat above 0 %. This confirms the reverted 0.0025 floor in
`default_vs_bcfishpass.md` ("Follow-up: spawn gradient minimum design").

**Spawning width — keep 4 m.** Most spawning observations sit on river polygons, where
the width test does not apply. The 67 on stream edges outside any waterbody, with a
width, give a P5 of 6.6 m, and no observations at 4–6 m across 3,368 km available. The
literature vetoes 6.6:

- Cooney & Holzer's 95th-percentile-low of redd reaches is 3.6 m wetted (bankfull
  < 3.7 m = none).
- Busch treats ≤ 4 m bankfull as unsuitable.
- Woll et al. (2017, Table 16) rate "channel size < 4 m" not suitable, which is the
  likely origin of the 4.

Modelled width is also only good to about −30 % / +55 % (see FISS below), which is as
wide as the gap between 4 and 6.6.

**Rearing gradient — keep 0.0549 (medium).** The P95 of 497 rearing-staged observations
is 0.060, which the rule rounds to the current value. Use thins above 2 % but persists
to ~10 % (ratio 0.1–0.5 from 5 to 10 %). The literature is mixed, and a scoring run is
the place to test a higher value:

- For a higher value: Beamer et al. (2013) found no non-natal juveniles above 6.5 %;
  Woll (2017, Table 17) rates 3–7 % as low suitability and > 7 % as none; Agrawal et al.
  (2005, via Sheer 2009) give 8 % as the maximum, with very low value above 3.5 %.
- Against: Cooney & Holzer's > 5 % exclusion is expert opinion.
- The current 5 % itself has no source. Rebellato attributes it to Woll and to Porter
  et al. (2008), and neither states it.

**Rearing width — keep 1.5 m.** P5 1.7 m. The 1.5 m has no literature origin; bcfishpass
describes it as a small-stream filter.

## Bull trout (BT)

bcfishobs gives BT **no life stage or activity at all**. BT and DV records are pooled
(Method, Change 3), the way the pipeline already pools them for access
(`observation_species = BT;DV`). Presence marks DV in 140 of 158 BT WSGs, and the DV
records here are mostly Skeena and interior; the DV spawning records are mostly in MORR,
ZYMO and BULK. The only staged char evidence comes from the DV records: 82 spawning and
1,042 rearing on accessible segments, of which 76 and 991 sit on a stream edge or river
polygon where gradient is tested.

**Rearing gradient — 0.1049 → 0.1349 (high).**

| Evidence | n | P95 | Rule |
|---|---|---|---|
| BT+DV pooled (primary) | 3,988 | 0.131 | 0.1349 |
| BT records only (comparison) | 2,443 | 0.125 | 0.1249 |
| DV rearing-staged | 587 | 0.154 | — |

- Pooled selection is ~0.7 from 5 to 12 %, dropping to 0.41 at 12–15 % and 0.24 at
  15–20 %.
- DV rearing records are selected (ratio ≥ 1) from 6 % to 12 % (1.43 at 10.5–12 %), and
  drop to 0.72 at 12–15 %.
- The literature agrees: Isaak et al. (2015) trim natal habitat at 15 % (< 1 % of
  occurrences above it), with a maximum habitat slope of 14.7 %; Porter et al. (2008)
  found BT CPUE highest in the steeper Thompson streams.
- FISS presence sites (n 15) have a P95 of 0.106. They are fewer, but do not contradict it.
- The current 0.1049 has no source.

Caveat: all-stage use includes adults, so this is rearing inferred from occurrence.

**Spawning gradient — keep 0.0549 (medium).** The 76 gradient-tested DV spawning
records give a P95 of 0.196, and the rule says 0.1949. Most of them are low-gradient: 46
(61 %) sit at or below 5 %, and the median is 0.031. The P95 is set by a thin tail: 17 at
5–10 %, 7 at 10–15 %, and **6 above 15 %**. Six records on 15–25 % segments are what
points at site ends on averaged segments can produce (Biases, below). They are not
evidence of spawning on 20 % slopes.
The literature vetoes it: redd sites are < 1 % (McPhail & Murray, via Ford et al. 1995)
and spawning reaches are "relatively low gradient" (McPhail & Baxter 1996). No source
gives a numeric reach-scale maximum.

**Spawning width — keep 2 m (medium).** DV spawning P5 is 1.12 m (n 40), and the rule
says 1.1. The literature vetoes it: the source for 2 m in spawners, Hagen et al. (2015,
§4.1.2, Parsnip and Pack), gives it as **wetted** width, the limit of use by migratory
spawners. Wetted runs narrower than the channel width the model tests, so 2 m of channel
width is, if anything, generous. Resident BT do spawn in smaller streams (McPhail &
Baxter 1996), but no source gives a number for them, so this stays open for scoring.

**Rearing width — keep 1.5 m (medium).**

- Pooled P5 is 1.47 m (BT alone 1.91 m), and pooled selection is ≥ 1 from 3 m.
- FISS presence sites have a P5 of 1.9 m, with none below 1.5.
- Juvenile occurrence is "very unlikely" below 2 m wetted width (Dunham & Rieman 1999,
  as cited in Dunham & Chandler 2001, pp. 3 and 26).

The pooled P5 sits on the current value; nothing argues for a lower one.

**`spawn_gradient_min` — keep 0.** DV spawning selection is 2.2 in the flattest bin.

**`cluster_bridge_gradient` — keep 0.05.** Only 1.5 % of pooled BT+DV observations (62
of 4,275; BT alone 1.2 %, 31 of 2,560) sit on accessible segments that pass the rearing
predicate yet end up `rearing = FALSE` (`bridge_bt.csv`).

What the bridge does, from fresh's `.frs_cluster_both()`: a rearing cluster is kept if
spawning lies anywhere **upstream** of it, with no gradient test. Failing that, it is
kept if a downstream trace reaches spawning within 10 km through reaches under the
bridge gradient. The 5 % therefore only matters for rearing that sits **above**
spawning. Newly admitted 10.5–13.5 % rearing is kept when spawning lies above it, and
otherwise only when it can reach spawning below through gentler water. The literature
gives the bridge rule no origin.

## FISS site evidence

The `knowledge` repo's parse of provincial FISS data submissions covers COTR, LNTH, PINE,
UNTH and UPCE: 9,679 sites, 362 of them with measured width. Only aggregates are
committed here.

- **Modelled width error.** At 18 sites with a crew measurement and a MODELLED segment
  width, modelled width is a median 0.97 × measured, with a p10–p90 of 0.69–1.56 (about
  −30 % / +55 %). Any width
  cutoff is resolved no better than that. The 81 FIELD_MEASURMENT segments match at 1.00
  because fwapg built them from these same sites, so they are not independent.
- **Presence vs absence.** BT presence sites (n 16 for width, 15 for gradient) sit on wider, flatter water (median
  5.5 m, 2.5 %) than sampled-without-BT sites (1.46 m, 8 %). No CH was caught at a site
  with measured width.
- **Units upstream.** `average_gradient_percent` holds proportions. This has been
  reported to `knowledge` rather than corrected here.

## Biases, stated rather than corrected

- Observation points often sit at the downstream end of a sampling site, and the
  pipeline breaks segments at them.
- Sampling clusters near road access and avoids big rivers and steep reaches; that is
  the likely reason BT use on NULL-width (order-1) segments is 0.12 of availability
  (pooled BT+DV; 0.08 for BT records alone).
- Segment gradient is an average: a reach can hold a short steep pitch above its mean,
  or a flat one below.
- **Access does not truncate the observed gradients.** Observations lift barriers (CH
  threshold 5 since 1990, BT 1), so 98 % of CH and 99 % of BT observation segments are
  accessible.
- `user_habitat_classification` holds 636 of the CH locations inside known spawning
  reaches, and was itself built partly from observations, so it cannot confirm them.
- Coverage is `fresh_default`'s 55 WSGs. Most are interior, but the lower Fraser (LFRA,
  HARR, CHWK) and the lower and coastal Skeena (LSKE, KLUM, LKEL, ZYMO) carry 565 of the
  1,745 CH locations. Harrison and Chilliwack fall runs are ocean-type. The observations
  are therefore a mix of life histories that the literature treats separately, and
  nothing here splits them. Vancouver Island and the central coast are not covered.
- River-polygon segments with NULL width fail the rule's `channel_width [0, 9999]`
  (a `BETWEEN`), so they drop out of spawning and rearing. 55 retained observations sit
  on them, 31 of those in TABR, UPCE and LPCE. That is a model behaviour worth its own
  issue, not a threshold.

## Step 5 — scoring (#283)

The validator exists: `lnk_habitat_validate()` and `data-raw/habitat_validate.R`
([`habitat_validation.md`](habitat_validation.md) has the method, the baseline, and the
command). Two findings from it change how this step is read:

- **CH spawning cannot be scored on spawn-staged observations.** 237 of 245 sit in
  `user_habitat_classification` spawning reaches, which `default` forces to habitat.
  Use the any-stage capture and `share_spawning_outside_uhc`.
- **BT rearing 0.1349 scores in-sample,** because it is the P95 of the same BT+DV
  locations. Hold records out (by project, date or WSG) through the function's
  `observations` argument.

### Scoring design, fixed 2026-09-29 before any run

Every threshold variant is scored on the **same segmentation**. Each pilot WSG is prepared
once under `default` and then re-classified once per variant, because two full runs are not
bit-reproducible: the PSCIS tie in `lnk_pipeline_pscis_build.R` moves a segment. Access
does not depend on the habitat thresholds, so every variant carries `default`'s
`streams_access`.

- **Variants** (`data-raw/habitat_score/variants.csv`): BT `rear_gradient_max` at 0.1249,
  0.1349 (`default_tuned`) and 0.1449, each differing from `default` in that one cell.
- **WSGs** (`data-raw/habitat_score/wsg_roles.csv`):
  - **Held out:** ELKR, BULL, UARL, REVL, CLRH, LILL, BABL and BABR, none of them among the
    55 WSGs the step-1 percentiles came from.
  - **In-sample:** PARS, KOTL, BULK and MORR.
  - The twelve resolve to a 23-WSG drainage closure, which is modelled downstream-first so
    that access sees the barriers below each pilot. Only the pilots are re-classified.
- **The band.** Each variant steps from its neighbour nearer `default` in the ladder
  0.1049 → 0.1249 → 0.1349 → 0.1449. The band is the set of segments whose stream-rearing
  flag differs between the two, joined on `(id_segment, watershed_group_code)`.
  - **The core** is the segments that are rearing under every variant of the ladder, which
    is `default`'s rearing outside every band.
  - **Observations** are the validator's: the #290 pooling from `default`'s tracker, buffer
    0. All stages count, since BT carries no life stage; that is the population the 0.1349
    was calibrated on. BT has no `user_habitat_classification` reaches, so no forced
    habitat sits in the core.
- **Rule.**
  - A band **is habitat** when its observations per km are at least 0.5 × the core's.
  - It is read on the held-out WSGs, pooled, and needs **n ≥ 10** locations in the band.
  - A step is taken when its band is habitat. The walk goes outward from `default` and
    stops at the first step not taken.
  - **An underpowered step (n < 10) changes nothing.** The step 1–4 verdict stands:
    `default_tuned` keeps 0.1349, and the verdict is recorded as scored but underpowered.
  - In-sample WSGs are reported and never decide. The literature veto stands.

**Why BT only, and why these WSGs.** Before any band was computed, observation locations per
gradient window were counted with no density attached (`data-raw/logs/habitat_score_284/`,
FWA segment gradients, so upper bounds). The eight pilots first planned held out ELKR and
BULL for BT, and UNTH and LNTH for CH:

| window | first held-out set | widened BT set | all 8 pilots | non-calibration WSGs (106 BT, 94 CH) |
|---|---|---|---|---|
| BT 0.1049–0.1249 | 10 | 43 | 66 | 95 |
| BT 0.1249–0.1349 | **1** | 33 | 15 | 45 |
| BT 0.1349–0.1449 | 0 | 22 | 17 | 35 |
| CH spawn-staged 0.0299–0.0449 | 0 | | 2 | 35 |
| CH spawn-staged 0.0449–0.0549 | 1 | | 1 | 19 |
| CH rear-staged 0.0549–0.0649 | 2 | | 2 | 17 |

As first planned, the rule could not have decided five of the six steps. The held-out BT
set was widened to the densest non-calibration BT WSGs (UARL, REVL, CLRH, LILL, BABL and
BABR, beside ELKR and BULL), which gives the 43 / 33 / 22 above.

CH was dropped. The CH locations outside the calibration set are spread thin: the
densest WSGs hold 5, 2 and 5 per step (OWIK, LISR and CARR). Reaching n ≥ 10 would
take three to six more WSGs per step, each with its own closure, on counts that are
upper bounds before the access, width and cluster filters. **The CH verdicts stay
"keep", unscored.** Operator's call, 2026-09-29, prompted by the plan review that found
the gap.

The questions scoring must answer:

1. How much rearing length the BT gradient change adds, against the observation capture
   it buys. Test BT-only 0.1249 and the pooled pre-change / window value 0.1449 beside the
   pooled 0.1349. The CH values retired by Method, Change 1 (CH spawning 0.0549, CH
   rearing 0.0649) were to be tested too; they are unscorable (above).
2. How much of the newly admitted BT rearing sits above spawning, where the 0.05
   downstream bridge decides whether it survives.
3. Whether spawning capture at 3–4.5 % justifies keeping the CH cutoff above the
   literature's 3 %. Unscorable: 0 held-out spawn-staged locations in that window.

### Results, 2026-09-29

**In plain terms.** The old line said BT stop rearing at about 10 % gradient. Moving it
to 12, 13 and 14 %, we checked whether bull trout turn up in the streams each move adds,
on watersheds not used to choose the number:
- between 10 and 13 % they do, at roughly two-thirds to nine-tenths of their rate in
  normal rearing at the same elevation, so that water is habitat;
- past 13 % they mostly don't: 8 sightings where about 25 were expected.

So 0.1349 holds. Steep water looks emptier than it is partly because it sits high,
where every stream holds fewer fish (colder, smaller, less sampled). Comparing like
with like by elevation is what the adjusted ratio does. Across the 12 watersheds the
change adds about 6 % more rearing (table below).

Run `20260930_014921-53610765`, link @ `a11a001` (build) and `031c5cc` (score). The 23-WSG
closure was modelled clean; each variant differs from `default` in one cell, on one
shared segmentation. Evidence: `data-raw/logs/habitat_score_284/` (`verdict.csv`,
`bands_pooled.csv`, `taper.csv`, `elevation*.csv`, `bridge_band.csv`, `built.csv`,
`stamp_*.txt`).

**Verdict: BT `rear_gradient_max` 0.1349 holds.** Held-out WSGs, pooled; the core is
18.1 locations per 100 km.

| step | band km | found | expected at the core rate | ratio | elevation-adjusted | rule | expected-count floor |
|---|---|---|---|---|---|---|---|
| 0.1049 → 0.1249 | 422 | 46 | 76 | 0.60 | 0.75 | take | take |
| 0.1249 → 0.1349 | 163 | 21 | 29 | 0.71 | 0.89 | take | take |
| 0.1349 → 0.1449 | 138 | 8 | 25 | 0.32 | 0.40 | keep (n < 10) | refuse |

- **Both steps to 0.1349 are taken, and the step past it is not.** Under the rule as fixed
  it is underpowered, which leaves 0.1349 standing. Under the alternative floor
  (discussed with the operator after the build; see below) it is refused, which also
  gives 0.1349. `default_tuned` does not change.
- **Capture against cost** (held out, all stages): stream-rearing capture goes from
  81.2 % under `default` to 84.2 % at 0.1349 (1,841 → 1,908 of 2,266 locations) for
  585 km more rearing (+5.7 %). 0.1449 adds 138 km for 8 more.
- **How much rearing the change adds** (`habitat_change.csv`, `default` → 0.1349, BT
  stream rearing): **19,133 → 20,237 km, +1,105 km (+5.8 %)** across the 12 WSGs.
  Spawning is unchanged: the cutoff is a rearing threshold.

  | WSG | role | before | after | added |
  |---|---|---|---|---|
  | KOTL | in-sample | 1,599 km | 1,742 km | +143 km (+8.9 %) |
  | UARL | held out | 777 | 846 | +69 (+8.8 %) |
  | BULL | held out | 1,062 | 1,151 | +89 (+8.3 %) |
  | ELKR | held out | 2,123 | 2,284 | +161 (+7.6 %) |
  | CLRH | held out | 988 | 1,048 | +60 (+6.1 %) |
  | LILL | held out | 906 | 958 | +51 (+5.7 %) |
  | REVL | held out | 561 | 593 | +32 (+5.6 %) |
  | PARS | in-sample | 2,635 | 2,775 | +140 (+5.3 %) |
  | BULK | in-sample | 3,010 | 3,169 | +159 (+5.3 %) |
  | BABR | held out | 1,724 | 1,806 | +82 (+4.8 %) |
  | MORR | in-sample | 1,692 | 1,770 | +78 (+4.6 %) |
  | BABL | held out | 2,055 | 2,097 | +42 (+2.0 %) |

  The mountainous Kootenay and Columbia groups gain most, and the Babine least. These are
  the only WSGs modelled at both cutoffs, so "about 6 %" elsewhere is a guess, not a
  measurement.
- **In-sample WSGs agree** (ratios 0.89, 0.70, 0.65; elevation-adjusted 0.94, 0.75,
  0.69), and never decide.
- **The core itself tapers** with gradient: 18.6, 19.8, 15.6 and 11.8 locations per
  100 km at ≤ 2, 2–5, 5–8 and 8–10.5 %. A cutoff is one line across a slope, not a
  cliff the fish see (knowledge#28 takes up weights instead of cutoffs).
- **Elevation is a confound.** Core rearing thins from 24.6 to 19.3 to 10.2 per 100 km
  across the low, mid and high thirds of each WSG's own rearing, and the steep bands
  sit mostly high: 263 of the first band's 422 km, and 366 of the 585 km the two steps
  to 0.1349 add (63 %; `elevation.csv`, held out). The elevation-adjusted ratio
  compares each band with the core at its own elevation mix. It raises the first two
  steps, and the third stays low.
- **Question 2 (the bridge).** Of the first band's 422 km, 140 km has spawning upstream
  and 282 km (67 %) survives only through the 5 % downstream bridge. The later bands
  are 70 % and 74 % bridge-only. 101 km of the first band lies outside its gradient
  window: lower-gradient stream the looser cutoff connects to a spawning cluster.
- **Clustering moves a little habitat the other way.** Loosening removed 1.1 km of
  rearing (BULK, KOTL, LILL; 0.07 km held out) while adding 1,365 km, when a newly
  admitted segment merges clusters.
- **Absences** do not reach these WSGs: the FISS snapshots cover none of the twelve.
- **Re-running the score changes only the last digit or two** of the km sums and ratios
  (`bands*.csv`, `taper.csv`, `elevation.csv`, `bridge_band.csv`). The double-precision
  length sums in Postgres depend on summation order, the same effect as #293. No count,
  ratio at printed precision, or verdict moves.

**The floor, discussed after the build (2026-09-29).** The rule's floor is on the
locations *found* in a band. A band fish avoid produces few, so it reads as
"underpowered", not "refuse". The rule can confirm a loosening but hardly ever reject
one, which is backwards for a sparse species. The alternative floor is on the locations
the band would hold at the core's rate (band km × core rate), which is set by the band's
length before any fish are counted. Both are in `verdict.csv` (`decision`,
`decision_expected_floor`). They agree on every step that decides the value, so the
choice did not need making here. It is open for the next tuning.


## MAD (discharge) ranges for BT, GR, KO and RB (#302)

Under the `mad` habitat model (#286), fresh tests a stream rule's size on mean annual
discharge (`mad_m3s`) against `*_mad_min` / `*_mad_max`. Before #302, BT, GR, KO and RB
carried no MAD range in any bundle (inherited from bcfishpass `example_newgraph`; still
none in `bcfishpass`, and none in `default` until #307 converted its width minima,
[below](#defaults-mad-ranges-converted-from-its-width-minima-307)), so in a `mad` group
fresh fails every inheriting stream rule and they keep only waterbody habitat. The
operator's direction (#299 plan gate, 2026-10-02) was to tune and add the ranges.

**Nothing changes in any output until a group is moved to `mad`.** Every shipped bundle
is all `cw`, so the ranges land in `default_tuned` without moving a segment. The only
before/after evidence is the scoring harness, which puts the held-out groups on `mad`.

### Verdict

| Species | Threshold | `default` at #302 | `default_tuned` | How |
|---|---|---|---|---|
| BT | `spawn_mad_min` | NA | **0.078** | scored: P10→P05 refused |
| BT | `rear_mad_min` | NA | **0.078** | scored: P10→P05 refused |
| GR | `spawn_mad_min` | NA | **0.96** | scored: P10→P05 refused |
| GR | `rear_mad_min` | NA | **0.97** | scored: P10→P05 refused |
| KO | `spawn_mad_min` | NA | **0.57** | candidate, unscored (no held-out WSG) |
| RB | `spawn_mad_min` | NA | **0.011** | scored: P10→P05 taken, P05→P02 underpowered |
| RB | `rear_mad_min` | NA | **0.019** | scored: P10→P05 refused |

Every `*_mad_max` is 9999. Values are m³/s. They are inert until a group is moved to
`mad`. **At these values a `mad` group keeps less stream rearing than `cw` does: on the
held-out WSGs −36 % for BT, −82 % for GR and −4 % for RB** (the landed pair, built in
#300; #302's P10 rows were lower bounds; with #305's main-stem fill, −32 %, −76 % and
−2.8 %, [below](#filling-discharge-on-river-polygon-main-stems-305)). (`default` at #302 had no
range for these species; it has width-converted ones since #307,
[below](#defaults-mad-ranges-converted-from-its-width-minima-307).) Most of what `mad` drops below its minimum is
little-used small water. Its most-used loss is river-polygon main stems with no discharge
value; see "`cw` against `mad`" below.

### Candidates (Phase 1, before scoring)

| Species | Threshold | `default` at #302 | Rule value | Evidence | n | `cw` equivalent |
|---|---|---|---|---|---|---|
| BT | `spawn_mad_min` | NA | **0.027** | any stage, fallback (17 spawn-staged) | 2,592 | 2 m ≈ 0.041 |
| BT | `rear_mad_min` | NA | **0.027** | any stage | 2,592 | 1.5 m ≈ 0.021 |
| GR | `spawn_mad_min` | NA | **0.095** | any stage, fallback (7 spawn-staged) | 540 | 4 m ≈ 0.20 |
| GR | `rear_mad_min` | NA | **0.095** | any stage | 542 | 1.5 m ≈ 0.021 |
| KO | `spawn_mad_min` | NA | **0.57** | spawn-staged, one WSG | 31 | 2 m ≈ 0.041 |
| RB | `spawn_mad_min` | NA | **0.011** | spawn-staged | 55 | 2 m ≈ 0.041 |
| RB | `rear_mad_min` | NA | **0.0094** | any stage | 4,508 | 1.5 m ≈ 0.021 |

Every `*_mad_max` is open (9999). Values are m³/s. The `cw` equivalent is the median
`mad_m3s` on `fresh_default` stream segments whose modelled channel width sits within
0.1 m of the species' current width minimum (`width_mad_equivalent.txt`). It says how the
candidate compares with what `cw` admits today, and is not evidence.

### Method

- **Instrument.** `lnk_habitat_validate()` over the 46 WSGs persisted in `fresh_default`
  that carry discharge, with every one of them put on `mad` by a method-table override.
  Each observation location then carries its segment's `mad_m3s`, joined from
  `fwa_stream_networks_discharge` on `linear_feature_id`, which is unique there. Pooling
  (#290), exclusions, stage and access are the validator's own.
- **Which locations.** Accessible ones (`access` 1 or 2) on a segment the stage's rule
  tests on discharge under `mad`:
  - spawning: a river polygon, or a stream edge outside any waterbody;
  - rearing: a river polygon, or a stream edge anywhere, except one the species' own lake
    or wetland rule admits (taken from fresh's compiled SQL, not from `rules.yaml`).

  This classification was checked against fresh's compiled `mad` predicates on every
  `fresh_default` segment, for BT and GR at both stages, and they agree on all of them.
  `rearing` itself is never cut by a rear range inside lakes and wetlands. The range
  gates only the `lake_rearing` / `wetland_rearing` bucket columns, as a width does under
  `cw`.
- **Rule, fixed and committed before the first full run (`a7f919e`):**
  - spawn minimum = P05 of spawn-staged locations;
  - rear minimum = P05 of locations at any stage (these are residents, or carry no
    stage, as #284 read BT rearing). Rear-staged is reported beside it.
  - Values are floored to two significant figures, and `*_mad_max` is open.
  - Fewer than 30 locations leaves the cell NA.
  - KO rearing is lake-only, so KO gets a spawning range only.
- **Change 1 (operator, 2026-10-02, before the full run): thin spawning cells fall back
  to any stage.** Spawn-staged evidence is thin: 17 BT (pooled DV) and 7 GR locations on
  tested segments. BT and GR cluster rearing on spawning (`cluster_rearing = TRUE`), so an
  empty spawning range would also empty their stream rearing under `mad`. Where
  spawn-staged locations number fewer than 30, the spawning minimum is the any-stage P05
  on spawn-tested segments, labelled `fallback: any stage`. It moved BT and GR spawning
  from NA to 0.027 and 0.095. The spawn-staged P05s, for the record, are BT 0.019 and
  GR 0.61.
- **No cap.** Use runs into the largest rivers. GR's P95 is 114 m³/s and its P99 131;
  BT's P99 is 80. Every bundle's existing rearing caps (CH 100, CO 40, ST 60, WCT 40) read
  as axis limits of the curves they came from, not as biology (literature, below).
- **Coverage.** 9–28 % of tested locations sit on a line with no discharge (BT 11 %,
  GR 28 %, KO 15 %, RB 9 %, any stage). Under `mad` those lose stream habitat whatever
  the range. That is a property of the discharge layer, not of the threshold.

### Literature

No source gives a fitted MAD minimum for these four species, and none supports a cap.
Site evidence is set below beside the Phase 1 candidates and the values the scoring
landed (full table: [`literature.md`](../planning/archive/2026-10-issue-302-mad-thresholds/literature.md), archived with #302's PWF):

- **BT.**
  - Hagen et al. 2015 (Table 2, p. 31) found redds at spawning-time flows down to
    0.25–0.30 m³/s, in a survey that skipped streams under 2 m by design.
  - Isaak et al. 2015 (p. 2542) trims juvenile habitat below 0.0057 m³/s mean summer flow
    (about 1 m wetted).
  - Neither is MAD, and Isaak's floor is a summer flow whose MAD equivalent is larger by
    an unknown amount. Neither bounds the candidate 0.027 or the landed 0.078 closely.
- **GR.**
  - No number for MAD.
  - Spawning is documented at 0.21–0.25 m³/s freshet flow in a constructed channel
    (House 2021, p. 76) and at about 400 m³/s in the Fond du Lac (p. 80). That rules
    out a cap.
  - **The landed spawning minimum 0.96 sits above that small-stream site's freshet
    flow.** Its MAD is not stated and is likely lower. On one constructed channel in the
    NWT, the literature leans lower for GR spawning.
- **KO.**
  - Spawning is documented at MAD 0.37–0.40 m³/s (Davidson Creek) and in a creek whose
    mouth MAD is 0.28 m³/s (AMEC 2015). In both, the upstream limit is put down to
    migration, not flow.
  - **Both sit below the candidate 0.57.** The candidate rests on 31 locations in one WSG.
- **RB.**
  - Spawning and rearing are documented at MAD of about 0.1 m³/s (AMEC 2015).
  - 0+ fish occur at 0.028 m³/s late-summer flow (Bustard 1988).
  - Juveniles are found down to 0.002 m³/s summer flow (via Sheer et al. 2009).
  - Consistent with the candidates (0.0094 rear, 0.011 spawn) and with the landed rearing
    minimum 0.019.
- **The existing bcfishpass MAD minima are mostly untraceable.** CH rearing 0.28 is
  documented (Agrawal 2005, via Sheer 2009). The spawning minima (CH 0.46, CO 0.164,
  SK 0.175, ST 0.447) were not found in the sources Rebellato et al. 2024 cites. WCT's
  row equals the CO row, cap included.
- **Width to discharge.** Woll et al. 2017's Alaskan relation (w = 1.71 Q^0.471, Q in
  cfs) gives 0.021, 0.040 and 0.17 m³/s at 1.5, 2 and 4 m. That is close to the BC-native
  medians above (0.021, 0.041, 0.20).

### FISS sites

Five WSGs have FISS snapshots: COTR, LNTH, PINE, UNTH and UPCE (`knowledge` @
`4fb1575`). The site's segment discharge is modelled, never measured, and the site is
snapped within 50 m (`fiss_presence.csv`, `fiss_share_below_candidate.csv`; KO is absent
from all five).

| Species | Candidate | Present sites below it | Absent sites below it |
|---|---|---|---|
| BT | 0.027 | 23 % of 139 | 27 % of 2,027 |
| GR | 0.095 | 22 % of 97 | 26 % of 1,273 |
| RB | 0.0094 | 27 % of 241 | 17 % of 1,925 |

Presence and absence do not separate at these cutoffs, so FISS neither supports nor
vetoes a candidate.

- About a quarter of the sites where the species was caught sit on a segment below its
  candidate.
- Unlike the observation set, these sites are not filtered to accessible, size-tested
  segments.
- A 50 m snap can land a mainstem site on a side tributary.

The scoring below decides whether the range costs real use.

### Scoring design, fixed 2026-10-02 before any run

The #284 harness (`habitat_variants_build.R`, `habitat_variants_score.R`), extended for
MAD (`data-raw/habitat_score/README.md`).

- **Ladders.** One per species × stage, BT/GR/RB spawning and rearing (6 ladders, 18
  variants; `variants_302.csv`):
  - an **anchor** at P10 steps from the `cw` base straight to `mad`. It is taken by
    construction, the operator's direction to add a range. Its bands (what `mad` keeps
    that `cw` drops, and the reverse) are reported and decide nothing;
  - then P10 → P05 → P02, walked out as #284 walked;
  - the other stage's range is held fixed at its candidate through `set`. BT and GR
    rearing needs spawning upstream, so a rearing rung with no spawning range would score
    nothing.
  - Rungs carry `default`'s gradient cutoffs.
- **The core** is the habitat every rung of the ladder keeps, which is the anchor's.
  - The `cw` base is left out. It tests a width floor and fails NULL widths, and no `mad`
    rung does either. Code review found that a core cut by it would differ from the bands
    on an axis no step is about.
  - On PARS, KOTL, MORR and BULK it would drop about 5 % of the km at
    `mad_m3s` ≥ 0.05, and about 17 % at ≥ 0.02.
  - `set` may hold only `*_mad_*` cells, so the bands differ from the core in discharge
    alone.
- **Held-out WSGs** (`wsg_roles_302.csv`) are discharge-covered and outside the 55
  `fresh_default` WSGs, of which the 46 with discharge were the calibration set. They
  were chosen as the densest per window before any build
  (`power_windows.txt`, counts only, upper bounds):
  - BT: REVL, ELKR, KOTR, UARL, MURR, UBTN, LHAF;
  - GR: UBTN, MURR, LHAF;
  - RB: SIML, OKAN, KETL, ELKR, REVL, KOTR.

  PARS (BT, GR, RB) and KOTL (BT, RB) are in-sample, reported, and never decide. HERR
  and LNTH were dense but left out because their closures pull in the upper Fraser. The
  20-WSG closure is smaller than #284's.
- **Rule.**
  - A band is habitat when its observations per km are at least 0.5 × the core's, on
    the held-out WSGs pooled.
  - **The floor of record is on locations expected** at the core's rate (band km × core
    rate ≥ 10), not on locations found (operator, 2026-10-02). A walk that only loosens
    from a tight anchor is where a found-count floor cannot refuse. Both readings are
    written.
  - A step is taken when its band is habitat. The walk stops at the first step not taken.
  - **An underpowered first step lands P05, marked unscored** (operator, 2026-10-02).
- **KO is unscorable.** It is present in four discharge-covered WSGs, all of them
  calibration WSGs. Its candidate lands unscored, as CH did in #284.

### Results, 2026-10-02

The build ran at a clean `c2fed37` in 145 min, with every invariant asserted. The base
recompute printed "There were 50 or more warnings", which were not recorded
(`build_20261002_full.log`). It was a
20-WSG closure, LHAF pre-flighted first, and 18 variants. The score ran under
`--floor=expected` (`verdict.csv`, `bands_pooled.csv`, `elevation_adjusted.csv`,
`habitat_change.csv`; logs `build_20261002_*.log`, `score_20261002.log`). The held-out
WSGs are pooled throughout.

| Step | Band km | Found | Expected at core rate | Ratio | Elevation-adjusted | Decision |
|---|---|---|---|---|---|---|
| BT rear P10→P05 | 2,037 | 45 | 297 | 0.15 | 0.16 | refuse |
| BT spawn P10→P05 | 1,439 | 30 | 247 | 0.12 | 0.12 | refuse |
| GR rear P10→P05 | 1,523 | 57 | 124 | 0.46 | 0.57 | refuse |
| GR spawn P10→P05 | 1,378 | 52 | 113 | 0.46 | 0.54 | refuse |
| RB rear P10→P05 | 1,032 | 19 | 138 | 0.14 | 0.16 | refuse |
| RB spawn P10→P05 | 1,267 | 8 | 10.1 | 0.80 | 0.93 | take |
| RB spawn P05→P02 | 630 | 1 | 5.0 | 0.20 | 0.23 | underpowered |

The two floors agree on every step that decides a value, except RB spawning P10→P05.
It is taken under the expected floor of record (10.1 expected) and underpowered under
the found floor (8 found). Both land 0.011; they differ only in whether it counts as
scored.

**What the anchor costs.** The anchor's `removed` band is the habitat `cw` keeps and
`mad` at P10 drops. Fish use it at 0.36 (BT rear), 0.48 (BT spawn), 0.50 (GR rear) and
1.06 (RB rear) of the core rate.

The band splits in two:

- **What P05 and P02 restore.** This is most of the band by length. In the rearing
  ladders it is BT 3,062 of 4,505 km, GR 3,099 of 3,893 and RB 569 of 864. In the
  spawning ladders it is BT 1,961 of 2,752 and GR 1,769 of 2,241. Its use rate relative
  to the core is BT rear 0.08, BT spawn 0.06, GR rear 0.36, GR spawn 0.47 and RB
  rear 0.42.
- **What no rung restores.** In the rearing ladders this is BT 1,444 km, GR 794 km and
  RB 296 km. It is used at about the core rate for BT (0.97; 0.86 adjusted for
  elevation) and above it for GR (1.06) and RB (2.30).

The split is derived as the `removed` band in `bands_pooled.csv` minus the `removed` class
in `elevation_adjusted.csv`. That class is the remainder, because the score labels each
segment by the first step whose flags differ. What the remainder is made of was not
written to any file. A review query on the rearing ladders found lines with no
discharge (mostly inside waterbodies) and water below P02. It also found water at or
above P02 that the rungs still drop: BT 146 km and GR 267 km.

Stream rearing on the held-out WSGs, from `habitat_change.csv`:

| Species | `cw` | `mad` P10 | `mad` P05 | `mad` P02 |
|---|---|---|---|---|
| BT | 12,991 km | 8,679 (−33 %) | 10,712 (−18 %) | 13,235 (+2 %) |
| GR | 4,705 | 825 (−82 %) | 2,348 (−50 %) | 5,022 (+7 %) |
| RB | 8,186 | 7,821 (−4 %) | 8,853 (+8 %) | 9,849 (+20 %) |

These rearing rungs held spawning at its P05 candidate (BT 0.027, GR 0.095). The landed
spawning ranges are tighter (0.078, 0.96), and BT and GR rearing clusters on spawning.
So for BT and GR **the P10 row is a lower bound on the loss** at the landed values, which
pair was never built. The spawning P10 rungs alone take BT rearing from 10,712 to
10,215 km and GR rearing from 2,348 to 1,558 km. RB's P10 row is the landed pair.

**Reading it.**
- **By the rule fixed before the run, BT, GR and RB rearing and BT and GR spawning stay
  at P10.** The P10 → P05 band for each is used at 0.12–0.46 of the rate of the larger
  water the anchor keeps. RB spawning's band is used at 0.80, so it moves to P05.
- **Elevation explains part of GR's gap, but not BT's or RB rearing's.**
  - Adjusted for elevation, the GR steps read 0.57 (rear) and 0.54 (spawn), above the
    0.5 line, so an elevation-adjusted rule would have taken them.
  - The BT steps and RB rearing stay at 0.12–0.16.
  - RB spawning rises from 0.80 to 0.93.
- **Stream size and sampling effort are not separated by this design (inference).** The
  core is the bigger water. If surveys cover large and small streams unevenly per km,
  part of the gap is where people look, not where the fish are. Nothing here measures
  that. The Biases section notes surveys avoid the largest rivers, which would cut the
  other way. A core split by stream size, as the elevation classes split elevation
  (#284), is the test. Until then the verdict stands as pre-registered.
- **What it costs.** At P10 a `mad` group keeps at least a third less BT rearing, and at
  least four-fifths less GR rearing, than `cw` does in the same WSGs. At P05 the losses
  would be −18 % and −50 %. At P02 the losses vanish.
- **Nothing switches today.** These values are inert while every group is on `cw`.
  Moving a group to `mad` is the operator's call, and it should wait for that re-score.
- **KO 0.57 is unscored, and the literature argues lower.** AMEC 2015 documents spawning
  at MAD 0.37–0.40 in Davidson Creek. In Creek 661 it occurs at ≤ 0.283, above 0.105.
  The candidate rests on 31 locations in one WSG.
- **Clustering moved a little habitat the other way.** On the held-out WSGs, BT rear
  moved 3.2 and 1.1 km against 2,037 and 2,523 km added, as in #284.

## `cw` against `mad`: which model's habitat do fish use? (#300)

#302's anchor bands were scored against a core of `mad` rungs, and the landed spawning
and rearing pair was never built, so they do not say which model is closer to where fish
are. This section compares the two models directly, in `default_tuned`, at the landed
ranges.

### Scoring design, fixed 2026-10-02 before any run

The #284 harness, extended for a **model-only variant** (`data-raw/habitat_score/README.md`):
a variant that changes no threshold cell and puts its species' WSGs on `mad`.

- **Base: `default_tuned` on `cw`** (`--base=default_tuned`, `variants_300.csv`), so the
  `mad` side carries the landed ranges and BT `rear_gradient_max` 0.1349 on both sides.
  Variants `bt_mad`, `gr_mad`, `rb_mad`, `ko_mad`: the same bundle, the species' WSGs on
  `mad`. Spawning and rearing move together, as they would in a real switch, so BT and GR
  rearing clusters on the landed spawning range.
- **Core:** segments both models flag (base ∩ variant), per flag.
- **Bands:** `cw`-only (the variant's `removed`) and `mad`-only (its `added`), per flag
  (spawning, rearing). KO has no stream rearing range under either model; its rearing
  bands are reported and read nothing.
- **Held-out WSGs:** #302's (`wsg_roles_300.csv` = `wsg_roles_302.csv` plus KO). KO is
  present only in KOTL and PARS, both in-sample: it is reported and decides nothing.
- **Stream size: stream order**, in classes 1, 2, 3 and 4+ (operator, 2026-10-02).
  Neither model tests order, so it sides with neither: `rear_stream_order_bypass` is `no`
  for BT, GR, KO and RB, and classify skips the bypass under `mad` anyway. Each segment of
  the base network is core, `cw`-only or `mad`-only, with its order class.
  - **Expected** locations in a band = Σ over classes of band km × the core's rate in
    that class, the core's rate pooled over the WSGs of one role (species × flag × stage
    × role × class), from that stage's own observations.
  - **Thin classes merge** (added after plan review, before any build). A core class can
    be too thin to give a rate. #302's GR rearing anchor kept 30 km of core in orders 1–3
    against 1,826 km of `cw`-only band there. So, walking up from order 1, a class joins
    the next until the group's core holds at least 10 locations, and a short last group
    joins the one before. If no class reaches 10, every ordered class is one group. The
    adjustment is then the pooled ratio, which is what the data can support.
  - Order 0 and NULL are `unknown`. They are priced at their own rate when their core
    holds 10 locations, and at the core's pooled rate otherwise.
  - `model_verdict.csv` reports the band km priced on a merged or a pooled rate, so a
    size-adjusted ratio that rests on little size information says so.
  - **Size-adjusted ratio** = locations found ÷ expected.
- **Why each band differs is reported, not scored** (`model_reason.csv`). A `cw`-only
  segment has no discharge (`mad_null`), is outside the species' MAD range
  (`outside_mad_range`), or is inside it and was dropped by connectivity or clustering
  (`in_mad_range`). A `mad`-only segment has no width (`width_null`), is outside the width
  range (`outside_width_range`), or is inside it (`in_width_range`). Plan review found
  about 11 % of GR's order-4+ `cw`-only rearing has no discharge. A verdict that turns on
  that share reads a gap in the discharge layer, not a threshold.
- **Rule, per species × flag, stage `any`, held-out WSGs pooled:**
  - **The verdict of record is size-adjusted** (operator, 2026-10-02): a band is habitat
    when expected ≥ 10 and the size-adjusted ratio ≥ 0.5. Expected < 10 is
    "underpowered" and reads nothing.
  - Written beside it: the unadjusted ratio and the #302 reading (expected at the
    pooled core rate ≥ 10, ratio ≥ 0.5), and the found count.
  - Spawn- and rear-staged rows are reported and decide nothing. Stage `any` also
    decides a spawning band. That is the evidence #302's spawning ladders used, apart
    from RB, and a staged floor would leave most bands underpowered. The spawn-staged rows
    sit beside it.
- **Reading the two bands together:**

  | `cw`-only | `mad`-only | Reading |
  |---|---|---|
  | habitat | not | `cw` is closer: `mad` drops habitat fish use and adds habitat they do not |
  | not | habitat | `mad` is closer |
  | habitat | habitat | each model misses habitat the other finds |
  | not | not | the models disagree only on water fish use little; the choice moves little used habitat |

  An underpowered band leaves its half of the reading open: the reading names the
  decided half (for example "cw-only habitat; mad-only open").
- **Power, before any build.** From #302's P10 anchors (held-out, stage `any`): the
  `cw`-only side is large (rearing BT 4,505 km, GR 3,893, RB 864), and the `mad`-only
  side is thin (BT 193 km, 7 found; GR 14 km, 0 found; RB 500 km, 19 found). The
  `mad`-only band is likely underpowered for BT and GR.
- **Nothing switches on this.** The verdict informs a reviewed row edit of a bundle's
  `parameters_habitat_method.csv`; it moves no group by itself.
- Under `default` and `bcfishpass` (as of this run; `default` gained width-converted
  ranges in #307), BT, GR, KO and RB had no MAD range, so on `mad` they lost all stream
  habitat by construction. That needs no score.
- **The `cw` base is not #302's.** `default_tuned` carries BT `rear_gradient_max`
  0.1349, so #302's BT `cw` rearing (12,991 km under `default`) is not this run's.
  Segments are not compared across builds; the PSCIS tie moves a segment between full
  runs.

### Results, 2026-10-03

The build ran at a clean `482c075`, in 68.2 min after the colima disk was grown (the first
attempt stopped at a full volume; nothing was dropped). It covered the 20-WSG closure,
with PARS pre-flighted first, and every invariant was asserted. The base's re-classify
under `default_tuned` reproduced its own habitat digest. KETL's access changed on the
closure recompute, as it did in #302's build. The score was run with `--floor=expected`.
Logs and outputs are in `data-raw/logs/habitat_score_300/`.

Band identity holds per WSG: `mad` km − `cw` km = `mad`-only km − `cw`-only km, within
0.01 km (the rollup's rounding) on all 23 WSG × species pairs, both flags.

**Of record (held-out, stage `any`, size-adjusted):**

| Species | Flag | `cw`-only km | Found | Expected | Ratio (size-adj.) | Ratio (unadj.) | `mad`-only km | Found | Expected | Reading |
|---|---|---|---|---|---|---|---|---|---|---|
| BT | rearing | 4,993 | 246 | 347 | **0.71** | 0.33 | 170 | 8 | 6.7 | `cw`-only habitat; `mad`-only open |
| BT | spawning | 2,752 | 225 | 325 | **0.69** | 0.47 | 145 | 6 | 14.3 (0.42) | `cw` closer |
| GR | rearing | 3,893 | 158 | 322 | **0.49** | 0.49 | 14 | 0 | 1.2 | `cw`-only not habitat; `mad`-only open |
| GR | spawning | 2,241 | 135 | 188 | **0.72** | 0.72 | 13 | 0 | 1.1 | `cw`-only habitat; `mad`-only open |
| RB | rearing | 864 | 123 | 83 | **1.49** | 1.01 | 500 | 19 | 35 (0.54) | each misses habitat the other finds |
| RB | spawning | 274 | 91 | 39 | **2.33** | 2.07 | 933 | 29 | 83 (0.35) | `cw` closer |

On held-out groups, `mad` at the landed pair keeps this much habitat against `cw`
(`habitat_change.csv`; the first build of the landed pair, which replaces #302's lower
bounds):

| Species | Rearing | Spawning |
|---|---|---|
| BT | 13,526 → 8,703 km (−35.7 %) | 8,983 → 6,376 km (−29.0 %) |
| GR | 4,705 → 825 km (−82.5 %) | 3,042 → 813 km (−73.3 %) |
| RB | 8,186 → 7,821 km (−4.5 %) | 5,522 → 6,181 km (+11.9 %) |

`cw` here is `default_tuned`'s, with BT `rear_gradient_max` 0.1349. #302's 12,991 km BT
figure was under `default`.

**The `cw`-only band is two different kinds of water, and the verdict is carried by one of
them** (`model_reason.csv`, `model_size.csv`):

- **Water with no discharge value.** For BT rearing this is 504 of 4,993 km. 433 km of it
  is edge type 1250, the main flow through double-line river polygons, and it is order 4+
  almost entirely. It holds 204 of the band's 246 locations, at 40 per 100 km against the
  core's 15. This is a gap in `fwa_stream_networks_discharge`, not a MAD threshold, and it
  is the most-used water in the comparison. The same holds for every species: GR rearing
  463 km at 14 per 100 km, RB rearing 178 km at 48, RB spawning 161 km at 53.
- **Water below the MAD minimum.** For BT rearing this is 4,459 km holding 41 locations,
  0.9 per 100 km. In orders 1–3, where most of it lies, `cw`-only rearing is used at 0.22
  of the size-matched core (42 found, 192 expected). BT spawning is at 0.14, GR rearing at
  0.18, RB rearing at 0.61 and RB spawning at 0.36.
- The order 4+ part of the band is used at or above the core rate. BT rearing is 1.31, BT
  spawning 1.36, RB rearing 3.31 and RB spawning 3.41; GR rearing and spawning are 0.77
  and 0.78.

**Reading it.**

- **By the rule fixed before the run, `cw` is closer for BT spawning and RB spawning, and
  `cw`-only habitat is used like habitat for BT rearing and GR spawning.** RB rearing
  reads both ways. GR rearing falls just short: its `cw`-only band reads 0.49.
- **What the verdict measures is mostly the discharge layer's gap on large rivers.**
  `mad` drops river-polygon main stems because they carry no discharge, and those are
  the most-used reaches. Below the MAD minimum, `mad` drops small water that fish use
  at a fifth (BT) to three-fifths (RB rearing) of the rate of size-matched core. So there
  are two separate questions. One is whether the minimum is right: it removes little-used
  water, which is what a minimum should do. The other is whether discharge exists where
  it is needed, and on main stems it does not.
- **The size adjustment mattered for BT and RB and did nothing for GR.**
  - It moved BT rearing from 0.33 to 0.71. The `cw`-only band is mostly small water,
    priced at the small-water core rate.
  - GR has almost no small-water core (30 km and no locations in orders 1–3), so every
    class merged into one group. GR's adjusted ratio is the pooled ratio, and its 0.49
    rests on no size control at all.
- **The `mad`-only side decides little.** It is underpowered for BT rearing and for GR in
  both flags. Where it is powered:
  - RB rearing's 500 km read 0.54, mostly order 1–2 water with no channel width.
  - RB spawning's 933 km read 0.35.
  - BT spawning's 145 km read 0.42.
  So `mad` adds little habitat fish use in proportion, except for the RB rearing it
  finds where width is missing.
- **Staged rows (reported, not decided).**
  - GR rear-staged locations use `cw`-only rearing at 0.89 and spawning at 0.98, above the
    any-stage 0.49 and 0.72.
  - BT and GR spawn-staged locations are too few to read.
- **KO (in-sample, PARS and KOTL)** loses 88 km of spawning under `mad` that holds
  3 locations (11.9 expected, 0.25). It is reported, and decides nothing.
- **Nothing switches.** Before any group moves to `mad`, the discharge gap on river-polygon
  main stems needs a fill (for example a `cw` fallback where `mad_m3s` is NULL, or
  discharge on edge type 1250). Without one, every species loses its most-used water on
  those reaches. The province-wide per-segment discharge estimate in the `wet` package is
  the natural source.

### Filling discharge on river-polygon main stems (#305)

**Verified:** 2026-10-06 · **Produced by:** `data-raw/discharge_fill_count.R` →
`data-raw/logs/discharge_fill_305/`, measuring the shipping SQL (`R/lnk_discharge.R`).

#300 found that `mad`'s most-used loss is edge type 1250 (main flow through double-line
river polygons) with no discharge. The fill is a bundle knob, `pipeline: discharge_fill`,
set in `default_tuned` only. With it, an edge 1250 line with no value takes, in order:

1. **`fill_upstream`**: the nearest valued line upstream on its own `blue_line_key`. Any
   edge type and any WSG qualify; the line itself never does. Discharge grows downstream,
   so this is a lower bound.
2. **`fill_downstream`**: else the nearest valued line downstream on the same line, an
   upper bound.
3. **`fill_tributary_max`**: else the largest value on any line upstream of it
   (`fwa_upstream()`), never its own `blue_line_key`. This is a lower bound, and it
   reaches a river that has no value anywhere.

The receiving river downstream is never used. The Beatton would take the Peace, orders of
magnitude larger. Other edge types are not filled.

Two gates decide where the fill runs at all:
- **Only in groups the table covers** (any valued row). Without that, in a group with no
  discharge, a stray headwater line upstream would give the Skeena's order-9 mouth in
  LSKE 0.003 m³/s (round-2 review). "No discharge" would then read as "below the
  minimum".
- **Only for groups that read discharge**: on `mad` in the bundle's method table, or under
  a rule-level `mad:`. An all-`cw` run of `default_tuned` fills nothing.

A lower bound is safe against a MAD minimum: a filled value that clears it means the true
one does. That is the test that matters for BT, GR and RB, whose maxima are open. It is
not safe against a finite maximum: `default_tuned` rearing for CH (100 m³/s), CO (40), ST
(60) and WCT (40), and WCT spawning (59.15). A filled main stem above one of those could
be admitted. No group is on `mad` for those species.

**The gap, in the 123 WSGs with any discharge** (`coverage_edge.csv`):
- Edge 1250 is 28,122 km, of which 6,243 km (22 %) has no value. The issue's "most" holds
  only province-wide, where the uncovered groups count.
- 4,152 km of it is rows absent from the table and 2,091 km is rows with a NULL value.
  Almost all of it is order 4+.
- Every edge 1250 line sits in a waterbody fundamental watershed, and the absent ones
  mostly do have a watershed in `fwa_streams_watersheds_lut` (4,098 of 4,152 km;
  `root_cause.csv`). So the loss is downstream of the lookup, in fwapg's per-watershed
  discharge step (`extras/discharge`). Those intermediate tables are not in the local
  DB, and which step drops them is not established.
- Edge 1000 NULLs (~9 % in every order) are rows with a NULL value on lines with no value
  anywhere. They are out of scope.

**Reach** (`reach.csv`):
- Of the 4,152 km of absent edge 1250 rows, the fill reaches all but 4.8 km:
  - 3,407 km by `fill_upstream`, 3,189 km of it from more than 10 km away;
  - 740 km by `fill_tributary_max`;
  - 0.1 km by `fill_downstream`.
- Of the 2,091 km of NULL-value rows, only 229 km is reached: 223 km by
  `fill_downstream` and 6 km by `fill_tributary_max`. The other 1,862 km, in 12 northern
  groups, sits on lines whose tributaries are NULL too: the discharge layer has nothing
  to offer there.

**Accuracy** (`accuracy.csv`, `accuracy_min.csv`):
- **Masking one valued line at a time says little.** Its neighbour usually shares its
  fundamental watershed: median error 0.01 %, P90 1.6 %.
- **Long gaps.** Taking the first valued line at least 10 km upstream instead (1-in-50
  sample, 1,249 lines):
  - median error −26 % and P90 77 %, under in 93 % of lines;
  - against every species' MAD minimum it never admits a line the true value would
    refuse (0 km gained);
  - it refuses a line the true value would admit on 7.7 km of 399 for BT and 40 km of
    375 for GR.
- **Tributary tier.** Median −1.6 %, P90 72 %. It is under in 64 % of lines and over in
  13 %, so it is mostly a lower bound but not always. It wrongly admits 0.56 km of 385 at
  GR's minimum, and nothing for BT or RB.

**On #300's held-out `cw`-only bands** (`band_reach.csv`, BT rearing):
- All 433 km of its edge 1250 water with no discharge is filled, and all of it clears
  BT's minimum. 103 km comes from `fill_upstream`.
- 330 km is the Beatton River in UBTN, which has no row anywhere along its line, filled
  by the tributary tier.
- GR's 330 km of Beatton clears GR's 0.97 minimum on 193 km. Its upper reaches take
  small tributaries' values.
- What stays NULL is the 71 km of non-1250 water (BT rearing): edge 1000/1100 lines with
  no value anywhere.

**Not filled on purpose.** The #302 calibration scripts (`query_habitat_thresholds_mad.R`,
`_fiss.R`) read the raw table. The ranges were set with NULL locations excluded, and a
filled main stem would add locations the calibration never saw.

**The fill off reproduces #300.** `built.csv` records each variant's fill, and a row
from before #305 has none, so it reads as raw. Re-scoring #300's schemas with the
#305 code (`312e195`) reproduces its outputs:
- **Byte-identical:** `summary`, `totals`, `habitat_change`, `model_bands`,
  `model_bands_pooled`, and the digests.
- **Numeric difference only:** `model_reason`, `model_size` and `model_verdict` differ
  by at most 7.4e-15 relative, the double-sum noise of #293.
- **New file:** `model_fill.csv`, which shows only `modelled` or no discharge.

Evidence: `data-raw/logs/discharge_fill_305/rescore300/`.

#### Re-scored with the fill (2026-10-06)

**The design** (fixed at the #305 plan gate):
- The same comparison as #300, on #300's segmentation: `score300_default_tuned` and
  `working_score300_*` are reused, and only the variants are rebuilt.
- `variants_305.csv` holds #300's four `mad` variants, renamed `*_fill`, built under
  `default_tuned`'s `discharge_fill`, with roles from `wsg_roles_300.csv`.
- The difference from #300 is the fill and nothing else. The base re-classify reproduced
  #300's habitat digest on all 12 focal WSGs.
- Build 31.5 min at `312e195`; score `--floor=expected`. Logs:
  `data-raw/logs/habitat_score_305/`.

**Of record (held-out, stage `any`, size-adjusted), against #300:**

| Species | Flag | `cw`-only km | Found | Expected | Ratio | #300 ratio | `mad`-only ratio | Reading | #300 reading |
|---|---|---|---|---|---|---|---|---|---|
| BT | rearing | 4,491 | 52 | 269 | **0.19** | 0.71 | 1.20 (underpowered) | `cw`-only not habitat; `mad`-only open | `cw`-only habitat |
| BT | spawning | 2,319 | 31 | 249 | **0.13** | 0.69 | 0.41 | differ only on little-used water | `cw` closer |
| GR | rearing | 3,611 | 101 | 409 | **0.25** | 0.49 | 0 (underpowered) | `cw`-only not habitat | same |
| GR | spawning | 1,959 | 78 | 224 | **0.35** | 0.72 | 0 (underpowered) | `cw`-only not habitat | `cw`-only habitat |
| RB | rearing | 731 | 38 | 60 | **0.64** | 1.49 | 0.54 | each misses habitat the other finds | same |
| RB | spawning | 140 | 6 | 16 | **0.39** | 2.33 | 0.35 | differ only on little-used water | `cw` closer |

**What `mad` keeps against `cw` on held-out groups** (`habitat_change.csv`):

| Species | Rearing | Spawning |
|---|---|---|
| BT | 13,526 → 9,205 km (−32.0 %; #300 −35.7 %) | 8,983 → 6,809 km (−24.2 %; #300 −29.0 %) |
| GR | 4,705 → 1,108 km (−76.5 %; #300 −82.5 %) | 3,042 → 1,096 km (−64.0 %; #300 −73.3 %) |
| RB | 8,186 → 7,955 km (−2.8 %; #300 −4.5 %) | 5,522 → 6,315 km (+14.4 %; #300 +11.9 %) |

**Reading it.**
- **#300's `cw`-favouring verdicts were the discharge gap.** With main stems filled, the
  edge 1250 water moves into the core, the core both models keep (`model_fill.csv`):
  - BT rearing's `cw`-only band keeps 52 of its 246 locations.
  - Every verdict that read "`cw` closer" or "`cw`-only habitat" (BT both flags, GR
    spawning, RB spawning) now reads "`cw`-only not habitat" or "the models differ
    only on little-used water".
- **Below the MAD minimum is where the band now sits.** For BT rearing, 4,390 of 4,491
  km is `outside_mad_range` on `modelled` discharge, used at 0.19 of the size-matched
  core. The minimum removes little-used water, as #300 found for this part of the band.
- **RB rearing still reads both ways.** `cw`-only 0.64 and `mad`-only 0.54, each with
  power.
- **What is left NULL is not main stem.**
  - The `mad_null` share is 71 km for BT rearing (10 locations), 44 km for GR and 45 km
    for RB: edge 1000/1100 lines with no value anywhere.
  - GR loses 137 km of the Beatton (4 locations) on a `fill_tributary_max` value below
    its 0.97 minimum. That is a lower bound, so the true discharge may clear it.
- **Cost, against `cw`:** `mad` still keeps less stream habitat (BT rearing −32 %, GR
  −76 %). The water it drops is now used at a fifth (BT) to a third (GR) of the
  size-matched rate. Whether to move a group is a reviewed row edit of
  `parameters_habitat_method.csv`. This informs it and moves nothing.

## `default`'s MAD ranges, converted from its width minima (#307)

`default` sized BT, GR, KO and RB streams on channel width only. Under `mad` they kept no
stream habitat at all, so comparing `cw` with `mad` inside `default` compared something
with nothing. #307 converts `default`'s own width minima to discharge, so the two models
test the same biological stream size two ways. `default_tuned` keeps #302's observed
ranges, so the contrast between biology and observation survives.

**The rule.** Each width minimum maps to the median `mad_m3s` on `fresh_default` stream
segments, defined as follows:
- stream edges 1000/1100/2000/2300, outside waterbodies;
- modelled channel width within 0.1 m of the minimum;
- discharge joined on `linear_feature_id`.

The median is floored to two significant figures, #302's rounding. Maxima stay open
(9999). A stage converts only where a stream rule inherits a size range, so KO rearing,
which is lake-only, stays NA. Producer: `data-raw/query_width_mad_equivalent.R`, run at
`f52c8f0`. It reproduces #302's ad-hoc query exactly: n 36,601 / 24,509 / 5,977, medians
0.0214 / 0.04115 / 0.2010 (`data-raw/logs/habitat_thresholds_307/`).

| Species | Stage | Width min | `default` (#307) | `default_tuned` (#302, observed) |
|---|---|---|---|---|
| BT | spawn | 2 m | **0.041** | 0.078 |
| BT | rear | 1.5 m | **0.021** | 0.078 |
| GR | spawn | 4 m | **0.20** | 0.96 |
| GR | rear | 1.5 m | **0.021** | 0.97 |
| KO | spawn | 2 m | **0.041** | 0.57 |
| RB | spawn | 2 m | **0.041** | 0.011 |
| RB | rear | 1.5 m | **0.021** | 0.019 |

Values are m³/s. `default_tuned` is stricter for BT, GR and KO and looser for RB.

**Sensitivity.** The 2 m median, 0.04115, sits 0.00015 above the floor's boundary, so a
small shift in the population (more groups in `fresh_default`, a discharge refresh)
could give 0.040. The values are pinned in the CSV and in a test, and the producer
records the population, so such a drift shows up as a diff and is not applied silently.

**Literature check.** The decision rule was fixed before the check: the cells are a width
equivalence, not a habitat-use estimate. The literature gives sizes where each species
was found using streams, so a mismatch is reported and moves no value. Against #302's
table ([above](#literature)):
- BT redds sit at spawning-time flows of 0.25–0.30 m³/s (Hagen et al. 2015). That survey
  skipped streams under 2 m by design, so it cannot bound a 2 m floor. 0.041 is below
  the use range, as a floor should be.
- GR spawning occurs at 0.21–0.25 m³/s freshet flow in a constructed channel (House
  2021). The 4 m floor's 0.20 sits just under it, and `default_tuned`'s 0.96 sits above
  it. Of the two, the converted value is the one consistent with the only small-stream
  record.
- KO spawning occurs at MAD 0.28–0.40 m³/s, where migration sets the upstream limit, not
  flow (AMEC 2015). 0.041 is well below it, as for BT.
- RB spawns and rears at MAD of about 0.1 m³/s (AMEC 2015), and 0+ fish are found at 0.028
  late-summer flow (Bustard 1988). 0.041 and 0.021 sit below or at those values, while
  the observations (`default_tuned`) go lower still.
- Woll et al. 2017's Alaskan width relation gives 0.021 / 0.040 / 0.17 m³/s at 1.5 / 2 /
  4 m, an independent check on the BC medians.

**Before and after** (NATR and ADMS, on held segmentation;
`data-raw/logs/habitat_thresholds_307/README.md`):
- **`cw` moves nothing.** Every species' `streams_habitat` digest matches main.
- **Under `mad` the four species get stream habitat back.** For example, NATR BT goes
  0 → 1,487 km spawning and 0 → 2,525 km rearing off waterbodies. CH, CO and SK on ADMS
  are unchanged, digest for digest.
- **Within `default`, `mad` and `cw` now agree to about 5 %** after connect:
  - NATR: BT spawning −4.5 %, rearing +1.5 %; GR −5.4 % / −4.8 %; RB −4.7 % / +3.3 %.
  - ADMS: BT +1.7 % / +5.0 %; RB +0.8 % / +3.6 %.

  That agreement is the width-equivalence holding, not a validation. It sits against
  `default_tuned`'s −32 % BT and −76 % GR stream rearing on held-out groups (#305).
- **The lake and wetland buckets shrink under `mad`.** Once a species has a rear range,
  fresh gates `lake_rearing` / `wetland_rearing` on it, and on discharge many lines
  inside lakes and wetlands sit below 0.021. NATR BT lake 521 → 304 km and wetland
  1,287 → 710 km; RB is similar. The `rearing` flag itself is not gated this way. **This
  is an artifact, not biology.** The test sizes a lake by the flow through it, when a
  lake's size is its area, and bcfishpass never does it (`smnorris/bcfishpass@f8db4b9`:
  SK lakes on area, CO wetlands with no size test). The buckets also ignore spawning
  connectivity: in `fresh_default`, 16,651 of 16,652 BT `lake_rearing` rows are not
  `rearing`. Fixes: fresh#240 (area-only buckets, connected to spawning) and #310
  (`default`'s lake and wetland rules). *Update 2026-10-07 (#311):* link now pins fresh
  v0.39.0, so the size gate is gone; the buckets are polygon area plus the rule's floor
  under either model ([below](#the-wetland-floor-on-rearing-311)). Connectivity landed
  in #310 ([below](#lake-and-wetland-rearing-connected-to-spawning-310)).

**Not done here.**
- `default`'s CH, CO, SK and ST minima come from bcfishpass and are mostly untraceable
  (#302). Converting them the same way would give CO spawning 0.041 against its 0.164,
  and would move existing `default` outputs; that is a separate decision.
- `default` sets no `discharge_fill`, so a line with no `mad_m3s` still fails every MAD
  test. NATR has none on its stream edges.
- `default_extrabreaks` and `default_rearbreaks` keep the old CSV. They are `cw`
  segmentation experiments.
- #302's ladders (`--base=default`) regenerate only at v0.58.0 (`8cb4822`). Each rung
  sets `*_mad_max = 9999`, which `default` now carries, so the build stops with "variant …
  equals default". Their scores are unaffected.

## The wetland floor on `rearing` (#311)

**Verified:** 2026-10-07 · **Issues:** #311; fresh#237 (the floor in the rear predicate),
fresh#240 (area-only buckets) · **Produced by:** `data-raw/logs/wetland_floor_311/`
(`run.R`, `summarise.R`, `obs.R`; README with the full tables)

**What changed.**
- **fresh v0.38.0 gates `rearing` on a W rule's `wetland_ha_min`.** Before, only the
  `wetland_rearing` bucket used it.
- **link pins v0.39.0**, so `default*` rearing narrows with no config change.
- **The 1050/1150 wetland-flow rear rule had no floor of its own.** On NATR BT it held
  26.6 km of rearing in wetlands under 1 ha.
- **Operator call (2026-10-07): a declared `rear_wetland_ha_min` bounds both wetland
  rear rules.** `lnk_rules_build()` therefore puts it on the wetland-flow rule too, as a
  W rule. Mainlines (1000/1100) in sub-floor wetlands still rear through the stream rule,
  which has no waterbody test (0–0.62 km per floored species under C). That rule comes after the polygon rule, which keeps the first W rule (fresh's
  bucket and `requires_connected` anchor) the same.
- **Floors in `default`:** 1 ha for BT, CH, RB, ST and WCT; 0.5 ha for CO. *Update
  2026-10-07 (#310): CO's floor is gone ([below](#lake-and-wetland-rearing-connected-to-spawning-310)).*

**Measured** on one segmentation per WSG (NATR, PARS, BULK, ADMS). Three runs:
- **A:** fresh 0.36.2 with the old rules.
- **B:** 0.39.0 with the old rules.
- **C:** 0.39.0 with the floored rules.

What each step does:
- **A → B: fresh alone.** It reproduces five of fresh's six published numbers exactly; the sixth, sub-floor wetland-flow km, fresh gives as an upper bound (26.6 here, ~26.4 there). `rearing`
  loses at most 75 segments / 3.6 km (PARS RB), and no observation species-location. The buckets
  roughly double: NATR BT lake goes from 310 to 521 km and wetland from 684 to 1,287 km.
- **B → C: the floor on the wetland-flow rule.**
  - Wetland-flow rearing in sub-floor wetlands goes to 0.
  - Rearing loss is largest on NATR RB (−46.7 km), NATR BT (−34.1 km), PARS RB
    (−28.0 km), PARS BT (−26.2 km) and BULK ST (−23.8 km).
  - Part of the loss is on other edges: rearing that `cluster_rearing` no longer
    connects to spawning once the sub-floor wetland link is gone. That is 17.4 of BULK
    ST's 23.8 km, and 6.8 of NATR BT's.
  - Observations: 3 of 2,265 species-locations on rearing are lost.
  - Against bcfishpass rearing km, the floor moves the departure by at most 1.1 points.
    NATR BT goes from +13.8 % to +12.7 %, PARS BT from +1.7 % to +0.6 %.

**Reading.** Across the four WSGs the floor removes 198.8 km (2,078 segment-species) of
rearing, and observations sit on 3 of those species-locations. So fish observations barely use
the small-wetland rearing it removes. It also cuts some upstream rearing through
connectivity. The floor's value itself (1 ha) was not calibrated here. BT's notes cite
beaver complexes, which are often small, and those are exactly what the floor removes.
Calibrating it on observations is open.

**Caveats.**
- Province-wide, 40 edge-1050 lines (about 6.6 km) have no `waterbody_key`. The W-typed
  rule drops them.
- In `edge_types = "categories"` mode the wetland-flow rule matches no FWA line at all.
  That predates #311; no shipped bundle uses categories.


## Lake and wetland rearing connected to spawning (#310)

**Verified:** 2026-10-07 · **Issues:** #310; fresh#240 (`requires_connected: spawning` on the
first rear L / W rule) · **Produced by:** fresh `data-raw/logs/bucket_connected_240/` (the
distance ladder); `data-raw/logs/lake_connected_310/` (this change on one segmentation)

**The question.** In `default`, a species' `lake_rearing` / `wetland_rearing` bucket kept every
accessible polygon over its size floor, whether or not that species spawns anywhere near it.
fresh v0.37.0 lets the first rear L / W rule keep a polygon only where same-species spawning lies
on it, or within `connected_distance_max` metres up- or downstream. The bundle has to state the
distance (operator, 2026-10-06: "reasonable number stated in rules").

**What the distance is for.** It is a test of whether a polygon sits in a species' spawning
network, not a cap on how far fish move. Movement distances in the literature are all longer:
- juvenile coho move up to 38 km downstream to winter rearing in beaver ponds, off-channel ponds
  and side channels with the first fall freshets (Scarlett and Cederholm 1984, in Pollock et al.
  2004), and move from the main river into ponds in autumn (Peterson 1980, 1982, in Swales and
  Levings 1989);
- adfluvial bull trout, rainbow trout and grayling rear in natal tributaries and move to lakes,
  with spawning migrations of tens of kilometres (e.g. Lake Billy Chinook / Metolius bull trout;
  Francois Lake rainbow recruitment from its tributaries).

Any cap under ~10 km is therefore conservative for every species here. bcfishpass's only
precedent is SK's 3 km between lake and spawning, which is a spawning-side test.

**The ladder** (fresh, NATR BT, buckets area-only, km of polygon lines):

| distance | lake km | wetland km |
|---|---|---|
| unconnected | 521.4 | 1,287.3 |
| 0.5 km | 486.6 | 870.3 |
| 1 km | 495.9 | 954.9 |
| 3 km | 514.5 | 1,190.9 |
| 10 km | 517.4 | 1,265.3 |

Above 3 km the lake curve is flat (+0.6 %); wetlands still gain 6 % from 3 to 10 km.

**Value: 10,000 m for every species, lakes and wetlands** (`rear_lake_connected_distance_max`,
`rear_wetland_connected_distance_max` in `configs/default/dimensions.csv`). Reasons:
- it is the largest distance measured, and still under every movement distance above;
- the literature gives no basis for a different number per species, so one number keeps the
  departure legible;
- per-species and per-type columns exist so a calibrated value can replace it cell by cell.

**Applies to** every species in `default`'s additive rear branch with lake or wetland rearing:
BT, CH, CO, GR (lakes only), RB, ST and WCT (operator, 2026-10-07). CT and DV carry the same
values, but they are inert: neither has a row in the bundle's thresholds CSV, so
`lnk_rules_build()` emits no rules for them. SK and KO are not changed: their spawning is
anchored to their lake rearing, so a rearing test anchored on spawning would be circular
(the builder refuses it).

**Hectares and centreline km follow different tests.** The distance filters only the
`lake_rearing` / `wetland_rearing` bucket. Lake centrelines reach `rearing` through the L rule
and then go through the rearing cluster pass like any stream: kept when spawning lies anywhere
upstream (no distance), or downstream within the bridge limits. RB has
`cluster_rearing = FALSE`, so its lake centreline km follow no spawning test at all. The
divergence therefore runs both ways (ha kept with km dropped, and km kept with ha dropped);
`data-raw/logs/lake_connected_310/` counts both.

**Measured** on one segmentation (ADMS, NATR; #311's scratch builds re-classified at main and at
the branch; `data-raw/logs/lake_connected_310/`):
- Spawning is unchanged for every species, and SK / KO are row-identical.
- Rearing rises by the lake centrelines:
  - +237 to +255 km per species on ADMS (SK and KO: 0);
  - +408 to +525 km on NATR (BT +525.4, of which 508.6 are lake lines and 10.5 are stream rearing
    that lake lines reconnect to a cluster).
- Adams Lake alone holds 211.6 km of ADMS's lake km. 148.8 km of that is 1450 connection lines
  joining tributaries to the main flow across the lake, so lake km run at about three times the
  main-flow length. Against bcfishpass, ADMS CH goes from +14 % to +91 % rearing and CO from
  +3 % to +75 %. Whether connection lines belong in lake km is open.
- The buckets move little at 10 km:
  - NATR BT lake 20,826 → 20,739 ha and wetland 17,128 → 16,772 ha;
  - CO on ADMS gains 52 lakes under 2 ha.
- Lakes where ha and km disagree are rare (at most 14 polygons per species).

**Uncalibrated.** Neither the value nor the per-species sameness is scored on observations.
