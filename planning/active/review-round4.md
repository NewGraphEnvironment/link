# Code-check round 4 (#396): observation breaks

Read only. Nothing was run and no database was touched.

## Checklist read

- **code-check.md**: the prose of the H3s under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers; Restore the bug and prove the guard fires; A shared working tree; A wrapper's exit is not the work, and the shorter remaining ones by their opening paragraphs). Table rows skipped. The H3s under "Rules that stand alone", Security, and Spreadsheets/PDFs were not read: they cover tools this diff does not use.
- **code-check-r.md**: only the sections whose index lines name what this diff uses: Postgres row order; `sprintf("%g")` into SQL; `information_schema` lookup by literal name; Rscript reads a script as it runs; `function(...)` mock; testthat `error` against `failed`; `$` partial match; `nzchar(NA)`.
- **code-check-shell.md**: psql `:'var'` and `\quit`; a failed `cd`; `local` reading its own assignment.
- **code-check-spatial.md**: FWA `upstream_route_measure` misses the next start; FWA main flow.

The two mechanisms this round applies are "A proxy is not the property" (near a removed break stands in for "explained by the mechanism") and "A guard proving coverage must ask a wider question than the check".

## Fact the findings rest on

Both builds give the walk the same inputs: the same `<schema>.observations`, the same barrier tables and the same lifts. On one FWA segment, `access_<sp>` and `has_barriers_<sp>_dnstr` are therefore a function of the segment's start alone (`frs_network_features()` reads each segment's `(blk, drm, wscode, localcode)`). So a piece can change only where `a.dm <> b.dm`. Where that holds, the larger of the two starts is a boundary that exists in one build only: a removed observation cut, or a later source that one build suppresses and the other releases.

Two direction invariants follow from the 1 m rules:

- **b.dm < a.dm (the segment merged downward).** The lower start sees a superset of upstream records, including tributary mouths, and a subset of downstream barriers. So only 1 -> 2 and blocked -> open (`has_barriers` TRUE -> FALSE) are possible.
- **b.dm > a.dm (a released break).** Only 2 -> 1 and open -> blocked are possible.

## Enumeration (re-walked against the current files)

