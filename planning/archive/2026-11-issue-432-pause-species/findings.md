# Findings — Turn species off in a bundle's runs with a dated tracker (#432)

## Issue context

**If we do it:** a bundle can stop modelling a species without losing its rules, thresholds or the reason it was stopped, and turning it back on is a one-cell edit. **If we never do:** pausing a species means deleting its row from `dimensions.csv`, and the decision lives only in git history.

## Problem

`default` models every species with a row in `dimensions.csv`: `lnk_config()` takes `cfg$species` from the species named in the generated `rules.yaml` (`R/lnk_config.R:121`), and every phase reads that list. Two species should not run in `default` for now, and neither is tuned:

- **KO:** the `ko` presence column was never sourced. It was added with four test values (CARP, KOTL, NATR, PARS; link PR #107), and bcfishpass's presence table has no kokanee column. 137 groups with KO records are unmarked (#402).
- **RB:** field records do not reliably separate rainbow trout from steelhead.

There is no way to say "not now" short of removing the row. Steelhead have the same identification problem and stay modelled for now, so the next provincial run is not delayed.

## Proposed

- [ ] **`configs/default/species_modelled.csv`**, declared under `files:`: one row per species, `species_code, modelled, reason, date, issue`, the shape of `species_pooling.csv`. KO and RB read `f` with their reasons; every other species with a rules entry reads `t`.
- [ ] **One filter in `lnk_config()`:** `cfg$species` is the rules species less those marked `f`. Refuse a code with no rules entry, a species with rules and no row, and a `modelled` value other than `t` / `f`.
- [ ] **`extends:` inherits it,** so `default_tuned` cannot run a species `default` paused unless it declares its own file.
- [ ] **Check that nothing reads the rules' species directly** instead of `cfg$species` (`lnk_pipeline_classify()`, `lnk_presence()`'s promotion, the validator, the variants harness), and that `lnk_vocabulary_resolve()`'s `acc` spec follows the filtered list.
- [ ] **What a paused species does to segmentation** is decided in #433. Build whichever it chooses.
- [ ] **Tracker rows:** #402's review rows for KO (138) and RB (3) are marked deferred, with the reason, not decided cell by cell.
- [ ] **A new `acc` token row** and the version bump (the species list is in the `acc` spec).

## Not proposed

No change to the `bcfishpass` bundle. The KO and RB thresholds and parameter rows stay as they are. Steelhead are not paused here.

Relates to #433 (a paused species' segmentation), #402 (presence checked against the fish records), #415 (a minimal network for tuning), #431 (the presence table as bcfishpass's copy plus an overlay) and #414 (output vocabulary).

## Exploration (plan mode, 2026-11-01)

- `cfg$species` is the rules species (`R/lnk_config.R:121`): default, default_tuned, default_extrabreaks, default_rearbreaks all give BT CH CM CO PK SK ST WCT KO RB GR; bcfishpass gives the first eight.
- Gradient breaks iterate `cfg$species` (`.lnk_pipeline_prep_minimal()`, `R/lnk_pipeline_prepare.R:651`), so filtering `cfg$species` removes a paused species' breaks with no change there.
- Observation top breaks follow presence (`.lnk_pipeline_break_obs_species()`, `R/lnk_pipeline_break.R:230`), not `cfg$species`: CT and DV tops already cut.
- The acc token spec hashes `cfg$species` (`R/lnk_vocabulary.R:202`).
- Pausing KO and RB: 242 groups with a modelled species become 234; 8 lose every species (BRID CHUK GRNL LEUT LNRS MURT PITR UISR). 71 groups have RB present without BT.
- Readers of the 8 (line rule, `data-raw/logs/recompute_early_374/run_a2/20261026_181957_recompute_deps.tsv`): LEUT and LNRS 19 each, UISR 3 (ISKR LISR LSTR), PITR 2 (MSTR USTK), MURT CLWR, BRID MAHD, CHUK USTK, GRNL DOGC.
- `lnk_pipeline_persist()` clears per species only for the species it writes, so a paused species' old rows stay; `lnk_compare_rollup()` discovers species from tables with rows.
- #402's tracker already holds the 141 KO (138) and RB (3) rows as pending with `issue` `#432`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
