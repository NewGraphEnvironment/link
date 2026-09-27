## Outcome

Moved "which observation species count as which model species" out of code and into data.

- **The tracker.** `configs/default/species_pooling.csv` holds one dated, sourced row per decision. Each row is scoped to a region, sub-region or WSG, and either side can be a group from `species_groups.csv`.
- **The resolver.** `lnk_species_pooling()` resolves it and knows no species: DV into BT, or all salmon together, is a row. The most specific scope wins, then the row naming fewer groups. Unresolved ties error, and anything unlisted is not pooled.
- **Regions.** `inst/extdata/wsg_regions.csv` is package-level geography. The region is the first segment of each group's *outlet* wscode (LFRA straddles 100 and 900). It is hashed into the `config_hash` of any bundle that declares a tracker.
- **Consumers.** `lnk_habitat_validate()`, `data-raw/habitat_validate.R` and the #284 obs producer take pooling from the tracker. The validator driver resolves it once and applies it to both bundles.
- **Seed.** DV → BT in the Fraser, Mackenzie, Skeena and Columbia/Kootenay (operator call, 2026-09-26).
- **State of knowledge:** [`research/species_pooling.md`](../../../research/species_pooling.md).

The plan moved twice at the operator's word: regions went package-level rather than into the bundle, and pooling became abstract (species or group on either side) mid-plan.

## Measurement

- **Where the new rule applies.** DV pools into BT in 129 WSGs. It does not in the 29 BT-present WSGs of unlisted regions (Nass, Stikine, Taku, Yukon, the coast), all of which pooled under the old "wherever BT is present" rule.
- **No #284 or #283 number moved.** Predicted before running, and confirmed:
  - The #284 obs producer re-runs byte-identical in every CSV and PNG except the province-wide ledger step 3, where DV goes 8,888 → 6,138. The plan review independently derived the same 6,138.
  - The #283 validation baseline (55 + 59 WSGs, knowledge @ 508bf44) re-runs byte-identical in all 6 CSVs, before and after the Phase 3 guards.
- **Negative check** (Skeena `pool = no`): ledger DV 2,910 (6,138 − 3,228). 1,929 evidence rows drop, all DV, in exactly the 9 Skeena WSGs; 0 rows are added and the rest are identical.
- **A pre-existing reproducibility defect surfaced.** The #284 producer's `candidates.csv` differs by 1 ulp (1.7e-16 relative) between identical runs, from a double-precision `sum(length_metre)` in its availability SQL. The committed copy was kept, and the issue is drafted in `draft_obs_float_issue.md`.
- **Wrong turns kept:**
  - A mutation loop restored from a missing path, so mutations stacked until a control run was added.
  - A `sprintf()` over SQL with a literal `LIKE '...%'` crashed the first re-run.
  - Round 2 of code review found every dictionary line ref stale after round 1's fixes. Round 3 found that the test written to catch that matched substrings.
  - Phase 3's first presence guard compared by row position.

  All four are one mechanism, which review round 3 named: two separately kept lists agree on a key, and disagreement narrows silently instead of failing. Both review loops ended by enumerating the mechanism's reach and guarding each site.
- **Review spend:** 1 plan review and 5 code-check rounds (Phase 2: 3; Phase 3: 2, one below the skill's floor, stated). That is 6 agents, past the ~5 bound.

## Evidence

- `data-raw/logs/habitat_thresholds_284/` (refreshed: `obs_ledger.csv`, `stamp.txt`)
- Review files: `review-*.md` here
- Follow-up issue drafts, awaiting body review: `draft_*.md` here

Closed by: PR for #290 (branch `290-region-scoped-dv-bt-observation-pooling`)
