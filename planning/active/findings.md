# Findings — Backlog move 11: What blocks access at a barrier (#479)

## Issue context

**If we do it:** barrier rules are config and compared as scenarios, dams can be species-dependent, and copies of one barrier agree. **If we never do:** what blocks is fixed in code and scenarios cannot be compared.

Move 11 of link's backlog, [`planning/backlog.md`](../backlog.md). Run `/planning-init <this issue>`: one phase per batch, one PR. `/gh-pr-merge` ticks the move on merge.

### Batch 16: What blocks access at a barrier

**Why here:** one `acc` row and one provincial re-model.

#201 (carry barrier ingredients and classify access late, per species, with an evidence-based dam override), #83 (species-dependent dam handling), #341 (barrier rules as config, compared as scenarios on #321's per-crossing totals) and #386 (copies of one barrier held by several groups can disagree under group-filtered controls) and #236 (several observation-lift rules per species, each with its own evidence, count and date; joined 2026-11-22, it shares this batch's `acc` row). Touches `R/lnk_barriers_unify.R`, `R/lnk_barriers_views.R`, `R/lnk_barriers_emit.R`, `R/lnk_pipeline_access.R`, `R/lnk_pipeline_prepare.R`, `R/lnk_barrier_overrides.R`, `inst/extdata/configs/default/parameters_fresh.csv`, a new `parameters_barrier_rules.csv`, `data-raw/study_area_verify.sql`. Gate: a deliberate departure from bcfishpass (dams per species, evidence over dams); #386 owner-only persistence or province-wide controls. One `acc` row and one provincial re-model.

| issue | title |
|---|---|
| #201 | Rethink blocks_species: carry barrier ingredients, classify access late + per-context; add evidence-based dam-override |
| #83 | Species-dependent dam-class handling in dimensions.csv |
| #341 | Barrier rules as config: compare scenarios of what counts as a barrier at a crossing |
| #386 | Copies of one barrier held by several groups can disagree under group-filtered controls |
| #236 | Several observation-lift rules per species (multi-rule overrides) |

The umbrella's one comment is the dispatch claim. None of the five member issues has a comment (read 2026-11-24).

## Where each rule lives today (read 2026-11-24 at `c7abea13`)

- **The human-made barrier set** is `barrier_status IN ('BARRIER', 'POTENTIAL')` in four places: `R/lnk_barriers_emit.R` (anthropogenic, PSCIS, dams) and `R/lnk_barriers_unify.R` (the anthropogenic source). `barrier_status` itself comes from `R/lnk_crossings_union.R` (PSCIS's `current_barrier_result_code`, CABD's passability code, the modelled type) and the per-row override files (`R/lnk_crossings_apply_overrides.R`, `R/lnk_pipeline_load.R`).
- **Streams cut at every crossing whatever its status** (`R/lnk_pipeline_break.R`), and fresh's classify labels crossings `barrier` / `potential` / `passable` / `unknown` under `label_block = "blocked"` (`R/lnk_pipeline_classify.R`), so no crossing blocks habitat at classify time.
- **Access** reads `barriers_<sp>_access` (`R/lnk_barriers_views.R`): natural sources only, minus `barrier_overrides` by position within 1 m and species, user-definite exempt. `blocks_species` on the persisted row supplies the gradient class test and nothing else for access.
- **Lifts** are one rule per species from `parameters_fresh.csv` (`R/lnk_barrier_overrides.R`), counted over every group's records (`observations_province`). The same `observation_date_min` is the species' record floor under `observation_record_date: lift_floor` (`R/lnk_observation_records.R`), and a rule whose listed species have another floor is refused there.
- **Gradient barriers are found along the whole of every line a group touches** (`.lnk_pipeline_prep_gradient()`: `streams_blk`, then `fresh::frs_break_find()`), and `lnk_barriers_unify()` persists every one under the group's code. Falls, subsurface flow, user-definite rows and crossings are already filtered to the group.
- **Controls** (`user_barriers_definite_control.csv`) are filtered to the group's rows by the CSV's `watershed_group_code` in `.lnk_pipeline_prep_load_aux()`. They prune gradient rows (`barrier_ind` false), skip subsurface rows, and lock a position against observation lifts (`barrier_ind` true, per species through `observation_control_apply`).
- **Habitat confirmations** are written whole, not per group, so a habitat lift already reads every group's rows.
- **The evidence table's key** is `(blue_line_key, downstream_route_measure, species_code, watershed_group_code, evidence, evidence_key)` (`R/lnk_persist_init.R`). The habitat export carries `barriers` and `barrier_overrides` per group and not the evidence table.
- **The `acc` spec** (`R/lnk_vocabulary.R`, `.lnk_vocabulary_spec_acc()`) digests `cfg$species`, the seven access columns of `parameters_fresh`, the presence table, `observation_upstream`, the record rule, the presence groups and the code-held class map. Live rows: `acc-v7` (`default`), `acc-bcfp-5`.
- **`lnk_pipeline_run()` refuses a config with no vocabulary row**, so a scratch bundle that changes an `acc` input cannot be modelled without minting a token. The measurements in Phases 2 and 3 are designed around that.
- **`lnk_thresholds()`, `lnk_score()`, `lnk_source()`** are exported and called by nothing on the modelling path; the README does not name them.

## Probes (2026-11-24, this host: `fresh_default`, 241 groups at 0.78.2; local FWA)

| measure | value |
|---|---|
| gradient barrier positions | 7,241,875 |
| held by more than one group | 1,224 positions, 3,087 rows, up to 13 holders |
| of those rows, held by a group that does not own the segment | 1,864 |
| control rows in `default` | 238 (67 true, 171 false; FALLS, GRADIENT, SUBSURFACEFLOW) |
| control rows filed under a group that does not own the position | 7 |
| control rows within 1 m of a multi-held gradient position | 1 |

The first three match #386's numbers from the 2026-10-26 build. The control counts are new. They are a planning probe on a build two `acc` rows old: Phase 1 re-measures and commits the script.

## Errors Encountered

| Error | Resolution |
|-------|------------|
