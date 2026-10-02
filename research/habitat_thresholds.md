# Habitat thresholds — gradient, channel width and discharge

**Verified:** 2026-09-29 (CH/BT gradient and width), 2026-10-02 (MAD) · **Issues:** #284 (gradient and width), #302 (MAD, [below](#mad-discharge-ranges-for-bt-gr-ko-and-rb-302)), #300 (`cw` against `mad`), #290 (the pooling tracker), #283 (the validator, [`habitat_validation.md`](habitat_validation.md)), #282 (`default_tuned`); spawned knowledge#28 (habitat weights) · **Produced by:** `data-raw/query_habitat_thresholds_obs.R`, `data-raw/query_habitat_thresholds_fiss.R` → `data-raw/logs/habitat_thresholds_284/`; step 5 by `data-raw/habitat_variants_build.R` and `data-raw/habitat_variants_score.R` → `data-raw/logs/habitat_score_284/`; literature reviews archived with #284's and #302's PWFs (`literature.md`); MAD by `data-raw/query_habitat_thresholds_mad.R` → `data-raw/logs/habitat_thresholds_302/` and the same scoring scripts → `data-raw/logs/habitat_score_302/` · **Status:** BT `rear_gradient_max` 0.1349 **scored and held**; MAD ranges for BT, GR and RB **scored** (the rule refused loosening past P10 except RB spawning; size confound open), KO unscored; every other row unscored

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
none in `default` and `bcfishpass`), so in a `mad` group
fresh fails every inheriting stream rule and they keep only waterbody habitat. The
operator's direction (#299 plan gate, 2026-10-02) was to tune and add the ranges.

**Nothing changes in any output until a group is moved to `mad`.** Every shipped bundle
is all `cw`, so the ranges land in `default_tuned` without moving a segment. The only
before/after evidence is the scoring harness, which puts the held-out groups on `mad`.

### Verdict

| Species | Threshold | `default` | `default_tuned` | How |
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
held-out WSGs at least −33 % for BT and −82 % for GR, and −4 % for RB.** Stream size and
sampling effort are not separated; see "Results".

### Candidates (Phase 1, before scoring)

| Species | Threshold | `default` | Rule value | Evidence | n | `cw` equivalent |
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
  Neither model tests order, so it sides with neither. Each segment of the base network
  is core, `cw`-only or `mad`-only, with its order class.
  - **Expected** locations in a band = Σ over classes of band km × the core's rate in
    that class, the core's rate pooled over the held-out WSGs. A segment with no stream
    order is its own class; a class with no core km takes the core's pooled rate. Both
    are reported if they occur.
  - **Size-adjusted ratio** = locations found ÷ expected.
- **Rule, per species × flag, stage `any`, held-out WSGs pooled:**
  - **The verdict of record is size-adjusted** (operator, 2026-10-02): a band is habitat
    when expected ≥ 10 and the size-adjusted ratio ≥ 0.5. Expected < 10 is
    "underpowered" and reads nothing.
  - Written beside it: the unadjusted ratio and the #302 reading (expected at the
    pooled core rate ≥ 10, ratio ≥ 0.5), and the found count.
  - Spawn- and rear-staged rows are reported and decide nothing.
- **Reading the two bands together:**

  | `cw`-only | `mad`-only | Reading |
  |---|---|---|
  | habitat | not | `cw` is closer: `mad` drops habitat fish use and adds habitat they do not |
  | not | habitat | `mad` is closer |
  | habitat | habitat | each model misses habitat the other finds |
  | not | not | the models disagree only on water fish use little; the choice moves little used habitat |

  An underpowered band leaves its half of the reading open.
- **Power, before any build.** From #302's P10 anchors (held-out, stage `any`): the
  `cw`-only side is large (rearing BT 4,505 km, GR 3,893, RB 864), and the `mad`-only
  side is thin (BT 193 km, 7 found; GR 14 km, 0 found; RB 500 km, 19 found). The
  `mad`-only band is likely underpowered for BT and GR.
- **Nothing switches on this.** The verdict informs a reviewed row edit of a bundle's
  `parameters_habitat_method.csv`; it moves no group by itself.
- Under `default` and `bcfishpass`, BT, GR, KO and RB have no MAD range, so on `mad`
  they lose all stream habitat by construction. That needs no score.
