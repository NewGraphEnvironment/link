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

## Phase 1: the cut set, measured before building (2026-10-28, m4 local fwapg)

Producers in `data-raw/logs/observation_breaks_396/`: `build_obs.R` builds `default`'s observation set with the pipeline's own `.lnk_pipeline_prep_observations()` (default presence, exclusions) into `zz396_cuts`; `cuts.sql`, `province.sql`, `code2_class.sql`, `redundancy.sql` read it. Outputs beside each (`*.csv`).

**A position cuts only when it sits more than 1 m from both ends of the segment it lands in** (`fresh::frs_break_apply()`, fresh 0.43.0 `R/frs_break.R:620-622`), and observations are the first break source. So "removes no segment" means within 1 m of an FWA segment end, another source's position or a kept top, not "rounds to the same metre" (the plan's wording); the SQL uses the 1 m rule. The other sources come from `working_<wsg>`, which on m4 holds the `bcfishpass` build (PARS 43,776 segments, as in `fresh`), so the segment estimate is approximate; Phase 4 counts exactly.

| group | observations | positions | tops | kept | positions adding a segment today | removed positions saving a segment |
|---|---|---|---|---|---|---|
| PARS | 1,018 | 593 | 244 | 41.1 % | 570 | 337 |
| LKEL | 511 | 188 | 111 | 59.0 % | 156 | 66 |
| BULK | 2,887 | 1,185 | 585 | 49.4 % | 1,081 | 552 |
| ELKR | 3,563 | 1,923 | 431 | 22.4 % | 1,817 | 1,426 |
| province | 232,773 | 63,282 | 28,876 | 45.6 % | | |

The province figure is on `default`'s presence filter (each record by its own group), with tops taken per group as each build takes them (review round 1), so it is lower than the exploration probe's unfiltered 81,264 → 40,159. Review round 1 also found the segment column undercounting: two observation positions 1 m apart both cut in one `frs_break_apply()` call, so a removed position near a kept top still saves a segment (BULK 550 → 552, ELKR 1,423 → 1,426).

**The 1 → 2 class is small** (`code2_class.csv`): pieces that read "not observed" before and "observed upstream" after, because a kept top's segment swallows a removed break above it and the species is not observed up any tributary above. PARS 0; LKEL 1 piece, 0.25 km (CO); BULK 17 pieces, 3.36 km over eight species; ELKR 16 pieces, 6.37 km (BT 2.29, CT 1.73, DV 2.35).

**Question 5, tributary redundancy** (`redundancy.csv`): 34 / 19 / 103 / 86 species-tops (PARS / LKEL / BULK / ELKR) have the species observed up a tributary joining above them. Removing them would drop 25 / 8 / 68 / 71 more positions, 4 to 12 % of today's positions on top of the 41 to 78 % already removed. Not built: decision 4 leaves materiality to the operator, and this reads as a modest second step needing an upstream walk per build.

**Question 4, readers** (`readers_code2.md`): nothing in link tells 2 from 1 (every reader is `IN (1, 2)`, `> 0` or `= 0`). QGIS styles and project files in the sibling repos read bcfishpass's text `model_access_<sp>`, not link's integer. bcfishpass's own `aw_linear_summary()` sums `access_<sp> = 2` km; it runs on bcfishpass's tables, and link's `bcfishpass` config keeps every observation break.

## Errors Encountered (resume session)

| Error | Resolution |
|-------|------------|
| 19 errors in `test-lnk_habitat_validate.R` during the full suite | A second run of the same file was started beside it; both use the fixture schema `zz_lnk_validate_probe`. Never run a live-DB test file beside the suite. The file alone passes 433 / 433. |
| FISS absence sites cover none of the four planned groups (COTR, LNTH, PINE, UNTH, UPCE only) | UPCE added to the `default` builds for question 3 |

## Code-check round 2: the premise of the tops (2026-10-28)

