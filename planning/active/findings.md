# Findings — Score the discharge (mad) habitat model against observations (#300)

## Issue context

**If done:** we know, per species, where classifying on `mad` instead of `cw` adds or drops habitat that fish actually use, before any bundle switches a group. **If never:** switching a group to `mad` is a guess. Since #302 that guess has a measured downside: at `default_tuned`'s ranges a `mad` group keeps at least a third less BT stream rearing than `cw`, and at least four-fifths less GR, on #302's held-out groups.

## Problem

Since #286, a bundle can put a watershed group on the discharge model (`mad`). The two models classify different segments, and nothing yet says which is closer to where fish are observed. Fewer habitat segments under `mad` is not by itself a defect. It may be less conservative, or more realistic, and the evidence should decide.

## What #299 and #302 settled (2026-10-02)

- **The validator scores a `mad` group on discharge** (#299).
- **BT, GR, KO and RB have MAD ranges in `default_tuned`** (#302; `default` and `bcfishpass` still have none, so under them those species lose all stream habitat on `mad` by construction). Values and evidence: `research/habitat_thresholds.md`, "MAD (discharge)".
- **The scoring harness already does model comparison** (#302, `data-raw/habitat_variants_build.R` / `_score.R`, `data-raw/habitat_score/README.md`): a variant's `model` column puts its WSGs on `mad` through a per-bundle method table, on one shared segmentation, and an *anchor* step from the `cw` base to a `mad` variant reports both directions (what `mad` keeps that `cw` drops, and the reverse).
- **A partial answer exists for BT, GR and RB.** #302's anchor bands (`data-raw/logs/habitat_score_302/bands_pooled.csv`, held-out, `stage = any`) give the cw-only and mad-only habitat at the P10 rungs. The `removed` side (cw only) is used at 0.37–0.48 (BT), 0.50–0.73 (GR) and 1.06–1.07 (RB) of the core rate. **But their core is the `mad` rungs, not the habitat both models keep**, so they do not answer this issue's question as posed.
- **Stream size and sampling effort are confounded** in a per-km density comparison when the two sides differ in stream size, which a model swap does. #302 flagged it and did not resolve it.

## Proposed Solution

- **Harness changes the build needs** (found by reading the code, not yet built):
  - **A model-only variant.** Today only the base may leave `column` empty, and every other variant must change at least one threshold cell. A `mad` variant with no cell change is what this issue compares.
  - **A base bundle other than `default`.** Both scripts hard-code `lnk_config("default")`. Comparing on `default_tuned` (which gives BT, GR, KO and RB a range) needs `--base=default_tuned`.
  - **A core of "habitat both models keep"** for a model-only comparison (`cw` base ∩ `mad` variant), with the decision on the two exclusive bands rather than a threshold walk.
- **Classify held-out groups under both models** on one shared segmentation. Only groups with discharge in `fwa_stream_networks_discharge` can be used (123 WSGs in local fwapg; e.g. BULK has none). #302's held-out set (REVL, ELKR, KOTR, UARL, MURR, UBTN, LHAF, SIML, OKAN, KETL; 20-WSG closure) and its `score302_*` / `working_score302_*` schemas can be reused if built at a compatible HEAD.
- **Score with `lnk_habitat_validate_band()` under a rule fixed before the run**: per species and stage, observation locations per km on the segments only one model keeps against the core both keep.
- **Control for stream size** before reading the ratio as habitat: split the core by stream size (as #284's elevation classes split elevation), or report the comparison within size classes. Without it the verdict may read sampling effort.
- **Report per species and stage**, including the species `default` gives no MAD range, which lose stream habitat under `mad` by construction there.
- **Groups outside the discharge coverage cannot be scored** until per-segment discharge exists there. A province-wide per-segment discharge estimate is in progress in the `wet` package.

Depends on #299 and #302 (both closed). Relates to #284, #286; fresh#237 (`wetland_ha_min` ignored by the rear predicate) affects wetland rearing under both models alike.

## Errors Encountered

| Error | Resolution |
|-------|------------|
