# Task: Check each group's species presence against its fish records (#402)

**If done:** every row of `default`'s `wsg_species_presence.csv` is checked against a stated rule on the fish records, for example at least 5 records dated 1950 or later in the group. Each disagreement is listed for review. **If never:** a species can be modelled in a group on the strength of one old record, or left out where the records say it is there, and nobody is told.

## Context

`default`'s `overrides/wsg_species_presence.csv` (246 groups × 13 species, plus a `notes` column with one cell per group) is hand-authored, and no rule produces or checks it. A row decides whether a species is modelled in a group at all. The pipeline reads it two ways:
- **Raw:** the observation filter (`.lnk_pipeline_break_obs_species()` → `.lnk_wsg_species_present()`, `R/lnk_pipeline_break.R:230`) and `lnk_pipeline_species()` read it as written.
- **Promoted:** the barrier sets (`R/lnk_pipeline_prepare.R:645`) and the mapping code (`R/lnk_pipeline_run.R:257`) read it through `lnk_presence()`, where any salmon present makes all salmon present, and any of ct/dv/rb makes all three present.

Done, every present/absent cell is judged against a stated rule on the fish records. Each disagreement goes into a tracker in the bundle, with a drafted story of what that group's records show and a decision for the operator to make. Nothing edits the presence table automatically.

## Decided at the gate (operator, 2026-10-30)

