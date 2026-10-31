# Code-check round 3 — #402 presence check (branch at 5aabe8fe)

## Checklist read

Index read in full (`checklist_index.txt`). Full prose read: every H3 under `code-check.md` `## Mechanisms` (guard that fails toward pass; fixture that cannot reach the failure mode; a proxy is not the property; verification that reads its own output; a guard's scope, escape hatches, and remedies; a fix lands in one of two callers; restore the bug and prove the guard fires; shared working tree; a wrapper's exit is not the work; zero-length/empty/unset; the probe is broken before the world is; written data outlives the fix; serialization loses meaning silently; one fact derived twice). From `code-check-r.md`: `stats::aggregate()` has three silent behaviours; `nzchar(NA)`; `paste()` with zero-length; `sort()`/`order()` collate by locale; `read.delim()` quotes; Postgres row order; a `data-raw/` script must load the source tree; `match()` treats NA as a value; `$` partial-matches. Shell/spatial files: nothing in this diff's shape beyond the above.

## Mechanism

Round 1 and 2's defects, and the two new ones below, share one shape: **a sentence states a consequence the check never observed; it is derived from a neighbouring value the check did compute.** Round 2's lift sentence keyed "its records are dropped" to the cell's species instead of the records' species; round 2's research line keyed "bcfishpass's thresholds" to one bundle's values. This round's main instance keys "its barriers and mapping code are built" to `present_promoted` (what `lnk_presence()`'s groups say) instead of to the code path that builds mapping code (`lnk_pipeline_species()`, raw presence ∩ `cfg$species`). The second keys "(newest Y)" for the pre-1950 records to `year_newest_any`, the newest of *all* wild dated records. "A proxy is not the property" (code-check.md). Where it reaches: every story sentence that names a pipeline consequence (S6, S7), every doc sentence that restates S7 (research lines 10 and 55, CLAUDE.md, RUNBOOK), and every parameter-dependent wording that was only checked at the default parameters (S3's "newest", the dictionary's `flag` text).

## Findings

- **[severity: bug]** R/lnk_presence_check.R:322-326 — the promotion sentence "The %s group makes it present, so its barriers and mapping code are built." is false for all 114 rows it is emitted on (CH 12, CM 17, CO 17, PK 32, SK 34, CT 2). Mapping code (and access, persisted habitat, the access barrier views) are built for `active_species <- lnk_pipeline_species(cfg, loaded, aoi)` (`R/lnk_pipeline_run.R:225`, used at 279, 305, 329, 343, 355-356; `data-raw/wsg_recompute_one.R:55`, 176-194), which intersects `cfg$species` with the **raw** cell (`.lnk_wsg_species_present()`). `lnk_presence()`'s promotion reaches only `.lnk_pipeline_prep_minimal()`'s break-position sets (`R/lnk_pipeline_prepare.R:655-658`), and only for species in `cfg$species`; `default`'s `cfg$species` has no CT or DV (rules.yaml), so the 2 CT rows (FINL, LOMI) get nothing at all. Measured: `fresh_default.streams_mapping_code` for ADMS (PK absent, promoted by "salmon (CH, CO, SK)" per `disagreements.csv`) has 39,425 rows, 0 non-NULL `mapping_code_pk`; `streams_access.access_pk` is NULL on all 39,425. Consequence: the tracker tells the operator an absent salmon cell is already modelled, which argues for `keep` on 114 rows when the opposite is true. The same false claim is restated in `research/species_presence.md:10` ("The barrier sets and the mapping code read that"), `:55` ("so their barriers and mapping code are built"), CLAUDE.md #402 bullet ("Promotion (`lnk_presence()`) feeds the barrier sets and mapping code only"), and RUNBOOK §"The presence table is checked against the records" ("`lnk_presence()`'s promotion feeds the barrier sets and mapping code, not the filter"); `tests/testthat/test-lnk_presence_check.R:175` pins the sentence. What is true: promotion adds that species' post-lift barrier positions to the stream breaks when the species is in `cfg$species`; for salmon those positions coincide with the raw-present members' (same `access_gradient_max` 0.15 and same `observation_species`), so in `default` promotion changes little or nothing observable.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** R/lnk_presence_check.R:272-273 (used at 289) — `before <- sprintf("%d before %d (newest %d)", n_before_floor, year_min, year_newest_any)`: `year_newest_any` is the newest of every wild dated own record, kept ones included. On the `n_kept > 0` branch (reachable whenever `--n-min` > 1, which the driver accepts and `--seed-tracker` would write into the tracker) the parenthesis names a year after the floor. Reproduced in a worktree: records 1940, 2001, 2002 with `n_min = 3` give "Marked present; 2 counting records, fewer than the 3 the rule asks for (also 1 before 1950 (newest 2002), not counted)." Not emitted in the committed 351 rows (all at `n_min = 1`, S3 count 0). Same reach: the dictionary's `flag` description ("no record meets the rule" / "at least one record does") is the `n_min = 1` wording of a column the driver can fill at any `n_min`.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** research/species_presence.md:85 — "The salmon, steelhead and WCT values are bcfishpass's (`smnorris/bcfishpass@620dbe4`)." The count matches (5, 5, 1), the date floor does not: `lnk_barrier_overrides()` counts `o.observation_date >= '1990-01-01'` (`R/lnk_barrier_overrides.R:209`), bcfishpass `o.obs_dt > date('1990-01-01')` (`model_access_ch_cm_co_pk_sk.sql:86`, `model_access_st.sql:86`). bcfishobs holds 569 salmon and steelhead records dated exactly 1990-01-01 (CH 60, CM 43, CO 134, PK 44, SK 47, ST 241), which lift in `default` and not in bcfishpass. WCT: `default` floors at 1900-01-01, bcfishpass has no date test; 0 WCT records predate 1900, so no effect today. A one-clause qualifier fixes it; this is round 2's fix to the same sentence still asserting more equality than the code has.
  - **Rule:** code-check.md "A proxy is not the property"

