# Plan review — #402 (Plan agent, 2026-10-30, read against 29711c0c plus the working-tree prep refactor)

## Q1. Declaring the tracker under `files:`
- Tokens: no move (`lnk_vocabulary_resolve()` reads parameters_fresh, presence species columns and named barrier inputs; R/lnk_vocabulary.R:120-215).
- Blocker/Assumption: `config_hash` moves on the declaration and every later tracker edit (`.lnk_config_files()`, R/lnk_log.R:84-91; also default_tuned via inheritance). Then recompute_readers.R:114 refuses (`config_differs`), recompute_readers_check.R:141 refuses (`config_changed_since_run`), and `.lnk_export_bundle()` refuses runs logged before the edit (R/lnk_scenario_export.R:578-591). Each operator decision after the next provincial run would break recompute and publication of that run.
- Gap: provenance drift test (test-lnk_config.R:397) fails on each tracker edit until re-stamped; runs record `config_drift = TRUE`.
- Gap: the pretest gate maps config.yaml to any/segments/observations/dams, so each re-stamp re-triggers the #372 gate.
- Blocker (test): test-pretest.R:221-238 requires every inst/extdata file to match a pretest_inputs.csv row; the tracker matches none. Needs a `none` row.
- Blocker (test, conditional): a new R/ file needs a pretest row (test-pretest.R:36); map R/lnk_presence_check.R `none`.
- Recommendation: keep the tracker in the bundle directory, out of `files:` and `provenance:`; map it `none`; test the dictionary by direct path.

## Q2. Pooling resolver
- Workaround (copy with every species "t") correct; known species come from column names (R/lnk_species_pooling.R:103,121,130). All 246 groups are in wsg_regions.csv.
- Gap: fold CT aliases before joining the resolver. Keep WCT separate.
- Gap: drive pooling from the resolver for every target species, not DV by name.
- Assumption to state: the pipeline itself never pools (only the validator and thresholds producer use the resolver). A BT `absent_recorded` resting only on DV records would, if accepted, model BT with no BT records; the story should say so.

## Q3. Counting rule against the pipeline
- Gap: other codes in bcfishobs.observations (local): SST 404, WST 358, STC 279, ADV 79, BT/DV 57, DV/BT 52, RB/CT 23, ABT 12, DVxBT 6, ' RB' 1. The pipeline drops all of them (exact IN). Mirror the pipeline, report each group's records under other codes in their own column, list the codes in stamp.txt.
- Gap: the story should say which species' lifts read the cell (parameters_fresh observation_species: salmon and ST read CH;CM;CO;PK;SK(;ST), BT reads BT;DV).
- Gap: define exclusion vs release precedence (excluded first, never also a release); NA not a release.
- Gap: the "one rule" claim; the same key logic is duplicated at R/lnk_habitat_validate.R:792-796, data-raw/access_disagree_349.R:112, data-raw/query_habitat_thresholds_obs.R:65. Switch the validator (mapped none) or narrow the claim.
- Assumption: bcfishpass's filter tests the raw code, so it does not admit CT aliases despite R/lnk_pipeline_prepare.R:287-289; say "as in link's pipeline" (#398).
- Fine: undated rule, exclusions first, raw via `.lnk_wsg_species_present()` and promoted via `lnk_presence()`.

## Q4. Ordering, scope, acceptance
- Ordering: re-stamp provenance after seeding (moot if undeclared).
- Ordering: capture the unchanged-SQL golden from the pre-refactor code, with "t"/NA string fixtures.
- Ordering: the gate is owed for config.yaml too (moot if undeclared).
- Acceptance: psql cross-check needs the exclusion and release_include keys from the CSV (temp table of keys); say so.
- Acceptance: disagreements.csv needs oldest and newest years; add the other-codes count.
- Scope: restrict the script to `default` (other bundles have other presence files and no tracker).

## Disposition (2026-10-30)
- Q1: tracker kept in the bundle directory, undeclared; pretest rows `none` for the tracker and R/lnk_presence_check.R; dictionary tested by path. Deviation from the plan's "declare under files:" (mechanism; reported in the summary).
- Q2: CT folded before the join (done); pooling driven by the resolver for all targets (done); story names the pooled species.
- Q3: other codes counted per group into groups.csv and stamp.txt; lift readers named in the story; precedence as coded (excluded first); validator switched to the helper; research file says "as in link's pipeline".
- Q4: golden SQL checked against the pre-refactor function; script refuses a config other than default; cross-check builds the exclusion keys as a temp table.