1. **Rule:** one record dated 1950 or later counts, for every species (salmon and bull trout included; operator, 2026-10-30, revised from the first answer of 5: a single fish caught above where the species was recorded before is real evidence, and while the row reads absent the pipeline drops it). A present cell is flagged when it has no such record, an absent cell when it has any. The count is shown, not judged: each row carries its total count, its count since 1990, its newest year and its sources, so a single stray reads differently from a run.
2. **Releases left out**, by bcfishpass's own tagging (`smnorris/bcfishpass@620dbe4` `load_observations.sql`): `source` starts `Releases Database:`, `source_ref` ilike `%BC RELEASE RECORDS DATABASE%` or `%STOCKING%`, or the record's `observation_exclusions.csv` row has `release_include`. Each row still shows its release count.
3. **DV pooled into BT** where `species_pooling.csv` pools (#290), with the year limit applied. The `dv` column is judged on DV records alone, and each row shows its unpooled BT count.
4. **Exclusions first:** records marked `data_error` or `release_exclude` are dropped before counting, as in the pipeline.
5. **Each group's story is tracked in the bundle:** a new `configs/default/wsg_species_presence_review.csv`, shaped like `species_pooling.csv`.

Also settled in exploration (mechanism, not asked):
- The check judges the **raw** row, and each row says whether the species is present after promotion and which group promotes it.
- CT aliases (CCT, ACT, CT/RB) count as CT, as in the pipeline.
- A year after the current year or before 1850 (the source holds 1007 and 9999) counts as undated, and an undated record does not meet the 1950 floor.
- `lnk_species_pooling()` yields rows only where the model species is present, so the check resolves pooling against a copy of the table with every species marked present. Without that, DV could never count toward an absent BT.
- The PR relates to #402 and does not close it: acceptance item 2 (a note on every row the operator changes) is the operator's.

Sized on today's local records (before pooling and exclusions): about 24 present cells have no record since 1950 and about 319 absent cells have at least one, so roughly 340 tracker rows.

## Phase 1: Check logic in R/, tested without a database

- [ ] `.lnk_observation_exclusion_keys(loaded)`: the `data_error` / `release_exclude` key list, moved out of `.lnk_pipeline_prep_observations()` (`R/lnk_pipeline_prepare.R:319`). Prep calls it, so the pipeline and the check apply one rule. A test asserts prep's SQL is unchanged.
- [ ] `.lnk_presence_check(records, loaded, n_min = 1L, year_min = 1950, regions = NULL)`: takes a records data frame (`observation_key`, `watershed_group_code`, `species_code`, `observation_date`, `source`, `source_ref`), applies the CT remap, exclusions, release tag, date validity and pooling, and returns one row per group × species: counts (all, kept, since the floor, since 1990, releases, excluded, pooled DV, unpooled own), oldest and newest year, the raw and promoted presence, `promoted_by`, and `flag` (`present_unsupported` | `absent_recorded` | NA).
- [ ] `.lnk_presence_story(row)`: a story drafted from the evidence and the group's `notes` cell. For example: "all 7 records are releases", "newest record 1968", "3 records, none since 1990", "existing note: Kenny Dam", "absent, but modelled through the salmon group".
- [ ] `.lnk_presence_review_merge(tracker, flagged)`: appends new flags as `pending`, never touches a row that carries a decision, and reports tracker rows the check no longer flags.
- [ ] Tests (`tests/testthat/test-lnk_presence_check.R`): CT aliases; each of the four release conditions; exclusions; pooling only in pooled regions, including a group where BT is absent; the year limit on pooling; undated and impossible years; both flag directions at the boundary (0 and 1 kept record, and a record dated 1949 against 1950); a promoted-only species; merge keeps decided rows. Then restore each defect and watch its test fail.

## Phase 2: The tracker in the bundle

- [ ] `inst/extdata/configs/default/wsg_species_presence_review.csv` with columns `watershed_group_code, species_code, flag, rule, story, decision (pending|keep|add|remove), reviewer, review_date, issue`.
- [ ] `configs/dictionary_wsg_species_presence_review.csv`, and the stem added to `test-dictionaries.R`'s tracker loop (line 248).
- [ ] Declare it under `files:` in `configs/default/config.yaml` with a provenance entry (source: link, hand-authored; #402). The pipeline does not read it, and `lnk_vocabulary_resolve()` does not either, so no output token moves.

## Phase 3: The check script, run on all groups

- [ ] `data-raw/wsg_species_presence_check.R [--config=default] [--n-min=1] [--year-min=1950] [--seed-tracker] [--out=]`. It reads `bcfishobs.observations` from local fwapg and calls Phase 1. It writes `data-raw/logs/presence_check_402/`: `disagreements.csv` (every flagged cell with its counts and story), `groups.csv` (flags per group, with region and notes), `summary.csv` (flags by species and direction) and `stamp.txt` (link sha, bcfishobs row count and newest date, rule). `--seed-tracker` merges the flags into the tracker. The script never writes `wsg_species_presence.csv`.
- [ ] Cross-check: for three groups (one Mackenzie, one Fraser, one coastal), count independently in psql and match the script's counts exactly; the script stops on a mismatch.
- [ ] Run on all 246 groups, seed the tracker (every row `pending`, story drafted), and commit the logs and the tracker, with a README in the log directory.

## Phase 4: Write-up

- [ ] `research/species_presence.md` (new topic file, with a provenance line): the rule, what it counts, the flags by species and region, and the patterns found (for example: KO absent but with records in many groups, Mackenzie salmon rows noted as absent, present rows held up only by releases). Add it to `research/README.md`.
- [ ] RUNBOOK: a short paragraph on the check and tracker where presence is described (the §2c / acc neighbourhood).
- [ ] CLAUDE.md status entry, NEWS line.

## Owed at the end (reported, done after merge)

- [ ] **Operator review:** a decision on each tracker row. Each changed presence cell carries a `notes` entry naming the rule (#402, acceptance 2). The issue stays open until then.
- [ ] **Changing presence cells is its own PR:** the presence table is in the `acc` token spec (RUNBOOK §6b), so an edit needs a new `acc` vocabulary row and a version bump, plus the config provenance checksum. The affected groups re-model at the next provincial run (#377's runs row).
- [ ] The pre-run gate (#372) must run again, since `R/lnk_pipeline_prepare.R` changes, behaviour-preserving. It is already owed for #401.

## Validation

- [ ] Tests pass (`devtools::test()`), `lintr::lint_package()`, `devtools::document()`
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the Phase 1 unit tests with mutation checks; the Phase 3 psql cross-check for three groups; the prep refactor proved by an unchanged SQL string; a script run end to end on all groups, with flag totals reconciled against `summary.csv`.