| place | depends on | verdict now |
|---|---|---|
| `R/lnk_pipeline_break.R:169-185` builder SQL | rounding (`round(max)` = `max(round)`) | right |
| `R/lnk_pipeline_break.R:161-162` subset claim | rounding is monotone | right |
| `R/lnk_pipeline_break.R:28` table row, `:154-159` mode doc | raw top against rounded start | right. "The first cut more than 1 m above its top" holds whatever made the cut, a released one included |
| `R/lnk_pipeline_break.R:18-24` `break_order` doc | which sources gate | right (`R/lnk_pipeline_prepare.R:513,681`, `lnk_pipeline_classify.R:107`) |
| `inst/extdata/configs/bcfishpass/config.yaml:96-98` | same as above | **right now** (round 3 fix) |
| `inst/extdata/configs/default/config.yaml:116-128` | first cut more than 1 m above the top | right ("mostly shortens" is hedged) |
| `R/lnk_config.R:388-403` `.lnk_observation_breaks_check()` | a closed set | right |
| `R/lnk_habitat_validate.R:43-51` attach rule | the validator's `< 1` | the rule is right. "most points sit inside a segment" under `top_per_species` is still unmeasured (LKEL keeps 59 % of positions); `bias.R`'s `share_on_segment_start` will show it. Unchanged since round 3 |
| `R/lnk_habitat_validate.R:54-65` buffer | `s2.drm >= seg_drm` | right |
| RUNBOOK §2c "own top break never changes its own code" | ±0.5 rounding against the 1 m tolerance | right |
| RUNBOOK §2c "under `top_per_species` … the next of the line's FWA ends, other break sources and other species' tops" | cut order | **right now**: a released source is an "other break source", and the new paragraph names release |
| RUNBOOK §2c "The access changes. The main one: … rounded position … more than 1 m above X's raw top" | raw against rounded | right (round 3 fix). It is described only through X's own top on the line; see finding 1 |
| RUNBOOK §2c "Three 1 m rules … move the rest", three bullets | release and suppression | the bullets are right. **"move the rest" is wrong** (finding 1: a merge below a tributary mouth gives whole-segment 1 -> 2 changes with no 1 m rule involved) |
| RUNBOOK §2c "Every one of these has a segment start within a few metres of a removed observation break; pre_post_diff.R checks that nothing else moves" | the start-function fact | the first half is right, even by construction. The second half claims more than the script checks (finding 2) |
| RUNBOOK §2c exact set "near-exact, not exact (the same released breaks)" | release, FWA ends | partly. It also misses where a kept exact position lies within 1 m of an FWA end and does not cut (`exact_set.sql`'s own case 2) |
| RUNBOOK §2c omitting `observations`; validator | — | right |
| `cuts.sql:7-20` header | cut order | **right now** (round 3 fix) |
| `cuts.sql:57-62` renamed columns, `cuts.csv` header | — | right; the csv header matches the SQL aliases in order |
| `cuts.sql` `removed_saving_a_segment` | release | right, apart from round 3's small undercount |
| `cuts.sql` FWA ends from `upstream_route_measure` | sub-mm gap | immaterial |
| `province.sql` | per-group tops | right (unchanged) |
| `code2_class.sql:27-28,51,56` `raw_t` | raw against rounded | **right now** (round 3 fix). R = T + 1 with raw_t < T is now caught |
| `code2_class.sql:1-6` header "The main access change" | — | right as "main", but finding 1 (tributary-mouth merge) is neither counted nor named |
| `code2_class.sql:31-32,55-56` `removed` / `r_m` | FWA-end suppression of an observation cut | **wrong (small)**: finding 4 |
| `code2_class.sql:67-75` `flips` | accessibility | **wrong (estimate)**: never tests that X is accessible at R (finding 4) |
| `code2_class.sql:40-48` `cut` list | release and suppression | ±1 m on `next_m` (round 3); sliver-sized only |
| `code2_class.sql:63-74` `fwa_upstream` across lines | — | right |
| `exact_set.sql:27-32` `p.m > t.raw_t + 1` | raw against rounded | right |
| `exact_set.sql:1-14` header | release, FWA ends, minimality | the three exceptions are right. **"So the count is an upper bound on what the rule needs" does not follow** (finding 5) |
| `redundancy.sql` | flagged moot | right as labelled |
| `pre_post_diff.R:83-87,108-110` `b_at_top` (`b.dm BETWEEN raw_t - 1.5 AND raw_t + 1`) | raw top, FWA-end suppression of T | **right now**. A start ≤ raw_t + 1 reads X's own top as upstream, so a 1 -> 2 there is correct by the walk's rule. The lower bound −1.5 covers T suppressed by an FWA end in [T − 1, T). An FWA end in (raw_t + 1, T + 1] gives no change, so it needs no window |
| `pre_post_diff.R:88-99` `allpos` / `keptpos` / `removed` | consistency with the builder | right: `keptpos` groups by raw `species_code` (CCT, ACT and `CT/RB` included), as `.lnk_pipeline_break_obs()` does, and the walk matches raw `species_code` (`lnk_pipeline_access.R:362-364`), as `tops` does |
| `pre_post_diff.R:111-114` `near_removed` (3 m, either start) | release, cascade depth | it covers every named case: a sliver (b.dm = R ± 1); whole-segment blocked/open next to a barrier (a.dm = R, b.dm = R + 1); whole-segment 2 -> 1 from a released break (a.dm = R in case b); cascades up to two released or suppressed links (R + 3). A cascade of three or more alternating later sources at metre spacing would read `elsewhere`; vanishingly rare. **As a control it is near-tautological** (finding 2) |
| `pre_post_diff.R:127-131` totals | — | right |
| `pre_post_diff.R:133-140` `km_change_near_removed` / `km_change_elsewhere` | — | the partition is right; see findings 1 and 2 for what `near_removed` holds |
| `pre_post_diff.R:13-28` header "Every other change comes from three 1 m rules" | — | **wrong** (finding 1) |
| `pre_post_diff.R:116` sliver `< 1.01` | 1 m plus up to 3.93 mm | right |
| `pre_post_diff.R:154` `sprintf` arguments | `%6$s` removed with `post` | right: no `%6$s` is left in the template |
| `pre_post_diff.R:160-166` coverage tolerance | — | right |
| `data-raw/logs/observation_breaks_396/README.md:24,26` file index | round 3's narrowing | **stale** (finding 3) |
| `bias.R:106-112` attach, `:113-118` FWA gradient | the validator's `< 1` | right, and a NULL gradient is immaterial (unchanged) |
| `build_obs.R` | the pipeline's prep helper | right |
| `run.sh` | — | fine |
| `tests/testthat/test-lnk_pipeline_break.R` live test and mocks | rounding | right |
| `tests/testthat/test-lnk_habitat_validate.R` new test | attach inside a segment | right |
| **new**: `pre_post_diff.R` direction of change against `sign(b.dm - a.dm)` | the invariants above | **not checked** (finding 2) |
| **new**: tributary-mouth merges | `fwa_upstream` across a confluence | **not described, not predicted** (finding 1) |

## Findings

- **[bug] RUNBOOK.md §2c ("Three 1 m rules stack near a removed break, and move the rest"); `pre_post_diff.R:17-18` ("Every other change comes from three 1 m rules"); `code2_class.sql` (counts only the own-top shape).** A merge gives whole-segment 1 -> 2 changes with no 1 m rule and no top of X's on the line. Worked case. Line L is one FWA segment, [0, 1000]. A tributary joins at 400, and X is recorded on that tributary. Y has records on L at 300 and 450, and its top at 900. X has no record on L.
  - Under `all`, L is cut at 300, 450 and 900. [300, 450) reads X = 2, because the mouth is upstream of 300. [450, 900) reads 1, because the mouth is below 450.
  - Under `top_per_species`, [0, 900) reads 2, so 450 m go from 1 to 2.
  - The same shape occurs when X does have a top on L but the AFTER segment starts at a non-top cut above it.

  It is the generalisation of the "main" change: the start moves down past any place where X reads as upstream (its own top within 1 m, or a tributary mouth with X up it), not only its own top. `pre_post_diff.R` puts it in `km_change_near_removed` (a.dm = 450 is removed), so nothing reads as a defect. But the bucket is documented as 1 m artefacts and will hold km-scale 1 -> 2. `code2_class.csv`'s predicted 1 -> 2 then undercounts what the builds change (`km_acc_1_to_2`), for a reason the record does not name. Fix: state the general rule in RUNBOOK §2c and the script header. In `code2_class.sql`, also predict, for every removed R, the species observed upstream of the AFTER segment's start but not of R. In `pre_post_diff.R`, report that 1 -> 2 apart from the near-removed rest (see finding 2).

- **[fragile, a measurement] `pre_post_diff.R:111-114,133-140` `near_removed`.** On the fact above, every change lies on a piece whose larger start is a one-build-only boundary. Every BEFORE segment that starts at a removed position has a.dm = r.m, distance 0. So `near_removed` excuses any change on any merged segment, whatever its direction, length or cause, and `km_change_elsewhere = 0` tests only three things:
  1. the builder kept exactly `keptpos`;
  2. cascades longer than 3 m;
  3. a non-segmentation difference between the builds (lifts, the observation set).

  A genuine defect that shows on merged segments can no longer be seen. Examples: open -> blocked or 2 -> 1 on a segment that merged downward, which the invariants make impossible; or blocked -> open with no gating barrier near either start. Round 3's finding 4 asked for `near_barrier` to read only the gating barriers. The fix removed the barrier test instead, which leaves a weaker control than the one it replaced: a 0 <-> open change no longer needs any barrier nearby.

  The question asked: a change whose segment start is far from every removed position still lands in `elsewhere`, but any change on a merged segment hides, however far along it the piece runs. Fix: keep `near_removed`, and add the direction test as the control, `elsewhere` defined as a violation. On `b.dm < a.dm` allow only 1 -> 2 and `has_barriers` TRUE -> FALSE. On `b.dm > a.dm` allow only 2 -> 1 and FALSE -> TRUE, with b.dm within 3 m of a removed position. Any change with `a.dm = b.dm` is a defect. Optionally require a gating barrier (`barriers_<sp>_access`) within (min start, max start + 1.5] for every `has_barriers` change, and report km per allowed class.

- **[fragile, doc] `data-raw/logs/observation_breaks_396/README.md:24,26`.** The file index still reads "the one access change expected: pieces that go from code 1 to 2" (`code2_class`) and "the break set that would keep code 2 exactly" (`exact_set`). Round 3 narrowed both claims in the scripts and the RUNBOOK, but not here. This is the index the archive and the research doc cite.

- **[fragile, an estimate] `code2_class.sql`.** There are two whole-segment overcounts, on top of round 3's ±1 m:
  - **`flips` (67-75) never tests that X is accessible at R.** X can be recorded above one of its own barriers that its records do not lift (below `observation_threshold`). There, the piece reads 0 in both builds, yet it is counted in `km_1_to_2`, while `pre_post_diff`'s `km_acc_1_to_2_at_top` excludes it.
  - **`removed` / `r_m` (31-32, 55-56) keep a removed position that never cut**, because it lay within 1 m of an FWA end at or below raw_t + 1. Example: raw_t 500.4, an FWA end at 501.3, R = 502. Both builds start a segment at 501.3, which reads 2, so nothing changes, but the script counts `next − 502` m as flipping.

  Fix: drop removed positions within 1 m of an FWA end (as `cuts.sql`'s `near_other` does for FWA), and either test X's access at R from the BEFORE build or say that `km_1_to_2` includes pieces that are blocked for X.

- **[fragile, doc] `exact_set.sql:12-13`.** "So the count is an upper bound on what the rule needs" follows only from the third exception (not minimal). The first two say the rule keeps too little: a released break, and a kept position within 1 m of an FWA end that does not cut. So `positions_exact` is the rule's own size, neither an upper nor a lower bound on an exact set. Say that, or drop the "So".

None of these touches the shipped R code. The builder, the config check, the `break_order` doc and the validator are right.
