# Findings — Check each group's species presence against its fish records (#402)

## Issue context

**If done:** every row of `default`'s `wsg_species_presence.csv` is checked against a stated rule on the fish records, for example at least 5 records dated 1950 or later in the group. Each disagreement is listed for review. **If never:** a species can be modelled in a group on the strength of one old record, or left out where the records say it is there, and nobody is told.

## Today

- **The table is hand-authored,** with a notes column (`source: link (hand-authored)` in `configs/default/config.yaml`, link@43e34096). No rule produces or checks it.
- **A presence row decides whether a species is modelled in the group at all.** Records of a species not present are dropped before the breaks and the access walk (`R/lnk_pipeline_prepare.R:346`), and `access_<sp>` reads -9. So an absent species gets no observation cut, no code 2, no access and no habitat there.
- **Presence is promoted by species group** (`lnk_presence()`: any salmon present means all salmon present; #292, #153). A rule that drops CH where CO is present would be undone by promotion. The check has to read the table both before and after promotion, and say which one it judged.

## Proposed

A `data-raw/` script that counts records per group and species under the rule, and writes the disagreements in both directions:
- **present with too few records,** such as one CH record from 1945;
- **enough records but not present.**

The operator edits rows with a note. Nothing edits the table automatically:
- no records is not no fish, since some groups are barely sampled;
- some presence comes from knowledge outside bcfishobs.

## Decisions (operator)

1. **The rule.** The count, the date floor, and whether either differs between anadromous and resident species.
2. **Pooling.** Whether DV records count toward BT where `species_pooling.csv` pools (#290).
3. **Exclusions first.** Whether `observation_exclusions.csv` is applied before counting (recommended, so a record already ruled bad does not count).

## Acceptance

- The disagreement list for all groups is committed under `data-raw/logs/`, with each row's counts and dates.
- Every row the operator changes carries a note naming the rule.

Related: #292, #153, #290, #400.


## Exploration (2026-10-30)

- Presence is read raw by the observation filter (`.lnk_wsg_species_present()`, which tests `identical(x, "t")`) and by `lnk_pipeline_species()`, and promoted through `lnk_presence()` by the barrier sets (`R/lnk_pipeline_prepare.R:645`) and the mapping code (`R/lnk_pipeline_run.R:257`).
- `lnk_species_pooling()` returns rows only where the model species is present, so the check resolves pooling against a copy of the presence table with every species marked present.
- bcfishpass (`smnorris/bcfishpass@620dbe4` `model/01_access/sql/load_observations.sql`) tags releases rather than dropping them: `source` starting `Releases Database:`, `source_ref` ilike `%BC RELEASE RECORDS DATABASE%` or `%STOCKING%`, or the exclusions row's `release_include`. Its note says the Releases Database source was absent from bcfishobs as of 2026-01-05, but local fwapg still holds 74,495 such records of 375,962.
- `bcfishobs.observations.observation_date` runs from 1007-08-03 to 9999-11-01; 5,510 records are undated.
- The presence table is in the `acc` vocabulary spec (species columns only; `notes` is excluded by `.lnk_presence_species_cols()`), so changing a cell moves the `acc` token but editing a note does not.
- Rough size, over the 13 species columns, CT aliases folded and releases counted: at least 5 records (any date) gives 206 present-too-few and 187 absent-enough; at least 5 non-release records dated 1950 or later gives 223 and 153. Absent-enough under the latter is led by KO (92); present-too-few by DV (53), BT (48) and CT (35), before DV pooling.
- The `notes` column holds 65 "Mackenzie basin" rows and 8 "No target species observations".

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Phase 1 (2026-10-30)

- The prep refactor (`.lnk_observation_exclusion_keys()`) produces SQL identical to the pre-refactor function from `git show HEAD:R/lnk_pipeline_prepare.R`, captured with `.lnk_db_execute` mocked, for three inputs: the shipped exclusions read as character, a logical/NA mix, and no exclusions (7 statements each, 33,134 / 27,246 / 27,168 characters).
- The validator (`R/lnk_habitat_validate.R`) also reads the helper now. `data-raw/access_disagree_349.R` and `data-raw/query_habitat_thresholds_obs.R` keep their own copies (one-off evidence scripts; not changed).
- bcfishpass's own filter tests the raw species code (`array[o.species_code] && wsg_spp.species_codes`), so it does not admit the CT aliases; the check folds them as link's pipeline does (relates to #398).
