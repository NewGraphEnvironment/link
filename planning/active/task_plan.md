# Task: Turn species off in a bundle's runs with a dated tracker (KO and RB in default) (#432)

`default` models every species with a row in `dimensions.csv`: `lnk_config()` takes `cfg$species` from the species named in the generated `rules.yaml` (`R/lnk_config.R:121`), and every phase reads that list. Two species should not run in `default` for now, and neither is tuned:

- **KO:** the `ko` presence column was never sourced. It was added with four test values (CARP, KOTL, NATR, PARS; link PR #107), and bcfishpass's presence table has no kokanee column. 137 groups with KO records are unmarked (#402).
- **RB:** field records do not reliably separate rainbow trout from steelhead.

There is no way to say "not now" short of removing the row. Steelhead have the same identification problem and stay modelled for now, so the next provincial run is not delayed.

## Context

`default` models every species with a rules entry: `lnk_config()` sets `cfg$species <- names(read_yaml(rules))` (`R/lnk_config.R:121`), and every phase reads that list. KO's presence column was never sourced and RB records don't separate from steelhead, so both should stop running in `default` for now. Today the only way to stop one is to delete its `dimensions.csv` row, which loses the rules and leaves the reason only in git history. #432 adds a switch. #433 decides what a paused species does to segmentation, and #432 builds that choice.

## Decided at the gate (operator, 2026-11-01)

- **#433: off means off.** A paused species adds no gradient breaks (option 1). The test for whether segmentation matters is whether it affects tuning. Measure the effect and record it.
- **Groups left with no modelled species are still modelled** (segments, barriers, streams; no habitat), because other groups read their barrier rows. Pausing KO and RB leaves 8 such groups: BRID, CHUK, GRNL, LEUT, LNRS, MURT, PITR, UISR. Today `lnk_pipeline_run()` refuses a group with no species (`R/lnk_pipeline_run.R:226`), and `lnk_wsg_resolve()` filters groups on `cfg$species`. On the 2026-10-26 line rule, LEUT and LNRS are each read by 19 groups (NATR, TABR, TAKL, …), UISR by ISKR, LISR and LSTR, PITR by MSTR and USTK, and MURT, BRID, CHUK and GRNL by one group each.

## Decided in exploration (state them at approval; reversible)

- **Observation top breaks stay on presence, not on the modelled list.** `.lnk_pipeline_break_obs_species()` (`R/lnk_pipeline_break.R:230`) already cuts at CT and DV tops, though no rules model CT or DV, so RB and KO tops keep cutting too. #433 is about gradient breaks. Changing this would be a second segmentation change to measure separately.
- **A full build clears the group's rows from habitat tables of species it no longer models.** `lnk_pipeline_persist()` deletes per species only for the species it writes (`R/lnk_pipeline_persist.R:63`). A paused species, or a presence cell removed by #402 (10 cells), would otherwise keep old `streams_habitat_<sp>` rows cut to segments that no longer exist. `lnk_compare_rollup()` finds species from tables with rows (`R/lnk_compare_rollup.R:150`), so it would count those rows. The clearing goes in `lnk_pipeline_run()` (a full build), not in persist, because the variants harness persists one species at a time (`data-raw/habitat_variants_build.R:927`).

## Phase 1: Tests first

- [x] `test-lnk_config.R`: `cfg$species` = rules species minus those marked `f`, in rules order; `cfg$species_paused` lists them. Refusals: a code with no rules entry, a rules species with no row, a `modelled` value other than `t`/`f`, and a duplicate code.
- [x] `extends:` inherits the file: `default_tuned` pauses KO and RB. A bundle that declares no file (`bcfishpass`, `default_extrabreaks`, `default_rearbreaks`) models every rules species, unchanged.
- [x] `.lnk_pipeline_prep_minimal()` builds no barrier set for a paused species (it iterates `cfg$species`, so this pins the existing route).
- [x] The acc spec moves when a species is paused (`lnk_vocabulary_resolve()` already hashes `cfg$species`, `R/lnk_vocabulary.R:202`).
- [ ] Live tests (skip without the DB): a group with no modelled species builds streams and barriers and persists no habitat. A re-model clears the habitat rows of a species no longer modelled.

## Phase 2: The switch

- [x] `inst/extdata/configs/default/species_modelled.csv` (`species_code, modelled, reason, date, issue`, the shape of `species_pooling.csv`). KO `f`: the presence column was never sourced (four test values, PR #107; 137 groups with KO records unmarked, #402). RB `f`: field records do not reliably separate rainbow trout from steelhead. Every other rules species `t`. Declared under `files:` in `default/config.yaml`.
- [x] `configs/dictionary_species_modelled.csv`, covered by `test-dictionaries.R`.
- [x] `lnk_config()` applies the filter and adds `cfg$species_paused`. `print.lnk_config` shows paused species.
- [x] `data-raw/pretest_inputs.csv`: a row mapping `configs/{config}/species_modelled.csv` to `any` (the gate refuses an unmapped file).
- [x] The bundle's `README.md` names the file.

## Phase 3: Readers and a group with no modelled species

- [x] `lnk_wsg_resolve()` (`R/lnk_wsg_resolve.R:94`) keeps a group with any rules species present, paused or not, so the 8 groups stay in the run and its closure.
- [x] `lnk_pipeline_run()`: with no modelled species, run setup, load, prepare, break and the barrier unify and persist. Skip classify, connect and the habitat persist. Persist `streams_access` and `streams_mapping_code` rows with no per-species values, and log the group with an empty species list.
- [x] Recompute (`lnk_access()`, `wsg_recompute_one.R`, the habitat gate): a group with no modelled species passes through instead of stopping on "species is empty".
- [x] The run clears a group's rows from `streams_habitat_<sp>` for each species in the schema that the build does not model.
- [x] Audit the remaining readers for the rules species where `cfg$species` is meant: classify and connect take species from `lnk_pipeline_species()`. Also check the validator, `lnk_presence_check` (its `modelled` column goes FALSE for KO and RB, as intended), `barriers_views_build.R`, `buckets_balance.R` and the variants harness. Fix any that read rules species directly.
- [ ] `study_area_verify.sql` and the driver accept a group whose log row carries no species. Check what they assert per group.

## Phase 4: Measure #433 (before arm from a worktree at 07203cde, after arm at the Phase 3 commit; scratch schemas on m4)

- [x] Build `default` before (KO and RB modelled) and after (paused) on KOTL, SALR and KETL (RB without BT), NBNK (RB only through the CT/DV/RB expansion), MURT (paused species only), and BULK as the control. Pin that MURT's barrier and override rows match across arms (review 15).
- [x] Report segments, breaks moved, BT and CH rearing km moved, and the gradient at fish records whose segment changed. The question is what tuning reads.
- [x] Write it up in `research/` (the segmentation write-up, or a short `species_paused.md` indexed in `research/README.md`). Evidence in `data-raw/logs/species_paused_432/` with a README.

## Phase 5: Vocabulary, docs, release

- [x] An `acc-v5` row for `default` and `default_tuned`: as `acc-v4`, with KO and RB paused (no breaks, no access, no habitat). Check that `cut-full-top`'s wording still holds; its breaks follow the acc token.
- [x] RUNBOOK: §2 (breaks follow modelled species) and the config section (the switch, and a group with no modelled species).
- [ ] NEWS and the version bump to 0.76.0, the final commit. Add a CLAUDE.md Status entry.
- [x] #402's tracker: the 141 KO and RB rows already carry `issue` `#432` as pending deferrals. Confirm, and change nothing.

## Owed at the end (reported, done after merge)

- [ ] Every `default` group re-models at the next provincial run: KO and RB habitat, access and mapping-code values go, and segmentation moves where Phase 4 measured. Add the 8 no-species groups to the run's notes, with `expected_n` unchanged at 241.
- [ ] Copy the sample rules to fresh only if `rules.yaml` changes. The plan leaves it unchanged.

## Validation

- [ ] Tests pass (`devtools::test()`, live DB tests included)
- [ ] `/code-check` clean (once over the branch, `/code-check branch`, three-round floor)
- [ ] `lintr::lint_package()`, `devtools::check()`
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How it is proved: the config filter and its refusals by unit tests. The no-species path by a live build of MURT that persists streams and barriers and passes the verifier's per-group checks. The stale-row clearing by a live re-model that leaves 0 rows for the cleared species in that group. Segmentation by Phase 4's before/after on one commit. `bcfishpass` unchanged by its acc spec, `config_hash` and a BULK build's segment count.