Aside, outside this diff: RUNBOOK's pre-existing line just above the new subsection says RB lifts have "no date floor"; `lnk_barrier_overrides()` substitutes `1900-01-01` when `observation_date_min` is NA (line 144), so BT and RB do have one.

## (a) Every sentence `.lnk_presence_story()` can emit

Run over all 351 committed rows (rule columns added at 1 / 1950 / 1990): stories identical to `disagreements.csv` 351 of 351; tracker stories, flags and rule identical to `disagreements.csv` 351 of 351, every decision `pending`.

| id | sentence | emitted when | rows | true for every admitted row? |
|---|---|---|---|---|
| S1 | "Marked present with no record of X in the group." | present_unsupported, n_records 0, n_kept_pooled 0 | 12 | Yes (by the exact-code reading; VICT DV holds an ADV record, an accepted tradeoff reported in alias_sensitivity.csv) |
| S2 | "Marked present; N records of X, none counting: <releases, excluded, undated, before Y (newest Z)>." | present_unsupported, n_kept 0, n_records > 0 | 12 | Yes: own not-kept = excluded + release + undated + pre-floor exhaustively; with n_kept 0 every wild dated record is pre-floor, so "newest" is pre-floor |
| S3 | "Marked present; K counting record(s), fewer than the N the rule asks for (also …, not counted)." | present_unsupported, n_kept > 0 (only n_min > 1) | 0 | **No**: "(newest Z)" is `year_newest_any` (finding 2) |
| S4 | "Not marked present; a single record (YEAR; SOURCE)" | absent_recorded, n_kept 1 | 82 | Yes (sources over kept incl. pooled; " (1)" stripped) |
| S5 | "Not marked present; N records since Y0, A to B, M since Y1 (sources)" | absent_recorded, n_kept > 1 | 245 | Yes; all three years read from the row |
| P1 | ", a D record pooled into X" | n_kept 1, n_kept_pooled 1 | 2 | Yes |
| P2 | ", all of them D records pooled into X" | n_kept_pooled > 0, n_kept_own 0 | 6 | Yes (8 BT rows = P1 + P2, all pooled DV only) |
| P3 | ", k of them D records pooled into X" | n_kept_pooled > 0, own > 0 | 0 | Yes (unreached) |
| S6 | "While it reads absent, its own X records are dropped before the observation breaks and from the barrier lifts of L." | absent_recorded, n_kept_own > 0, lift_readers not NA | 317 | Yes: prep filter reads the raw cell (`.lnk_pipeline_break_obs_species`), `observations_province` keeps each record by its own group's raw cell, `default` breaks on `observations` (`top_per_species`), every reader in L has `observation_threshold` > 0 so `lnk_barrier_overrides()` processes it. Omitted (not false) for FINL CT and LOMI CT (CT has no reader), and wherever own records exist but none counts |
| S7 | "The G (members) group makes it present, so its barriers and mapping code are built." | absent_recorded, promoted_by not NA | 114 | **No** (finding 1) |
| S8 | "Also N releases, M excluded, not counted." | absent_recorded with releases or exclusions | 60 | Yes (omits undated / pre-floor: omission, not false) |
| S9 | "Group note: \"…\"." | group_notes not NA | 57 | Yes |

