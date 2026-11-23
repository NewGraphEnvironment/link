Plan review for #501 (backlog move 16), Plan agent, 2026-11-22, against origin/main be06e2b4

Blockers raised: 1
Owner forks: 4

Each finding was probed in the code or data before it was folded in. Verdicts follow.

## Blocker

1. **Under (b), the presence check flags RB in groups where the pipeline never applies the rule.** The check pools as if every species were present (`R/lnk_presence_check.R:76-82`), so a province `RB ← ST` row would flag `absent_recorded` RB wherever ST records count. The pipeline pools only where RB is present.
   - **Verified** in the code.
   - **Folded:** Phase 1 counts these groups. The choice is an owner fork, written as Open decision 7 (recommended: count RB's own records only).

## Gap

2. **Dating of pooled records.** A pooled record takes RB's floor (none), so undated ST records cut and set code 2. The lift still drops undated records (`R/lnk_barrier_overrides.R:181-182`, empty floor = `1900-01-01`).
   - **Verified.**
   - **Folded:** Open decision 1's costs, and Phase 2's test.
3. **The RB lift reads pooled records, and RB's top-per-line becomes the higher of the RB and ST tops**, so segments move in groups holding both species.
   - **Accepted.**
   - **Folded:** decision 1's costs; Phase 1 counts the groups whose top moves; Phase 5 checks `species_code_recorded = 'ST'` on RB lifts.
4. **The SST/WST refusal protects three readers** (`.lnk_record_aliases_everywhere()`, `.lnk_presence_measures()`, `data-raw/wsg_species_presence_map.R`).
   - **Verified:** the refusal is at `:231-236`, the drop at `:257-262`.
   - **Folded:** written as an owner fork, Open decision 8 (recommended: split out).
5. **Phase 1's extension is an R change.** `.lnk_presence_measures()` matches barriers on the record's own code.
   - **Accepted.**
   - **Folded:** Phase 1 names it as R, with a test and a `pretest_inputs.csv` row.
6. **The `ct_dv_rb` note was mostly moot.** RB is already present in the pending CT groups. Promotion is new only in 16 groups, and LPRO's DV cell keeps RB's breaks after an RB removal.
   - **Verified:** the 16 groups were counted from the copy plus the overlay. BEAV BLUR CHUK COAL DEAL DEAR FROG JENR KTSU KUSR LKEC LRAN MBNK NBNK SWIR TOAD.
   - **Folded:** decisions 2 and 5, and the choice of Phase 5's third group.

## Assumption

7. **KO cells do not move the cut token.** The record-rule digest is resolved with every species present.
   - **Verified** (`R/lnk_observation_records.R:278-292`).
   - **Folded:** corrected in decision 3. The KO choice itself stays the owner's fork.
8. **Phase 1 needs a current province-wide build.**
   - **Accepted.**
   - **Folded:** Phase 1 states the host and build and stamps its `run_uid`.

## Tokens

9. **Vocabulary rows are keyed by spec, not by bundle.** All four bundles share `acc-v7`. Under (b) there is one `cut-full-top-3`. `default_minimal` has no record term, so `cut-min` and `grad-parent` stay. Under (a) no cut token moves.
   - **Verified** (`R/lnk_vocabulary.R:149-153`).
   - **Folded:** the Phase 4 bullet is rewritten.

## Tests missed

10. Missed pins: `test-lnk_vocabulary.R:74-87`, `test-lnk_log.R:744`, `test-lnk_pipeline_species.R:124-129`. Docs: `R/lnk_pipeline_species.R:50` and `research/output_vocabulary.md:33`.
    - **Accepted.**
    - **Folded:** Phase 4.

## Ordering

11. **The check re-run must come after the unpause,** because the stories and the `modelled` column read `cfg$species`.
    - **Accepted.**
    - **Folded:** the `species_modelled.csv` edit is the first step of Phase 3.
12. **Token pins stay red between phases.**
    - **Accepted.**
    - **Folded:** Validation uses `/code-check branch`.
13. **Phase 5 needs a middle build**, so each difference has one cause.
    - **Accepted.**
    - **Folded:** Phase 5 builds three states.

## Scope (owner)

14. **Split the alias change and option (c)** into issues naming move 16.
    - **Owner fork:** Open decision 8.
15. **Splitting #402's non-RB rows into a later PR** means a second `acc` token before move 17.
    - **Owner fork:** added to decision 5.
16. **KO's rows** stay the owner's call.
    - **Owner fork:** decision 3, corrected.

## Acceptance

- **Accepted, all of them:**
  - the RB flag count before and after;
  - the SST/WST and undated-ST tests;
  - comparison with a pre-pause build;
  - a province-wide count of groups whose cuts move;
  - `pretest_inputs.csv:123` (overlay to `observations` and `obs_upstream`).
- **Folded into:** Phases 2, 3 and 5.

## Files the plan names

R/lnk_observation_records.R
R/lnk_species_pooling.R
R/lnk_presence_measures.R
R/lnk_presence_check.R
R/lnk_barrier_overrides.R
R/lnk_vocabulary.R
R/lnk_config.R
R/lnk_pipeline_species.R
R/lnk_pipeline_prepare.R
R/lnk_pipeline_break.R
data-raw/wsg_species_presence_check.R
data-raw/wsg_species_presence_map.R
data-raw/pretest_inputs.csv
data-raw/habitat_diff_segments.R
data-raw/streams_parent_build.R
inst/extdata/vocabulary.csv
inst/extdata/wsg_regions.csv
inst/extdata/configs/default/species_modelled.csv
inst/extdata/configs/default/species_pooling.csv
inst/extdata/configs/default/parameters_fresh.csv
inst/extdata/configs/default/presence_groups.csv
inst/extdata/configs/default/wsg_species_presence_review.csv
inst/extdata/configs/default/overrides/wsg_species_presence_overlay.csv
inst/extdata/configs/dictionary_species_modelled.csv
inst/extdata/configs/dictionary_species_pooling.csv
tests/testthat/test-lnk_config.R
tests/testthat/test-lnk_observation_records.R
tests/testthat/test-lnk_barrier_overrides.R
tests/testthat/test-lnk_csv_sync.R
tests/testthat/test-lnk_vocabulary.R
tests/testthat/test-lnk_pipeline_species.R
tests/testthat/test-lnk_log.R
RUNBOOK.md
research/species_presence.md
research/output_vocabulary.md
