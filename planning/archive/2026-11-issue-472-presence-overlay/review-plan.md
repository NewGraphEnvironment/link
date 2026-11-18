# Plan review for #472 (Plan agent, 2026-11-18), with verdicts

Spawned at the baseline, returned while Phases 1-2 were landing. Findings in its categories; each verdict says what was done.

## Blocker
- **B1** Phase 3's union breaks the validator's "set observation_exclusions to NULL" idiom, which `data-raw/habitat_variants_score.R` follows for absence sites. **Confirmed; fixed** before the review landed: that script nulls both tables, and the validator's message and `@param` name both.
- **B2** `data-raw/pretest_inputs.csv` had no row for `presence_groups.csv` or `observation_exclusions_link.csv`, so test-pretest.R fails and the gate refuses. **Confirmed; fixed:** presence groups map to segments and gradient; the link exclusions join the exclusions rows (observations, gradient). test-pretest.R passes.

## Gap
- **G1** Three data-raw scripts read the presence CSV by path and would skip the overlay. **Confirmed; fixed:** `query_habitat_thresholds_obs.R`, `query_habitat_thresholds_fiss.R`, `species_pooling_evidence.R` read through `lnk_load_overrides()`.
- **G2** Exclusion readers that bypass the key function; `release_include` read from the copy only. **Fixed:** `.lnk_observation_release_include_keys()` and `.lnk_observation_exclusion_rows()` serve the presence check, `wsg_species_presence_check.R` (incl. `recall.csv`) and `wsg_species_presence_map.R`. `data-raw/access_disagree_349.R` is #349's one-off record and is left as written.
- **G3** Nothing reports a link exclusion bcfishpass adopts. **Fixed:** `.lnk_sync_exclusions_redundant()`, reported by the sync as a retire note, tested offline (BOM copy included).
- **G4** Binding the two tables mixes logical and character columns. **Fixed:** rows are bound as text in the readers' columns; tested with a numeric-looking key.
- **G5** Docs the plan's lists left out. **Fixed:** tracker dictionary `decision`, RUNBOOK acc row and "What gets no token", vocabulary roxygen and comment, RUNBOOK §7, sync header, `default/README.md`, `default/overrides/README.md`, `research/species_presence.md`.
- **G6** `wsg_species_presence` in the sync stems list; offline redundancy test. **Fixed.**
- **G7** `regen_provenance.R` rebuilds `rules.yaml` and re-stamps copies. **Noted:** not run on this branch (checksums written directly); its file list now names the new files. Dropping copies from it is out of scope.

## Ordering
- **O1** Run the presence check after Phases 2-3 commit; decide on `--seed-tracker`. **Taken:** it runs from a clean tree after commit, without `--seed-tracker` (no tracker churn; pending stories would quote the copy's notes).
- **O2** ADMS/BULK main-vs-head mixes three changes. **Taken:** a digest difference would be bisected at the Phase 1 commit; the three records lie outside both groups' upstream.
- **O3** Concurrent edits. **Noted;** mutation checks run in a worktree.

## Assumption
- **A1** acc token does not move. **Agrees** with the in-code check (all five bundles).
- **A2** `config_hash` moves for five bundles. **Taken:** into NEWS and Owed.
- **A3** Only GUIC's exclusion moves the model (MESI SK, KOTL ST are absent cells). **Taken:** Owed corrected.
- **A4** Full column equality would refuse on any upstream column added; the copy has a BOM. **Fixed:** the link table needs `observation_key`, `data_error`, `release_exclude` only.
- **A5** "Sync dry run clean" defined. **Met:** upstream is still `3bd2824`; every copy clean in both bundles, no load error, no redundant row.
- **A6** No other declaration needed for a new `files:` key. **Agrees.**

## Scope
- **S1** Bundles with no `presence_groups.csv` still use groups in code. **Taken:** NEWS says so (`default_extrabreaks`, `default_rearbreaks` resolve no tokens and are not run).
- **S2** LARL GR: one overlay row merging the tracker's reason and `322389a3`. **Already so** in `build_overlay.R`; plan text updated.
- **S3** Decisions that agree with the copy get no overlay row. **Taken:** RUNBOOK says so.

## Acceptance
- **AC1** #431's `identical()` holds for species cells, not `notes`. **Reported** to the operator as the one call made without them.
- **AC2** The rule sentence was dropped. **Fixed:** each overlay reason now carries the review's rule; overlay regenerated from the pre-conversion commit in a worktree.
- **AC3** The issues ask for an acc row; none is needed. **Taken:** NEWS and PR body say why.
- **AC4, AC5** Covered.
