# Task: Backlog move 4: default's presence table as bcfishpass's copy plus an overlay (#472)

**If we do it:** every departure from bcfishpass's presence table is an overlay row with its reason, link can exclude a record it finds wrong, and the presence groups live in the bundle. **If we never do:** the table stays a hand-edited fork, and a wrong record stays counted until bcfishpass drops it.

Batch 5 of planning/backlog.md: #402, #431, #436, #292. One PR.

## Context

`default`'s `wsg_species_presence.csv` is a hand-edited fork of bcfishpass's. Compared with the
`bcfishpass` bundle's copy (`smnorris/bcfishpass@3bd2824`) it differs in **122 species cells**
(110 added, 10 removed, UTRE CH and LARL GR held absent) plus the `ko` column, and **every one of
the 122 is a decided row in `wsg_species_presence_review.csv`** (110 add, 10 remove, 2 keep).
QUES ST already matches upstream (added by #435). Since #429 the `bcfishpass` bundle's table is a
synced copy with link's cells in an overlay; this move does the same for `default`, lets a bundle
exclude a record bcfishpass has not listed (#436), and moves `lnk_presence()`'s hard-coded groups
into the bundle (#292). One PR, release 0.86.0.

Measured while planning: the `acc` spec hashes only the presence **species** columns (not `notes`),
exclusions are not in any spec, and the groups enter it as a string. So with every cell kept, the
move changes **no output token**: `default` stays `acc-v6`, `bcfishpass` `acc-bcfp-5`. Verified
in-code by the tests below, not assumed.

## Decided at the gate (operator, 2026-11-18)

- **#436:** a link-owned exclusions file beside the copy, unioned by `.lnk_observation_exclusion_keys()`. An offer of the three rows upstream is drafted, posted only on your word.
- **UTRE CH:** kept absent, as an overlay row with the tracker's reason. No new `acc` row.
- **Rainbow trout's return:** its own link issue, drafted for your review before filing; the 3 pending RB tracker rows point at it. RB stays paused here.
- **#402 stays open:** the PR relates to it without closing it; its body is edited to list what is left (the 13 non-KO/RB pending rows; the KO rows held by #432).
- **(mine) `notes`:** the loaded `notes` column becomes the copy's. link's "added PK (#402 review…)" notes were pointers to the tracker, and the overlay's `reason` now carries each cell's reason. Nothing models on `notes`; the presence check's `group_notes` reads it.

## Phase 1: presence groups in the bundle (#292)

- [x] `presence_groups.csv` (`group_code,species_code`; `salmon`: ch cm co pk sk; `ct_dv_rb`: ct dv rb) in `bcfishpass` and `default`, declared under `files:` (enters `config_hash`), provenance entries, a `dictionary_presence_groups.csv` covered by `tests/testthat/test-dictionaries.R`
- [x] `.lnk_presence_groups(loaded)` in `R/lnk_presence.R`: the bundle's groups as the named list `lnk_presence()` takes, else its formals default (bundles with no file: `default_extrabreaks`, `default_rearbreaks`, custom); refuses an empty or malformed file
- [x] Every caller passes it: `R/lnk_pipeline_run.R:298`, `R/lnk_pipeline_prepare.R:632`, `R/lnk_presence_check.R:221`, `R/lnk_vocabulary.R:216` (the `presence_groups=` payload), `data-raw/wsg_recompute_one.R:64`, `data-raw/habitat_variants_build.R:815`
- [x] Tests: each live bundle's `acc` spec is unchanged (`lnk_vocabulary_resolve()` still matches `acc-v6` / `acc-bcfp-5`); a changed group file changes the spec; a caller grep test that no pipeline path calls `lnk_presence()` without `groups =`

## Phase 2: default's presence table as the copy plus an overlay (#431)

- [x] `data-raw/logs/presence_overlay_431/build_overlay.R` (run once, kept as the record): copy `bcfishpass/overrides/wsg_species_presence.csv` byte for byte into `default/overrides/`; write `default/overrides/wsg_species_presence_overlay.csv` from the tracker's decided rows that differ from the copy (`reason` = the story's opening sentence, which states the decision's reason; `issue` = the tracker's), the four `ko` rows (#106, as the `bcfishpass` overlay words them), and LARL GR's tracker reason merged with `322389a3`'s into one row; stop unless the overlaid species cells equal today's table for all 246 groups
- [x] `default/config.yaml`: `overlay:` on `wsg_species_presence`; the copy's provenance becomes `source: https://github.com/smnorris/bcfishpass`, `path: data/wsg_species_presence.csv`, `upstream_sha: 3bd2824`; an overlay provenance entry; checksums regenerated (`data-raw/regen_provenance.R`, whose file list is updated)
- [x] Tests: `test-lnk_csv_sync.R` flips (default's presence is now a sync target); loaded `default` and `default_tuned` presence species cells identical to the pre-conversion table (digest pinned in the test); every overlay row carries an issue
- [x] Sync dry run clean (`data-raw/sync_bcfishpass_csvs.R`), and no overlay row redundant (`.lnk_sync_overlay_redundant()`)
- [x] RUNBOOK §7 "Copies and overlays" and "The presence table is checked against the records": default's table is a copy, decisions land as overlay rows

## Phase 3: a record bcfishpass has not listed can be excluded (#436)

- [x] `default/overrides/observation_exclusions_link.csv`, the copy's columns, the three rows (`091612fd01` GUIC CH, `284b315bd7` MESI SK, `ef68279063` KOTL ST) with `data_error = t`, reviewer, date, the evidence path in `source_1` and the reason in `notes`; declared under `files:` as `observation_exclusions_link`, provenance `link (hand-authored; link#436)`
- [x] `.lnk_observation_exclusion_keys()` (`R/lnk_pipeline_prepare.R:362`) takes the union of both tables, requiring `observation_key`, `data_error` and `release_exclude` in the link rows and binding both as text (review A4, G4)
- [x] Tests: a key in the link rows is excluded by prep, the validator (`R/lnk_habitat_validate.R:792`) and the presence check (`R/lnk_presence_check.R:128`) alike; `cut` and `acc` specs unchanged
- [x] Draft the upstream offer of the three rows (shown here, nothing posted)

## Review folds (Plan review, `review-plan.md`)

- [x] Pre-run gate map rows for the new files (B2); presence read through the loader in three scripts (G1); shared exclusion-row and release-include helpers (G2); sync reports a link exclusion upstream adopts (G3); docs (G5); the review's rule in every overlay reason (AC2)

## Phase 4: measure, record, release

- [x] Re-run `data-raw/wsg_species_presence_check.R` (DB): the decided rows drop out of its flags and the three records count nowhere; commit its log (#402 plan step 3)
- [x] Model ADMS and BULK under `default` at `main` and at the branch head into scratch schemas on local fwapg: `streams`, `streams_access`, `streams_mapping_code` identical (#292's acceptance). Model GUIC the same way and report what excluding its CH record moves (code 2, lifts)
- [x] Draft the rainbow-trout issue for your review; on approval file it and point the 3 RB tracker rows at it (filed as #497 on the operator's word, 2026-11-18)
- [x] Edit #402's body: what this move did and what is left
- [x] NEWS, DESCRIPTION 0.86.0, `CLAUDE.md` status block, RUNBOOK touched sections; evidence under `data-raw/logs/presence_overlay_431/` with its README

## Owed at the end (reported, done after merge)

- [ ] The pre-run gate runs again before the next provincial run (`R/` and `inst/extdata/` changed)
- [ ] GUIC, and the groups whose code 2 or lifts read its records, re-model at the next provincial run (its CH exclusion; MESI SK and KOTL ST are absent cells, so their exclusions move no model output; no token moves)
- [ ] `config_hash` moved for `default`, `default_tuned`, `default_minimal`, `default_parent` and `bcfishpass`: earlier builds read as another bundle in `recompute_readers_check.R` and the export until re-modelled (already owed: the current builds are `acc-v5`)
- [ ] The upstream offer of the three exclusions, if you give the word

## Validation

- [x] Tests pass (6,156 pass; 3 fail, all failing on main too: #493's test and two lnk_wsg_resolve closure tests)
- [x] `/code-check` clean (once over the branch with `/code-check branch`): 3 rounds, 4 findings fixed, ended on an enumeration of the 15 exclusion readers (review-round1..3.md)
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved: the `acc` spec match per bundle (no token moves); the pinned digest of the loaded presence species cells (conversion changes no cell); the build script's own stop on any cell mismatch; the sync dry run; the exclusion-key test across its three readers; ADMS and BULK model digests before and after; the presence check re-run.

