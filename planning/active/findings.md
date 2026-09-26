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