- **A species' own top break never changes its own code.** fwapg's `fwa_upstream` with `include_equivalents` counts a same-line record upstream when `drm_b > drm_a` or `abs(drm_a - drm_b) <= tolerance` (1 m), against the segment's start. So the segment starting at the top reads 2, and a species turns to 1 at the first cut more than 1 m above its top. Kept tops serve as that cut for species recorded only below them. The reviewer's further claim (`top_per_species` equals no observation breaks) is wrong: with X at 100 and Y at 300, the 300 cut turns X to 1 above it, which no-breaks does not.
- **The exact set** (per species, the lowest record of any species more than 1 m above its raw top) keeps every flip where `all` puts it and holds 3 to 31 % of positions, against 17 to 59 % for the tops (`exact_set.csv`). Not built; it goes back to the operator, recommended.
- **Whole-segment flips next to a barrier:** a barrier 1 to 1.5 m above a removed observation cut. #349's metre-rounding class; `pre_post_diff.R` splits them out (`*_near_barrier`, 3 m window).
- **`break_order` omission:** only `subsurfaceflow` is read off it for access; roxygen corrected.

## Code-check round 3: the mechanism behind rounds 1 and 2 (2026-10-28)

- **Shared assumption:** removing an observation break only deletes a boundary at the record's raw position. Three 1 m rules stack instead: metre rounding against raw measures in the walk, a later source cut only more than 1 m from the current ends (so a removed observation cut releases a later break within 1 m, or a moved cut suppresses one), and the walk's 1 m tolerance. Verified by hand on the reviewer's case (X raw top 500.2, Y non-top at 501.1, crossing at 502.3): `all` reads X = 2 on [501, 800], `top_per_species` X = 1 on [502, 800], so 2 → 1 on 298 m.
- **Acceptance restated as one rule:** every access or `has_barriers` change is either 1 → 2 on a segment starting at that species' raw top (between raw_t − 1.5 and raw_t + 1), or has a segment start within 3 m of a removed observation position. Anything else is a defect (`pre_post_diff.R`, `km_change_elsewhere` must be 0). This replaces round 2's barrier-table window, which read crossings and lifted barriers too.
- `code2_class.sql` now compares against the raw top; `exact_set.sql`'s claim narrowed to near-exact with an upper-bound count; `cuts.sql` columns renamed to what they count (values unchanged); `bcfishpass/config.yaml`'s `break_order` comment corrected. `code2_class.csv` is re-run after the builds, when the working schemas hold the runs' builds.

## Code-check round 4: the acceptance becomes a direction rule (2026-10-28)

- `near_removed` was tautological: every merged BEFORE segment starts at a removed position, so it excused any change on any merged segment. A merge below a tributary mouth also turns 1 → 2 with no 1 m rule at all.
- **The control now is exact:** both builds give the walk the same inputs, so codes depend only on a segment's start, and both walk tests are monotone in it (record upstream when `m >= start - 1`, barrier downstream when `b <= start + 1`; segments never span a confluence). AFTER start lower ⇒ access only rises and `has_barriers` only goes true → false; higher ⇒ the reverse; same ⇒ no change. `pre_post_diff.R` counts violations (`n_violation`, must be 0).

## Code-check round 5: the direction rule holds (2026-10-28)

- Verified against fwapg, fresh and link: the barriers are located on FWA features before any break, lifts are point against point, the walk reads only the segment's start, and every ltree branch is constant within a feature. Access is `blocked ? 0 : observed ? 2 : 1`, and the merge keeps it monotone. So `n_violation` is an exact control.
- Round 4's tributary-mouth case was impossible: FWA ends a feature at every confluence, and the segment starting at a confluence does not count the tributary (`wscode_b <@ localcode_a`). I accepted it without probing it against a sentence I had just written. Dropped from the RUNBOOK, research and `code2_class.sql`.
- `pre_post_diff.R` now writes `n_violation` and stops when it is above 0.
