# Findings — Break streams at a fish observation only where "observed upstream" changes: the top observation per species per line (#396)

## Issue context

**If done:** streams are cut at a fish observation only where it changes what a segment reports: the farthest-upstream observation of each species on each stream line. Far fewer segments, so every run is faster, and segment gradients stop depending on where people sampled. **If never:** every observation keeps cutting the stream, so heavily sampled streams carry many short segments with noisy gradients, and the gradient a habitat rule sees at a fish site is shorter-reach, and noisier, *because* a fish was recorded there.

## Problem

`lnk_pipeline_break()` cuts the network at every observation position (`<schema>.observations_breaks`, the first break source), as bcfishpass does. #326 (v0.69.0) reduced the gradient breaks to the places a present species' access changes; observation breaks were left as they were.

Only one thing reads an observation break: `access_<sp>` code 2, "accessible, and the species is observed upstream" (`R/lnk_pipeline_access.R`), against code 1, "accessible, not observed upstream". Barrier lifts count observations point against point (`fwa_upstream`, `lnk_barrier_overrides()`), so they need no break. Neither the mapping code (`accessible` comes from the barrier flags, `R/lnk_pipeline_mapping_code.R`) nor the habitat gate (`access = 0` against `> 0`) tells 1 from 2.

Two costs follow from cutting at every observation:

- **Speed.** Every observation position is a cut, so a well-surveyed stream is cut many times. Segments drive the cost of classify, access, the recompute and the persisted tables.
- **Gradient accuracy.** A segment's gradient is computed from its own geometry (`fresh::frs_col_generate()`), so a short segment reads a noisy gradient. A habitat-threshold tuning study measured the effect at fish-sampling sites: on its stream branch 86 % of visits that caught fish sit on a segment starting at the visit, against 10 % of empty ones; the median segment is 113 m long for visits with fish and 305 m for empty ones. So the gradient a rule is applied on at a site depends on whether fish were found there.

## Proposed

Cut at an observation only where code 2 can change. On a stream line, "species observed upstream" can only go from no to yes, once per species: at that species' farthest-upstream observation on the line. Below it the line already reads yes; above it the only way to read yes is through a tributary, which joins at a confluence where FWA already cuts.

1. **Keep the top observation per `(blue_line_key, species)`**, the largest `downstream_route_measure`, and break at the union of those positions. Per species, not per line: one top per line would drop the flip of a species whose top observation is lower. `default` only: the `bcfishpass` config keeps every observation break, as bcfishpass cuts.
2. **Fix what reads every observation as a segment start.** `lnk_habitat_validate()` joins each observation to the segment starting at it (99 % sit within 1 m of a boundary today); that becomes a measure-overlap join, as `data-raw/habitat_diff_segments.R` already does.

## Decided (operator, 2026-10-27)

1. **Code 2 stays.** The observed / not-observed distinction is wanted in outputs, so observation breaks stay, reduced. "No observation breaks at all" is only a fallback (below), and question 4 confirms who reads code 2 rather than deciding whether to keep it.
2. **`default` only.** The `bcfishpass` config keeps every observation break, so the parity instrument cuts as bcfishpass does.
3. **The top observation per species per line.** On each `blue_line_key`, each species keeps its own farthest-upstream observation, and lower observations of the same species on that line stop cutting. One top per line would wrongly read a species "not observed" between its own top and a higher one of another species.

## Questions this answers before building (measured, on several groups)

Groups: at least one heavily surveyed (many observations per line), one sparse, and one with salmon and residents both present.

1. **How many cuts go?** Observation break positions today against the top-per-species-per-line set, and the segments each produces.
2. **How much faster?** The modelling and recompute minutes of those groups, both ways.
3. **How much of the sampling bias is left?** Segment length (and gradient against the Freshwater Atlas line's) at visits with fish against visits without, both ways. The top observation per line still cuts at some fish sites.
4. **Who reads code 2?** List every reader of `access_<sp>` = 2 against 1 (the export, the QGIS styles, any report), so the change keeps each of them working.
5. **Is the remaining redundancy worth removing?** A line's top observation is redundant when the species is also observed up a tributary that joins above it. Count those; remove them only if the count is material (it needs an upstream walk).
6. **Do the outputs move only where expected?** Access, mapping codes and habitat flags against the current build: the expected change is segment boundaries and the gradients of the pieces that merge; any change in which streams are accessible is a defect.

## Options if question 3 shows the bias is still material

- **The pieces inherit their parent segment's gradient** where an observation cuts, instead of recomputing it from the short piece (a change to how fresh generates `gradient`).
- **No observation breaks at all**, with code 2 read at segment resolution (a segment holding an observation reads "observed upstream" along its whole length). Decided against as the main path (decision 1); kept only if the reduced breaks still leave material bias.

## Acceptance

- `default` cuts at the top observation per species per line; the `bcfishpass` config is unchanged, and its parity unchanged.
- Code 2 is unchanged on every segment against the current build, read at the positions that still break.
- `lnk_habitat_validate()` scores the same observations as before (counts per bundle and species unchanged).
- The measured answers to questions 1 to 6 are in `research/`, with the evidence under `data-raw/logs/`.

Related: #326 (gradient breaks), #283 (the validator), #294 (observation positions as threshold evidence).



## Exploration (2026-10-28, plan mode, before the baseline)

- `.lnk_pipeline_break_obs()` (`R/lnk_pipeline_break.R:144`) builds `observations_breaks` as `SELECT DISTINCT blue_line_key, round(drm) FROM <schema>.observations`; the table feeds `frs_break_apply()` only. `lnk_pipeline_access()` walks `<schema>.observations` itself (`R/lnk_pipeline_access.R:207`, `frs_network_features(direction = "upstream", include_equivalents = TRUE)`), so code 2 does not read the breaks table. The recompute (`R/lnk_access.R`) passes `observations = NULL` and preserves the prior 2 in merge mode.
- Readers of `access_<sp>` in this repo all test `IN (1, 2)` or `> 0`: `R/lnk_rollup_wsg.R:120`, `R/lnk_compare_rollup.R:232`, `R/lnk_habitat_validate.R` (`not_accessible`), `data-raw/parity_crosssection.R:203`, `data-raw/query_habitat_thresholds_mad.R:201`, `data-raw/wsg_vignette_data.R:124`. Mapping code reads `has_barriers_<sp>_dnstr`; the export reads flags and `access_gradient_max`. No `.qml` / `.sld` in the repo.
- The validator already falls back to the containing segment (`R/lnk_habitat_validate.R:874-895`).
- Cheap probe on local fwapg (`bcfishobs.observations`, no presence filter, no exclusions): province 81,264 positions → 40,159 top-per-species-per-line (49 % kept). ELKR 2,269 → 601; BULK 1,253 → 682; PARS 764 → 361; LKEL 201 positions (sparse). Segment change is smaller than the position change where a top coincides with another break.
- m4 dev schemas: `fresh_default` holds PARS, LKEL, FINA, PCEA at `21e0fea2` (post-#326); `fresh` holds the 11-group bcfishpass cross-section at the same code (`segmentation_326/round2`).
- Config knob pattern: `.lnk_config_pipeline_check()` (`R/lnk_config.R:386`); `config.yaml` is in `config_hash`.
- FISS absences come from the private `knowledge` repo via `hv_fiss_absences()` (`data-raw/habitat_validate_inputs.R`, `LNK_KNOWLEDGE_DIR`).

## Errors Encountered

| Error | Resolution |
|-------|------------|
