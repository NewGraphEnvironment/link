# Findings — Backlog move 4: default's presence table as bcfishpass's copy plus an overlay (#472)

## Issue context

Move 4 of link's backlog (`planning/backlog.md`), batch 5: #402 (the presence check and its
tracker), #431 (`default`'s presence table as bcfishpass's synced copy plus an overlay), #436
(exclude a fish record bcfishpass has not listed: three data errors from #402's review), #292
(move `lnk_presence()`'s hard-coded presence groups into the bundle, under `config_hash`).
Gate in the issue: #436's option; UTRE CH and QUES ST; whether rainbow trout's return to
`default` gets its own issue. knowledge#132 (move 9) and knowledge#148 (move 8) wait on it.

## Measured at the plan gate (2026-11-18, main db4a7710)

- `default`'s table against the `bcfishpass` copy (3bd2824): 246 groups both, 122 species cells
  differ (110 t in default only, 12 t in the copy only: UDEN ch cm co pk sk st, UTRE ch,
  LNTH ct, THOM ct, VICT dv, BULL gr, LARL gr), plus `ko` (4 groups t). `notes` differs on 80
  rows (link's "added X (#402 review …)" pointers).
- All 122 are decided rows in `wsg_species_presence_review.csv`: 110 add, 10 remove, 2 keep
  (UTRE CH, LARL GR). QUES ST is t in both (added by #435), so #431's "QUES ST" item is moot.
- Tracker decisions: add 111 (incl. QUES ST), keep 76, remove 10, pending 154 (KO 138, RB 3,
  BT 8, CT 4, ST 1). Every decided story opens with its reason.
- The `acc` spec (`.lnk_vocabulary_spec_acc()`, R/lnk_vocabulary.R) hashes the presence species
  columns only (not `notes`), the record map, and `presence_groups=` built from
  `formals(lnk_presence)$groups`. Exclusions are in no spec.
- `.lnk_sync_targets()` picks a copy by provenance `source` = bcfishpass, so the sync needs no
  code change; `test-lnk_csv_sync.R:56` asserts default's presence is not a target (flips).
- `lnk_presence()` callers: R/lnk_pipeline_run.R:298, R/lnk_pipeline_prepare.R:632,
  R/lnk_presence_check.R:221, R/lnk_vocabulary.R:216, data-raw/wsg_recompute_one.R:64,
  data-raw/habitat_variants_build.R:815.
- `.lnk_observation_exclusion_keys()` (R/lnk_pipeline_prepare.R:362) readers: prep (332),
  validator (R/lnk_habitat_validate.R:792), presence check (R/lnk_presence_check.R:128),
  data-raw/wsg_species_presence_check.R.
- Bundles extending default: default_tuned, default_minimal, default_parent.
  default_extrabreaks, default_rearbreaks and bcfishpass are `extends: ~`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| A mutation check restored its file with `git checkout`, which also discarded the uncommitted Phase 1 edit to that file | Restored from the copy taken before the mutation; further mutation checks run in a `git worktree` (CLAUDE.md, "Make a reviewer's copy with `git worktree`") |

## Phase 2

- Every one of the 80 notes that moved was a pointer to the tracker ("added PK (#402 review …)"); none carried link-original text. UDEN now shows the copy's note "salmon/steelhead added as test for Ulkatcho" while the overlay removes those cells, each overlay row saying why.
- The overlay's reason is the decision plus the story's opening sentence (four distinct openings for the 110 adds).
| test-dictionaries.R refs into R/lnk_presence.R went stale when roxygen lines were added above them in Phase 1, and the Phase 2 commit went in before the failing result was read | Refs corrected in a follow-up commit; read each test result before committing |
