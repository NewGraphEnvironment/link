# Code-check round 3, #470 (branch against 2da2db35)

## Checklist read

- **code-check.md**: the prose of all 14 H3s under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree, and what generators leave in it; A wrapper's exit is not the work; Zero-length, empty, and unset are three different things; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice). Not read: the 31 other H3s (Rules that stand alone, Security, Spreadsheets and PDFs).
- **code-check-r.md**: An `information_schema` lookup by the literal table name misses what Postgres resolves; Postgres row order is never fixed unless the query fixes it…; `match()` treats NA as a matchable VALUE…; Cross-function consistency for label/string normalization; `ifelse()` with an all-NA test returns a logical vector…; A database driver's value is not a base R type…; `$` on a list partial-matches…. Not read: 115.
- **code-check-shell.md**: read by index line only for psql `:'var'` / `\quit`, heredoc inside `$( )` on bash 3.2, a second `trap … EXIT`; no full section read. Not read in full: 110.
- **code-check-spatial.md**: none read in full (the diff's FWA use is `fwa_upstream()` calls carried over unchanged). Not read: 143.

## Mechanism

**The record rule has no single resolved artifact; each consumer re-derives it.**
`lnk_species_pooling()` returns per-target rows, and each place that needs "which recorded code
counts as which species, in which group, from which date, within which year, without chaining"
rebuilds that answer from it (or from scratch) with its own filters: present-only or all-present,
alias rows split from pooled rows or not, which date floor, which set of groups is "everywhere",
which lift arguments. They agree only where the separate derivations happen to coincide on today's
tracker and today's call sites. The three earlier findings are the same shape: round 1 derived a
table's columns from a stand-in (the literal name in `information_schema`) instead of the table;
round 2 derived "which runs are judged" in the negative script differently from the check; round 3
re-derived pooling in the presence check from folded codes, so it chained where the pipeline does
not.

Checked empirically at HEAD (`default`): the pipeline's map resolved with every species present
equals the presence check's pooled-plus-alias set row for row (2,196 non-self rows, `setequal` TRUE),
ADV maps only to DV, BT/DV and DV/BT only in the 158 pooled groups, and the targeted test files
(`test-lnk_observation_records.R`, `-presence_check`, `-species_pooling`, `-vocabulary`,
`-barrier_overrides`) pass with no skips.

| # | place | what it derives | verdict |
|---|---|---|---|
| 1 | `R/lnk_observation_records.R:40` `.lnk_observation_species_map()` | the rule: present targets, pooled + alias rows, target's floor, year limit | reference |
| 2 | `R/lnk_observation_records.R:149` `.lnk_observation_table_build()` | joins on the record's own group; `date >= floor`, `extract(year) <= year_max`, undated fails both | agrees |
| 3 | `R/lnk_pipeline_prepare.R:313` `.lnk_pipeline_prep_observations(cfg = list())` | date rule from `cfg` | **finding 5** (default silently = `any`) |
| 4 | `R/lnk_pipeline_prepare.R:369` `.lnk_pipeline_prep_obs_province()` | same map, every group | agrees |
| 5 | `R/lnk_barrier_overrides.R` lift | `observation_species` list on model species; own floor (undated never lifts); control; floor-mix refused in #1 | agrees |
| 6 | evidence table, `lnk_pipeline_persist.R`, `lnk_persist_init.R`, consolidate/hosts core lists | evidence and lifts read one temp table, so the (barrier, species) sets match | agrees |
| 7 | `R/lnk_observation_records.R:213` `.lnk_record_aliases()` | alias rows, all-present, year limit; refuses a two-target alias the pipeline would accept (loud) | agrees (deliberate all-present) |
| 8 | `R/lnk_observation_records.R:249` `.lnk_record_aliases_everywhere()` | "listed in every group" | **finding 3** (latent) |
| 9 | `R/lnk_presence_check.R` | aliases via #7, pooled rows matched on the recorded code, same year-limit semantics, own `year_min` instead of floors (deliberate) | agrees |
| 10 | `R/lnk_presence_measures.R` `pm_alias` join, `pm_pools` | aliases via #7 with year limit; zones via #8; lift pools from `observation_species` (pooled DV→BT not folded, but BT is not a measured species) | agrees (zones inherit #8) |
| 11 | `data-raw/wsg_species_presence_check.R` SQL recounts | `pc_alias` = #7, `pc_alias_zone` = #8 | agrees (inherits #8) |
| 12 | `data-raw/wsg_species_presence_map.R` | #7 | agrees |
| 13 | `lnk_habitat_validate()` via `data-raw/habitat_validate_inputs.R` | `lnk_species_pooling()` present-only, record's group, year limit, no chaining, no floor (accepted) | agrees |
| 14 | `R/lnk_vocabulary.R` acc spec / cut digest | acc: exactly #1; cut: #1 all-present; specs match `vocabulary.csv` (tests pass) | agrees |
| 15 | `data-raw/pretest_inputs.csv` | which inputs the rule's code drives | **finding 4** |
| 16 | `data-raw/study_area_verify.sql` evidence block | judged groups = newest finished build of the run at >= 0.84.0 | agrees |
| 17 | `data-raw/study_area_verify_negative.sh` 6j–6l | judged groups = any log row >= 0.84.0; mutated row from any copied group | **finding 2** |
| 18 | `data-raw/logs/record_rule_470/verify_evidence.sh` | raises every row to 0.84.0, so every group judged | agrees |
| 19 | `data-raw/logs/record_rule_470/pre_post_diff.R` old rule | folds CCT/ACT/CT/RB into CT, which the old pipeline did not (it kept the recorded code, so CCT had its own top); acknowledged in the README's HOMA trace and it fails toward "unexplained", not toward a silent pass | agrees with stated caveat |
| 20 | `data-raw/logs/record_rule_470/lifts_426_427.R` | lift rule without `control` | **finding 1** |

## Findings

- **[severity: fragile]** `data-raw/logs/record_rule_470/lifts_426_427.R:60-65` — the lift harness calls `lnk_barrier_overrides()` with no `control`, while the pipeline passes `<schema>.barriers_definite_control` (`R/lnk_pipeline_prepare.R:571-585`) and every salmon/ST row has `observation_control_apply = TRUE`. So #427's "added" lifts include barriers the pipeline never lifts. Measured: HARR's falls `356354346` @ 8876 m (`user_barriers_definite_control.csv`, `barrier_ind = t`) is lifted at threshold 2 for CH, CM, CO, PK, SK and ST by the harness (two 1995 CO records above it) and not with control; `lifts_427.csv`'s HARR `lifts = 11, added = 9` is 10 / 8 in the pipeline, and the README's "+9 (≤ 282 km)" counts the km above that falls. The operator's threshold-2 decision rests on this table. (#426's comparison is unaffected: both arms lack control equally.)
  - **Rule:** code-check.md "One fact derived twice" ; code-check.md "A proxy is not the property"

- **[severity: fragile]** `data-raw/study_area_verify_negative.sh:573,590-593` — the cases judge "which groups the check judges" differently from the check. `study_area_verify.sql` judges only groups whose newest finished build of the run is at >= 0.84.0; the script proceeds when **any** scratch log row is >= 0.84.0 and then picks `EV_ROW` from `barrier_overrides` of **every** copied group (`ORDER BY 1 LIMIT 1`, alphabetical). On a run spanning the version boundary (a group re-modelled under the run's uid after an upgrade, the #348 path), the picked row can belong to an unjudged group: deleting its evidence (6k) or its lift (6l) moves nothing the check reads, the verify passes, and the script reports a false failure of a working check. Restrict the pick to groups whose newest finished build is >= 0.84.0, as the SQL's `g` does.
  - **Rule:** code-check.md "One fact derived twice" ; code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** `R/lnk_observation_records.R:254-258` — `.lnk_record_aliases_everywhere()` defines "every group" as `unique(aliases$watershed_group_code)`, the groups that list *any* alias, not the groups resolved. It is right today only because the province rows make every group list some alias (246 of 246). If the tracker held only regional alias rows, `BT/DV` and `DV/BT` (listed in all 158 pooled groups, which would then be all of `n_all`) would pass as "one species everywhere" and fold into BT in the historical zones province-wide (measures' `in_hist_zone`, the driver's `n_hist_zone`), including the lower Skeena and the coast where the tracker does not pool them. Pass the resolved group set and compare against it.
  - **Rule:** code-check.md "A proxy is not the property"

- **[severity: fragile]** `data-raw/pretest_inputs.csv:20` — `R/lnk_species_pooling.R` stays mapped `any` ("runs once per group whatever the group holds"), but it is now half of the record rule: the pipeline's map, the vocabulary specs and the lifts' records all resolve through it (scope ranks, the alias regex, province rows). The other half (`R/lnk_observation_records.R`) and the tracker CSV and `wsg_regions.csv` were mapped to `segments`, `gradient`, `observations` and `obs_upstream` in this branch. A later change confined to the resolver is pretested on the `any` group only, not on the groups at the extreme of the inputs it moves.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "One fact derived twice"

- **[severity: fragile]** `R/lnk_pipeline_prepare.R:313-315` — `.lnk_pipeline_prep_observations(..., cfg = list())`: an omitted `cfg` silently resolves the date rule to `any`, so a `lift_floor` bundle's tables are built under another rule with no error. The one production caller passes `cfg`; the callers that omit it today are measurement scripts (`data-raw/overrides_scope_time_349.R`, several `data-raw/logs/*/build_obs.R`), which would now build `default`'s tables with pre-1990 salmon records. Make `cfg` required.
  - **Rule:** code-check.md "A guard that fails toward pass"
