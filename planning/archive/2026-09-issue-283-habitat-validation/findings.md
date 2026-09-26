# Findings — Validate modelled habitat against fish observations (#283)

## Issue context

**If we do it:** "is this threshold set better?" gets a number per species and watershed group, so candidate CH/BT thresholds can be compared rather than eyeballed. **If we never do:** threshold changes are judged against bcfishpass parity, which measures agreement with a model rather than with fish.

## Problem

link compares its output with bcfishpass (`compare_*`, `wsg_compare.R`, `parity_crosssection.R`) but never with fish observations. The only observation-vs-model comparison is the Babine SK work in `research/default_vs_bcfishpass.md` §6-7, done by hand for one species against `user_habitat_classification`.

## Proposed Solution

A function (working name `lnk_habitat_validate()`) and a driver that, for a run schema, species set and WSG set, report:

- **Capture:** share of observations (after `observation_exclusions`, releases removed) on or within a buffer of modelled spawning / rearing / accessible segments, split by life stage where known.
- **Cost:** km of modelled spawning and rearing, so capture can't be raised by just calling everything habitat.
- **Misses:** gradient, channel width and edge type of the segments under observations that fell outside modelled habitat. This is the direct evidence for which threshold is binding.
- **Absences (optional input):** sites sampled with no fish captured (FISS no-fish-captured records), used as a false-positive check.

Output is a tidy table per bundle × species × WSG, so two bundles can be diffed. Use the per-WSG schemas; `fresh.streams_habitat_*` in the local snapshot is duplicated per group (fresh#218).

Known biases to report alongside the numbers, not correct silently:
- observation points often sit at the downstream end of a sampling site;
- sampling clusters near road access;
- observations exist only where fish have access, so observed gradients are cut off at the access limit.


## fresh#218 is a bare-`id_segment` join artifact (measured 2026-09-26)

Docker fwapg :5432.

| query | rows |
|---|---|
| `fresh.streams_habitat_ch` total / distinct `(id_segment, watershed_group_code)` | 2,329,201 / 2,329,201 |
| `fresh_default.streams_habitat_ch` total / distinct full PK | 786,317 / 786,317 |
| Naver Creek (blk 356363814, COTR) `streams ⋈ streams_habitat_ch` on full PK | 187 |
| same on bare `id_segment` | 4,301 |

Naver's `id_segment` range is 35796–35982; those integers are other segments in other
WSGs (#203). No duplication. #283 body corrected. fresh#218 itself (a fresh-repo issue)
is left for the user — offered in the PR report.

## Circularity

Observations feed the model: barrier overrides (`observation_threshold` BT 1, CH 5,
`observation_species` BT `BT;DV`, CH `CH;CM;CO;PK;SK`), observation break points, and
`user_habitat_classification` (field-confirmed habitat). So accessible capture partly
reads the model's own input. Spawning/rearing capture is the score.

## Coverage for the baseline

`fresh_default` 55 WSGs (all with `streams_access`); `fresh` 59 WSGs with access; 51 shared.
`fresh_default_tuned` does not exist. FISS snapshot WSGs in `fresh_default`: COTR, PINE, UPCE.
