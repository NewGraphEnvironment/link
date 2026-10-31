# Code-check round 4 — #402 presence check (branch at c6a12c5c)

## Checklist read

Index read in full (`checklist_index.txt`). Full prose read: `code-check.md` `## Mechanisms` (guard that fails toward pass; fixture that cannot reach the failure mode; a proxy is not the property; verification that reads its own output; a guard's scope, escape hatches, and remedies, including "Compression runs both ways" and the enumeration-termination paragraph). Headings applied from the index for patterns this diff uses: `code-check-r.md` "Postgres row order is never fixed…", "`match()` treats NA as a matchable VALUE", "`nzchar(NA)` is TRUE", "`sort()` and `order()` collate by `LC_COLLATE`", "A `data-raw/` script must load the source tree", "`read.delim()` quotes by default"; nothing in the shell or spatial files matches this diff's shape.

Method: worktree at HEAD (`c6a12c5c`, removed after), `NOT_CRAN=true`, `pkgload::load_all()`; read-only SQL on local fwapg; bcfishpass read at `620dbe43`.

## Findings

- **[severity: fragile]** RUNBOOK.md:645-646, tests/testthat/test-dictionaries.R:303-304, CLAUDE.md:21, research/species_presence.md:81 — the reason given for leaving the tracker undeclared says a review edit would make "`recompute_readers` and the export refuse that run" (RUNBOOK), "refuse earlier runs' recomputes and exports" (test comment), "make `recompute_readers` refuse that run's groups and stop the export publishing it" (CLAUDE.md, research). Two parts are false. (1) The export never refuses on a changed `config_hash`: `.lnk_export_runs()`'s skip reasons (R/lnk_scenario_export.R:281-292) do not test the hash against today's bundle; `.lnk_export_bundle()` (:576-596) still exports the run and only withholds the bundle files, writing `reason = "bundle has changed since the build"`, and `.lnk_export_model()` (:1228-1239) writes `model` NA. The run's habitat is published. (2) `recompute_readers_check.R:141-143` refuses the run's *outside readers* (`config_changed_since_run` → every reader named, not recomputed); the run's own groups still recompute. The decision stands on the readers check alone; the export consequence is inferred from "the hash changes" rather than read from the export code. CLAUDE.md/research's "stop the export publishing it" is true only if "it" means the bundle files, not the run; RUNBOOK's and the test comment's wording has no such reading.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** research/species_presence.md:85 — "569 salmon and steelhead records dated exactly 1990-01-01 count toward a lift in link and not in bcfishpass." 569 is the raw `bcfishobs.observations` count (CH 60, CM 43, CO 134, PK 44, SK 47, ST 241, verified). Lifts read `<schema>.observations_province`, which keeps a record only where its own group marks its species (the mechanism this branch documents): 561 survive it (CO 132, PK 42, SK 45, ST 239); 8 sit in groups whose cell is not marked, 0 are excluded. The number is a proxy (records in the source) for the property claimed (records the lift reads). "561" or "up to 569" fixes it.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** research/species_presence.md:7 and :12 — "A cell marked `t` makes the species part of the model in that group" and "a species modelled where nothing shows it lives there". False for CT and DV, two of the 13 columns (306 marked cells): `default`'s `cfg$species` is BT CH CM CO PK SK ST WCT KO RB GR, and `lnk_pipeline_species()` (`intersect(cfg$species, present)`) never classifies, accesses or codes CT or DV in any group. 8 of the 24 present_unsupported rows are these (CT 5: CLRH, DUNC, LNTH, THOM, UEUT; DV 3: GUIC, UEUT, VICT). What such a mark does in `default`: keeps that species' records (DV records feed BT lifts through `observation_species` BT;DV; CT records feed nothing) and promotes the ct_dv_rb group, so RB, where it is not marked, breaks the streams at its barriers (`.lnk_pipeline_prep_minimal()`). Line 10 lists the modelled species correctly, so the page contradicts itself; a reviewer reading :12 would weigh a CT/DV row as "modelled where nothing shows it lives there". Same mechanism as round 3's finding 1: "marked" stands in for "modelled".
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** data-raw/logs/presence_check_402/README.md:3 — "`stamp.txt` … its date and tracker line differ on every run." The tracker line was identical in the last two runs (`5aabe8fe` and `c6a12c5c`: "0 added, 351 pending refreshed, 0 no longer flagged"); it differs only between a seeding run and a refresh, while the `link:` line, which does differ on every run, is not named. Minor; stated as a quantifier ("every run") the history disproves.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (compression: a quantifier with no measurement behind it)

No defect found in `.lnk_presence_story()` or `.lnk_presence_check()`: every sentence holds for every row its condition admits (table (a)).

## (a) Every sentence `.lnk_presence_story()` can emit

Rerun over all 351 rows of the committed `disagreements.csv` (rule columns added at 1 / 1950 / 1990): 351 of 351 identical to the committed `story`; tracker 351 rows, 351 joined, story and flag identical on all 351, every decision `pending`, one `rule` string equal to `.lnk_presence_rule(1, 1950)`, issue `#402`. Tests at HEAD: test-lnk_presence_check.R 86 pass, test-dictionaries.R 118 pass, test-pretest.R 98 pass / 1 skip, 0 fail.

| id | sentence | emitted when | rows | pipeline fact asserted, its code path | holds for every admitted row? |
|---|---|---|---|---|---|
| S1 | "Marked present with no record of X in the group." | present_unsupported, n_records 0, n_kept_pooled 0 | 12 | none (record count) | Yes, at any n_min (own X records 0; pooled records not counted are another species) |
| S2 | "Marked present; N records of X, none counting: <releases, excluded, undated, before Y (newest Z)>." | present_unsupported, n_records > 0, n_kept 0 | 12 | none | Yes: own = excluded + release + undated + pre-floor + kept, kept 0, so the list is exhaustive; Z is `year_newest_before` (newest pre-floor wild own record) since round 3 |
| S3 | "Marked present; K counting record(s), fewer than the N the rule asks for (also …, not counted)." | present_unsupported, n_kept > 0 (only at n_min > 1) | 0 | none | Yes; "(newest Z)" now pre-floor (test "the pre-floor clause…" pins 1940 at n_min 3) |
| S4 | "Not marked present; a single record (YEAR; SOURCE)" | absent_recorded, n_kept 1 | 82 | none | Yes (year and source over kept incl. pooled; " (1)" stripped) |
| S5 | "Not marked present; N records since Y0, A to B, M since Y1 (sources)" | absent_recorded, n_kept > 1 | 245 | none | Yes; Y0/Y1 from the row; at year_recent < year_min "M since Y1" still true (kept ⊂) |
| P1 | ", a D record pooled into X" | n_kept 1, n_kept_pooled 1 | 2 | none | Yes |
| P2 | ", all of them D records pooled into X" | n_kept_pooled > 0, n_kept_own 0 | 6 | none | Yes (the 8 BT absent rows are P1 + P2; n_records 0 on all) |
| P3 | ", k of them D records pooled into X" | n_kept_pooled > 0, n_kept_own > 0 | 0 | none | Yes (unreached) |
| S6 | "While it reads absent, its own X records are dropped before the observation breaks and from the barrier lifts of L." | absent_recorded, n_kept_own > 0, lift_readers not NA | 317 | breaks: `.lnk_pipeline_prep_observations()` keeps `species_code IN (.lnk_pipeline_break_obs_species(aoi))` (raw cell, exact code; CT aliases only when CT marked); lifts: `lnk_barrier_overrides()` reads `observations_province` (prepare.R:612-614), built by `.lnk_pipeline_prep_obs_province()` from each group's raw cell; L = `parameters_fresh` rows whose `observation_species` lists X, all with `observation_threshold` > 0 so `lnk_barrier_overrides()` processes them | Yes, independent of n_min / year_recent. Omitted (not false) for FINL and LOMI CT (no reader) |
| S7a | "The G group makes it present only where streams break: its barriers cut the network, but it is not classified and gets no access or mapping code." | absent_recorded, promoted_by not NA, modelled TRUE | 112 (CH 12, CM 17, CO 17, PK 32, SK 34) | `.lnk_pipeline_prep_minimal()` builds `barriers_<sp>_min` for `cfg$species` ∩ `lnk_presence()$present` (prepare.R:652-671), unioned into `gradient_barriers_minimal`; classify/connect default to `lnk_pipeline_species()` (classify.R:98, connect.R:87); access iterates `barriers_per_sp` over `active_species` (pipeline_run.R:225, 305-307; access.R:168-235, 468); mapping code `species = active_species` (run.R:356); recompute the same (wsg_recompute_one.R:55, 176-194). Measured: ADMS PK 39,425 segments, 0 `access_pk`, 0 non-empty `mapping_code_pk` | Yes for `default` (every promotable modelled species — CH, CM, CO, PK, SK, RB — has `access_gradient_max` > 0, so prep_minimal does build its set). Not reachable with RB in the committed rows |
| S7b | "The G group makes it present, which changes nothing: the bundle does not model X." | absent_recorded, promoted_by not NA, modelled FALSE | 2 (FINL CT, LOMI CT) | prep_minimal skips species outside `cfg$species`; access, classify, mapping code use the raw-present ∩ `cfg$species` set; no other `lnk_presence()` consumer acts on an unmodelled species (callers: run.R:257, prepare.R:655, wsg_recompute_one.R:60, habitat_variants_build.R:799, all passing species = active) | Yes |
| — | (no promotion sentence) | promoted_by not NA, modelled NA (species_modelled NULL) | 0 | — | Omission only |
| S8 | "Also N releases, M excluded, not counted." | absent_recorded with releases or exclusions | 60 | none | Yes |
| S9 | "Group note: \"…\"." | group_notes not NA | 57 | none | Yes |

## (b) Numbers and quantified or causal claims

### research/species_presence.md

| line | claim | source | verdict |
|---|---|---|---|
| 3 | bcfishobs 375,962 rows, newest valid 2026-10-10, link `83e45a71`, 351 flagged, all pending | stamp.txt; tracker; no R/ or data-raw/*.R change 83e45a71..HEAD | ✓ |
| 7 | 246 groups × 13 species, one notes cell | CSV header; cells.csv 3,198 | ✓ |
| 7 | "A cell marked `t` makes the species part of the model in that group" | cfg$species lacks CT, DV; lnk_pipeline_species() | **✗ for CT, DV** (finding 3) |
| 9 | filter keeps a record only where its own group marks it; lnk_pipeline_species picks species to classify; an unmarked species' record reaches no break, code 2 or lift in any group | prepare.R:307-350, 378-410; access walk reads observations_province | ✓ |
| 10 | groups: salmon CH CM CO PK SK; CT DV RB | lnk_presence.R:67-69 | ✓ |
| 10 | only prep_minimal reads the promoted reading, only for modelled species; default's list | prepare.R:655; cfg$species | ✓ in effect (run.R:257 and recompute also pass the promoted object to access and mapping code, which query it only for raw-present species, where it equals the raw cell) |
| 10 | ADMS PK promoted, no access_pk / mapping_code_pk on 39,425 segments | SQL on fresh_default; disagreements.csv | ✓ |
| 12 | "a species modelled where nothing shows it lives there" | 8 of 24 present_unsupported are CT/DV | **✗ for those 8** (finding 3) |
| 20 | bcfishpass filter tests the raw code | load_observations.sql:116 | ✓ |
| 22 | 74,495 / 75,739 of 375,962; bcfishpass tags without dropping | SQL; load_observations.sql:121-134 | ✓ |
| 23 | source holds 1007 and 9999 | SQL: 1007 ×1, 2028 ×1, 2080 ×6, 9999 ×178 | ✓ ("holds", not "only") |
| 24 | DV→BT regions; pipeline does not apply species_pooling.csv; BT lifts count DV | species_pooling.csv; grep (only validator, log, check); parameters_fresh BT `BT;DV` | ✓ |
| 24 | "its story says so" (BT flag on DV alone) | stories P1/P2 name every record as pooled DV | ✓ in substance |
| 26 | check reports whether and through which members promotion acts | present_promoted, promoted_by | ✓ |
| 30-46 | 351 of 3,198; table, 65 cells | summary.csv | ✓ all |
| 48-50 | 12 no record; 6 UDEN; KTSU CH/ST note; 12 on releases (8) / undated (4); LPRO RB 90 releases; UEUT BT/CT/DV 2 undated each | disagreements.csv | ✓ (no mixed or pre-floor cells) |
| 53 | 82 / 89 / 156; 238 since 1990 | disagreements.csv | ✓ |
| 54 | KO 4 marked, 137 flags, median 11, 92 of 156, 52 with releases | disagreements/cells.csv | ✓ |
| 55 | 114 promoted: PK 32, SK 34, CM 17, CO 17, CH 12 break-only; 2 CT changes nothing | disagreements.csv; code as S7a/S7b | ✓ |
| 56 | ST 34, none promoted, 17 single | disagreements.csv | ✓ |
| 57 | Mackenzie 29 flags (26 absent), 7 salmon/ST, 1-2 records 1969-1998, listed cells; all carry "Mackenzie basin" | disagreements.csv | ✓ |
| 58 | BT's 8 (absent) flags rest on pooled DV alone | n_kept_own 0, n_records 0 | ✓ |
| 62-73 | 132,502 records, 157 codes, mostly other fish, eight codes and counts | stamp.txt; SQL top codes MW, EB, LSU… | ✓ |
| 75 | 4 flags: FINA ST, UFRT ST, MFRA BT → absent_recorded; VICT DV → supported | alias_sensitivity.csv | ✓ |
| 79 | add/remove moves `acc` (species columns in spec, notes not) | lnk_vocabulary.R:183-212 | ✓ |
| 81 | declared file enters config_hash | lnk_log.R:52-120 (declared files + provenance; tracker not listed) | ✓ |
| 81 | "recompute_readers refuse that run's groups and stop the export publishing it" | recompute_readers_check.R:141-143; lnk_scenario_export.R:281-292, 576-596, 1228-1239 | **✗** (finding 1) |
| 81 | no run reads the tracker | grep R/, data-raw: only the check driver | ✓ |
| 85 | default: 5 on or after 1990-01-01 for CH…KO; 1 for BT, RB, WCT | parameters_fresh.csv | ✓ |
| 85 | salmon and ST counts bcfishpass's; strict `>` vs link `>=` | model_access_ch_cm_co_pk_sk.sql:86,158; model_access_st.sql:86,157; lnk_barrier_overrides.R:209 | ✓ |
| 85 | "569 … count toward a lift in link" | SQL raw 569; 561 in observations_province | **✗** (finding 2) |
| 85 | WCT one record in both | model_access_wct.sql (any WCT record upstream) | ✓ |
| 85 | no GR/KO model; RB in CT/DV/RB with no threshold row; BT lift counts BT, salmon, ST | model/01_access/sql listing; ct_dv_rb.sql:59; bt.sql:78,160 | ✓ |
| 85 | "a single salmon above a falls makes the segment read code 2 and does not lift the falls" | access.R:468-490 | ✓ for segments below the falls (segments above it, the record's own included, read 0) |

### CLAUDE.md #402 entry

| claim | verdict |
|---|---|
| 351 rows (24 / 327); rule; first answer five records | ✓ |
| owed: acc token spec, new acc row and version bump; pre-run gate runs again (prepare.R changed) | ✓ |
| tracker undeclared: "refuse that run's groups and stop the export publishing it" | **✗** (finding 1) |
| pretest maps it `none`; dictionary tested by path | ✓ (pretest_inputs.csv row; test-dictionaries.R) |
| unmarked cell: no break, code 2 or lift in any group | ✓ |
| promotion reaches only prep_minimal; ADMS PK has neither; 114 of 327 | ✓ (effect; see research :10) |
| pooling resolved on an all-present copy | ✓ lnk_presence_check.R:110-115 |
| drops SST 404, WST 358, ADV 79, ABT 12, BT/DV 57, DV/BT 52, RB/CT 23; 4 flags | ✓ stamp.txt (the 1 " RB" record omitted, changes no flag) |
| lifts 5 since 1990 …, 1 for BT, RB, WCT; one salmon above a falls gives code 2 and no lift | ✓ (code 2 below the falls) |
| one exclusion helper for prep, validator, check | ✓ diff; other data-raw scripts keep their own copies, outside the claim's scope |

### RUNBOOK "The presence table is checked against the records"

| claim | verdict |
|---|---|
| a record survives only where its own group marks its species `t` | ✓ |
| promotion reaches only prep_minimal, modelled species break; classification, access, mapping code follow the cell | ✓ (effect) |
| unmarked cell discards records for breaks, code 2, every group's lifts | ✓ |
| rule summary; tracker pending; add/remove moves `acc` | ✓ |
| "a review edit after a run would then make recompute_readers and the export refuse that run" | **✗** (finding 1) |
| SST, WST, ADV, ABT, BT/DV, DV/BT, RB/CT never count | ✓ |

### data-raw/logs/presence_check_402/README.md, stamp.txt

| claim | verdict |
|---|---|
| produced at `83e45a71` | ✓ (83e45a71..HEAD touches only outputs, research line 3, README) |
| "its date and tracker line differ on every run" | **✗** (finding 4) |
| first run at `feaa408c` flagged the same 351 | ✓ be8f5319 stamp `@ feaa408c` |
| later rounds rewrote stories, added `year_newest_before`, `modelled`; flags, counts, groups/summary/alias did not move | ✓ be8f5319 vs HEAD: cells.csv 24 old columns identical (2 added); disagreements.csv 24 non-story columns identical, 327 stories changed; groups.csv, summary.csv, alias_sensitivity.csv byte-identical |
| file table, column descriptions | ✓ (`year_newest_any` not described: omission) |
| stamp: 246 / 3,198 / 351 (24, 327); 132,502 / 157; SQL cross-check 39 cells, 5,423 records | ✓ |

### dictionary_wsg_species_presence_review.csv

| claim | verdict |
|---|---|
| consumed_by 410-418 | ✓ lines of the `add` data.frame; test-dictionaries.R passes |
| flag: "fewer records meet the rule than it asks for" / "at least as many do" | ✓ (n_kept < n_min / ≥ n_min, any n_min) |
| story drafted from evidence, refreshed while pending, decided rows never changed | ✓ `.lnk_presence_review_merge()` |
| decision values | ✓ merge refuses others; test checks tracker |

## (c) Values restated in two places

| value | places | verdict |
|---|---|---|
| dictionary consumed_by refs | dictionary vs lnk_presence_check.R:410-418 | ✓ (test passes at HEAD) |
| rule n_min / year_min / year_recent | check defaults, row columns, driver (`res$n_min[1]`), `.lnk_presence_rule()`, tracker `rule`, research, CLAUDE.md, RUNBOOK | ✓ one source |
| exclusion keys | prep, validator, check | ✓ one helper |
| release tagging | R vs driver SQL vs bcfishpass load_observations.sql:121-134 | ✓ |
| CT alias set | check vs `.lnk_pipeline_break_obs_species()` vs driver SQL vs bcfishpass remap | ✓ CCT, ACT, CT/RB |
| alias map | driver `alias` (8 codes incl. " RB") vs README table vs research table vs stamp | ✓ |
| promotion groups | `eval(formals(lnk_presence)$groups)` in check vs vocabulary vs pipeline default | ✓ |
| modelled species | `cfg$species` (driver) vs research :10 list | ✓ |
| what promotion builds | story S7a/S7b, research :10/:55, CLAUDE.md, RUNBOOK vs prep_minimal / lnk_pipeline_species | ✓ |
| what a marked cell builds | research :7/:12 vs cfg$species | **✗** (finding 3) |
| consequence of declaring the tracker | CLAUDE.md, research :81, RUNBOOK, test-dictionaries.R comment vs readers check and export code | **✗** (finding 1) |
| lift date-test record count | research :85 vs observations_province | **✗** (finding 2) |
| unchanged columns after round 3 | README vs be8f5319 outputs | ✓ (24 + 24 columns identical) |
| log file list | README table vs directory | ✓ |
