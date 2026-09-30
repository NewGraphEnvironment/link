# Habitat thresholds — CH and BT gradient and channel width

**Verified:** 2026-09-27 · **Issues:** #284 (this), #290 (the pooling tracker), #283 (the validator, [`habitat_validation.md`](habitat_validation.md)), #282 (`default_tuned`) · **Produced by:** `data-raw/query_habitat_thresholds_obs.R`, `data-raw/query_habitat_thresholds_fiss.R` → `data-raw/logs/habitat_thresholds_284/`; literature review archived with #284's PWF (`literature.md`) · **Status:** candidates set in `default_tuned`, **unscored**

## Verdict

| Species | Threshold | `default` | Candidate (`default_tuned`) | Confidence |
|---|---|---|---|---|
| CH | `spawn_gradient_max` | 0.0449 | **keep** | medium |
| CH | `rear_gradient_max` | 0.0549 | **keep** | medium |
| CH | `spawn_channel_width_min` | 4 | **keep** | medium |
| CH | `rear_channel_width_min` | 1.5 | **keep** | medium |
| CH | `spawn_gradient_min` | 0 | **keep** | high |
| BT | `spawn_gradient_max` | 0.0549 | **keep** | medium |
| BT | `rear_gradient_max` | 0.1049 | **0.1349** | high |
| BT | `spawn_channel_width_min` | 2 | **keep** | medium |
| BT | `rear_channel_width_min` | 1.5 | **keep** | medium |
| BT | `spawn_gradient_min` | 0 | **keep** | medium |
| BT | `cluster_bridge_gradient` | 0.05 | **keep** | medium |

One value moves: BT rearing gradient loosens. Every other threshold the observations
argued against was vetoed by the literature. `spawn_gradient_min` and
`cluster_bridge_gradient` live in `parameters_fresh.csv`; both are kept, so
`default_tuned` still inherits that file from `default`.

"Unscored" means the candidates have not yet been run against the observation
validation (#283). Scoring can overturn any row, including a "keep".

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