## (b) Numbers and quantified claims

### research/species_presence.md

| line | claim | source | verdict |
|---|---|---|---|
| 3 | bcfishobs 375,962 rows, newest valid 2026-10-10, link 6aabb6f0, 351 flagged, every one pending | stamp.txt; tracker decisions | ✓ |
| 7 | 246 groups by 13 species | cells.csv 3,198 = 246 × 13 | ✓ |
| 9 | unmarked species: no break, no code 2, no lift, own group or any other | prep_observations / prep_obs_province / access walk on observations_province | ✓ |
| 9 | `lnk_pipeline_species()` picks the species to classify | lnk_pipeline_species.R | ✓ but incomplete: it also picks access and mapping code |
| 10 | "The barrier sets and the mapping code read that" (promotion) | lnk_pipeline_run.R:225, 305, 355; prepare.R:655 | **✗ mapping code** (finding 1) |
| 20 | bcfishpass's filter tests the raw code | load_observations.sql:116 `array[o.species_code] && species_codes` | ✓ |
| 22 | source test 74,495; with source_ref tests 75,739; of 375,962 | SQL on bcfishobs | ✓ |
| 23 | source holds 1007 and 9999 | SQL: 1007 ×1, 2028 ×1, 2080 ×6, 9999 ×178 | ✓ ("holds", not "only") |
| 24 | DV into BT in Fraser, Mackenzie, Columbia, Skeena above Hazelton | species_pooling.csv | ✓ (Kootenay row is a Columbia subregion) |
| 24 | pipeline does not apply species_pooling.csv; BT lifts count DV via observation_species | grep: only lnk_log and the check call it; parameters_fresh BT `BT;DV` | ✓ |
| 30 | 351 of 3,198 | summary.csv / cells.csv | ✓ |
| 34-46 | table (present, present-no-record, absent-recorded, one record, promoted) | recomputed from cells.csv / disagreements.csv | ✓ all 65 cells |
| 48-50 | 24 present-unsupported: 12 no record (6 UDEN, KTSU CH/ST note), 12 on releases (8) or undated (4); LPRO RB 90 all releases; UEUT BT/CT/DV 2 undated each | disagreements.csv | ✓ (no pre-1950-only or excluded-only cells) |
| 53 | 82 / 89 / 156; 238 since 1990 | disagreements.csv | ✓ |
| 54 | KO 137, median 11, 92 of the 156, 52 with releases | disagreements.csv | ✓ |
| 55 | 114 promoted: PK 32, SK 34, CM 17, CO 17, CH 12, CT 2 | disagreements.csv | ✓ counts; **✗ "so their barriers and mapping code are built"** (finding 1) |
| 56 | ST 34, none promoted, 17 single | disagreements.csv | ✓ |
| 57 | Mackenzie 29 flags, 26 absent, 7 salmon/ST, one or two records, 1969-1998, the listed cells | disagreements.csv (region) | ✓ |
| 58 | BT's 8 flags all pooled DV alone | n_kept_own 0, n_records 0 on all 8 | ✓ |
| 62-73 | 132,502 records, 157 codes, the eight codes and counts | stamp.txt; SQL 132,502 | ✓ |
| 75 | 4 flags: FINA ST, UFRT ST, MFRA BT, VICT DV | alias_sensitivity.csv | ✓ |
| 79 | an add/remove moves the `acc` token; notes does not | (not re-derived; CLAUDE.md #414 agrees) | not re-checked |
| 85 | 5 since 1990 for CH…KO; 1 for BT, RB, WCT | parameters_fresh.csv | ✓ |
| 85 | salmon, steelhead, WCT values are bcfishpass's | model_access_*.sql; lnk_barrier_overrides.R:209 | **✗ date floor `>=` vs `>`, 569 records** (finding 3) |
| 85 | bcfishpass: no GR/KO model; RB in CT/DV/RB with no threshold; BT lift counts BT, salmon, ST | bcfishpass @620dbe43 model/01_access/sql | ✓ |

### CLAUDE.md #402 entry

| claim | verdict |
|---|---|
| 351 rows (24 / 327) | ✓ |
| tracker undeclared; pretest maps it `none`; dictionary tested by path | ✓ (pretest_inputs.csv row; test-dictionaries.R) |
| unmarked cell discards records everywhere | ✓ |
| "Promotion feeds the barrier sets and mapping code only; 114 of the 327" | 114 ✓; **mapping code ✗** (finding 1) |
| pipeline drops SST 404, WST 358, ADV 79, ABT 12, BT/DV 57, DV/BT 52, RB/CT 23; 4 flags | ✓ stamp.txt |
| lifts: 5 since 1990 for …, 1 for BT, RB, WCT | ✓ |
| one exclusion helper for prep, validator, check | ✓ diff |

### RUNBOOK new subsection

| claim | verdict |
|---|---|
| a record survives only where its own group marks its species `t` | ✓ |
| "promotion feeds the barrier sets and mapping code, not the filter" | **✗ mapping code** (finding 1) |
| rule: one record since 1950, releases tagged as bcfishpass, exclusions, CT folded, pooling | ✓ |
| `add`/`remove` moves `acc` token; tracker undeclared | ✓ (as CLAUDE.md) |
| SST, WST, ADV, ABT, BT/DV, DV/BT, RB/CT never count | ✓ |

### data-raw/logs/presence_check_402/README.md

| claim | verdict |
|---|---|
| produced at 6aabb6f0 | ✓ stamp; no R/, data-raw/*.R or tests change between 6aabb6f0 and HEAD |
| first run (feaa408c) flagged the same 351; later rounds changed only stories; other CSVs byte for byte | ✓ first committed output (be8f5319) vs HEAD: only disagreements.csv changed, and only its `story` column (325 rows); cells/groups/summary/alias untouched |
| file table (6 files) | ✓ matches disk |
| 24 / 327; 3,198 cells; 4 alias cells; 39 cells, 5,423 records | ✓ stamp.txt |

## (c) Values restated in two places

| value | places | verdict |
|---|---|---|
| dictionary consumed_by refs (392-400) | dictionary CSV vs R/lnk_presence_check.R | ✓ test-dictionaries.R passes at HEAD (118 pass, 0 fail) |
| rule n_min / year_min / year_recent | `.lnk_presence_check()` defaults, row columns, driver, `.lnk_presence_rule()`, tracker `rule`, research, CLAUDE.md, RUNBOOK | ✓ one source since round 2 (rows carry them; driver reads `res$n_min[1]`) |
| exclusion rule | prep, validator, check | ✓ one helper |
| release tagging | R (`.lnk_presence_check`) vs SQL cross-check vs bcfishpass load_observations.sql | ✓ same three tests plus `release_include` |
| CT alias set | check vs `.lnk_pipeline_break_obs_species()` vs SQL cross-check | ✓ CCT, ACT, CT/RB in all three |
| promotion groups | `eval(formals(lnk_presence)$groups)` vs pipeline's default call | ✓ |
| presence truthiness | check raw uses `.lnk_wsg_species_present` (== "t") as the filter does; promoted uses `lnk_presence` (`.lnk_presence_truthy`) as prep_minimal does | ✓ consistent with each consumer; CSV holds only "t" and "" today |
| presence consequences (what promotion builds) | story S7, research 10/55, CLAUDE.md, RUNBOOK vs lnk_pipeline_run / prep_minimal | **✗** (finding 1) |
| log file list | README table vs directory | ✓ |
| test files | test-lnk_presence_check.R 79 pass; test-dictionaries.R 118 pass (NOT_CRAN=true, worktree at 5aabe8fe) | ✓ |
