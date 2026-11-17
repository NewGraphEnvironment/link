# Code-check round 4, #470 (enumeration round; branch at 75f575e7 against 2da2db35)

## Checklist read

- **code-check.md**: the prose of the H3s under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; and, by index line and from earlier rounds, the other nine). Also "Documentation Staleness" (Rules that stand alone). Not read in full: the other stand-alone, Security and PDF H3s.
- **code-check-r.md**: by index; read in full for none this round (the R rules this branch touches were read in rounds 1 to 3: `information_schema` lookup by literal name; Postgres row order; `match()` and NA; `$` partial matching).
- **code-check-shell.md**: by index (psql `:'var'`, `\quit`; `grep -c`); none read in full.
- **code-check-spatial.md**: by index; none read in full (FWA calls unchanged).

How checked: a detached worktree of HEAD (`git worktree add --detach`), scratch schema
`zz_review_lifts` (dropped at the end), local fwapg.

## Findings

- **[severity: fragile]** `data-raw/logs/record_rule_470/lifts_426_427.R:73-79` (and the #427 table in its README, NEWS.md's #427 bullet) — round 3's fix gave the harness prepare's control table but not prepare's other lift input: `.lnk_pipeline_prep_overrides()` (`R/lnk_pipeline_prepare.R:556-596`) passes `habitat = <schema>.user_habitat_classification` whenever the bundle declares it, and `default` does (`config.yaml:36`). Habitat lifts are unioned into the same `barrier_overrides` at every threshold, so a barrier a habitat row already lifts at 5 is not "added" at 2 in a build. Measured with the harness's own inputs (fresh_default 0.78.2 barriers, HEAD's record rule, control), once without and once with the habitat table: without it reproduces `lifts_427.csv` exactly (SQAM 22, LSKE 7, HARR 8, SQAM ST 42, MORR ST 8); with it the lifts threshold 2 adds are **SQAM 4** (not 22) per salmon species, **SQAM ST 24** (not 42), **LSKE 6** (not 7), HARR 8, MORR ST 8. NEWS says "On SQAM, LSKE and HARR that adds 22, 7 and 8 lifts per salmon species", and the README's table under "The operator chose 2" carries the same counts; the README's "(observation lifts only)" names the scope but the numbers are presented as what the threshold adds. The threshold-1 column has the same overcount. (#426's comparison is unaffected: habitat lifts are the same in both arms and can only mask, not create, a difference.) This is the same derivation one axis over from round 3's finding 1: the harness re-derives "what prepare passes to `lnk_barrier_overrides()`" argument by argument.
  - **Rule:** code-check.md "One fact derived twice" ; code-check.md "A proxy is not the property"

- **[severity: bug]** `inst/extdata/configs/dictionary_wsg_species_presence_review.csv:2-10` — round 2's fix (d62c9340) added 6 net lines above line 434 of `R/lnk_presence_check.R` and left the dictionary's `consumed_by` refs (`R/lnk_presence_check.R:434`..`:442`) pointing at the old positions. `tests/testthat/test-dictionaries.R:270` ("species_pooling / species_groups consumed_by refs land on their column") now fails 9 times at HEAD under `devtools::test()` (`NOT_CRAN=true`; it skips under `R CMD check`, where `R/` is absent): line 434 reads `tracker$flag[ri] <- flagged$flag[pend]`, and the `add <- data.frame(` block the refs name now sits at 440 (`watershed_group_code = flagged$...`) to 448 (`issue = ...`). Round 3's run of targeted tests did not include this file. Shift the nine refs by +6 (434→440 … 442→448) and re-run the file.
  - **Rule:** code-check.md "Documentation Staleness"

## Round 3's fixes

| fix | checked | verdict |
|---|---|---|
| harness passes control | run (measurement above) | control correct; **habitat missing** (finding 1) |
| negative script judges as the check | read: `JUDGED` is the SQL's `g` (newest finished build per group, >= 0.84.0); the scratch `log` holds only the run's rows (`study_area_verify_negative.sh:99`), and 6f/6g restore their log edits before 6j | agrees |
| `.lnk_record_aliases_everywhere()` reads the `wsgs` attribute | run: on `default`, 7 aliases fold (ABT, ACT, CCT, CT/RB, ADV, SST, WST; 246 of 246 groups), BT/DV and DV/BT (158 groups) do not; all three callers pass the `.lnk_record_aliases()` result unsubset (read); new test passes | agrees |
| `R/lnk_species_pooling.R` mapped to the rule's inputs | read + `test-pretest.R` 162 pass, 2 skip | agrees |
| `cfg` required | read + test passes; no caller passes `cfg = NULL` (an explicit NULL would still resolve `any`); the old measurement scripts that omit it now stop loudly | agrees |
| (round 2) presence check matches pooled rows on the recorded code | run (set equality below) | agrees; but shifted the dictionary refs (finding 2) |

## Enumeration

| # | place | what it derives | how checked | verdict |
|---|---|---|---|---|
| 1 | `R/lnk_observation_records.R:40` `.lnk_observation_species_map()` | the rule: present targets, pooled + alias rows, target's floor, year limit; refuses a lift list mixing floors | run on `default`, `default_tuned`, `bcfishpass` | reference |
| 2 | `R/lnk_observation_records.R:149` `.lnk_observation_table_build()` | join on the record's own group and code; `date >= floor`, `extract(year) <= year_max`, undated fails both | read | agrees |
| 3 | `R/lnk_pipeline_prepare.R:313` `.lnk_pipeline_prep_observations()` | the date rule from `cfg` (now required); AOI table = map rows of the AOI | read + test | agrees |
| 4 | `R/lnk_pipeline_prepare.R:376` `.lnk_pipeline_prep_obs_province()` | the same map, every group | read | agrees |
| 5 | `R/lnk_barrier_overrides.R` observation lift | list on model species; own floor (`1900-01-01` when none, so undated never lifts: accepted); control per `observation_control_apply`; habitat lifts unioned | read; `default`'s lists all share their floor (run: CH..SK, ST 1990-01-01; GR, KO own; BT, RB, WCT none), `bcfishpass` under `any` | agrees |
| 6 | evidence: `lnk_pipeline_persist.R`, `lnk_persist_init.R`, `schema_consolidate.R` core, `study_area_hosts.sh` core | evidence rows from the lift's own temp table; same core set both sides | read + `test-lnk_pipeline_persist.R`, `test-lnk_persist_init.R` pass | agrees |
| 7 | `R/lnk_observation_records.R:214` `.lnk_record_aliases()` | alias rows, all-present, year limit, `wsgs` attribute | run | agrees (all-present deliberate) |
| 8 | `R/lnk_observation_records.R:257` `.lnk_record_aliases_everywhere()` | aliases listed in every resolved group | run | agrees |
| 9 | `R/lnk_presence_check.R` | aliases via #7; pooled rows on the recorded code; year limits | run: `default` all-present map (non-self, 2,196 rows) `setequal` the check's pooled + alias set; tests pass (91) | agrees |
| 10 | `R/lnk_presence_measures.R` | aliases via #7 (`pm_alias`, year limit), zones via #8, lift pools from `observation_species` | read | agrees |
| 11 | `data-raw/wsg_species_presence_check.R` SQL recounts | `pc_alias` = #7, `pc_alias_zone` = #8; same `regions` path as the check | read | agrees (counts are independent, alias resolution is not, by design) |
| 12 | `data-raw/wsg_species_presence_map.R` | #7 into the measures | read | agrees |
| 13 | `data-raw/habitat_validate_inputs.R` `hv_pooling()` → `lnk_habitat_validate()` | `lnk_species_pooling()` present-only, one tracker for every scored bundle | run: present-only pooling over all species = pipeline map without dates (2,622 rows, `setequal`), and the BT/CH subset equal | differs deliberately: no floor (accepted); a `bcfishpass` bundle scored beside `default` gets `default`'s aliases (pre-existing one-tracker design) |
| 14 | `R/lnk_vocabulary.R` acc spec / `.lnk_record_rule_digest()` cut digest | acc: #1 as written; cut: #1 all-present | `test-lnk_vocabulary.R` 82 pass (specs match `vocabulary.csv`) | agrees |
| 15 | `data-raw/pretest_inputs.csv` | which inputs the rule's files drive | read + `test-pretest.R` | agrees |
| 16 | `data-raw/study_area_verify.sql` evidence block | judged groups = newest finished build of the run at >= 0.84.0; threshold check over all run groups | read | agrees (the threshold check's wider set holds no evidence for pre-0.84 groups) |
| 17 | `data-raw/study_area_verify_negative.sh` 6j–6l | judged groups, mutated row | read | agrees |
| 18 | `data-raw/logs/record_rule_470/verify_evidence.sh` | every row raised to 0.84.0 | read | agrees |
| 19 | `data-raw/logs/record_rule_470/pre_post_diff.R` | old rule folds CT aliases | read | accepted caveat |
| 20 | `data-raw/logs/record_rule_470/lifts_426_427.R` | lift inputs as prepare passes them | run | **finding 1** (habitat) |
| 21 | `R/lnk_pipeline_access.R` code-2 walk (via `lnk_pipeline_run.R:367`) | model species from `observations_province`; `group_gated` gate from `<schema>.observations` | read | agrees |
| 22 | `R/lnk_pipeline_break.R` `.lnk_pipeline_break_obs()` | tops per model species from `<schema>.observations` (the removed `.lnk_pipeline_break_obs_species()` alias list has no caller left) | read + grep | agrees |
| 23 | `R/lnk_species_pooling.R` province scope, alias regex | rule rows | `test-lnk_species_pooling.R` 60 pass | agrees |
| 24 | `data-raw/query_habitat_thresholds_obs.R`, `query_habitat_thresholds_mad.R` (unchanged) | `lnk_species_pooling()` now returns alias rows too | read: their one-target and model-species guards stop loudly on a conflict; aliases now count as their species there, as the rule says | agrees |
| 25 | old measurement scripts calling `.lnk_pipeline_prep_observations()` without `cfg` (`data-raw/logs/{obs_province_401,observation_breaks_396,record_at_start_399}/`) | — | grep | stop loudly now (records of past runs); `overrides_scope_time_349.R` was updated |
| 26 | `inst/extdata/configs/dictionary_wsg_species_presence_review.csv` `consumed_by` | file:line refs into `R/lnk_presence_check.R` | run `test-dictionaries.R` | **finding 2** |
| 27 | `R/lnk_habitat_validate.R` exported default list | — | — | accepted |

Tests run (worktree, `NOT_CRAN=true`): observation_records 45, presence_check 91,
vocabulary 82, species_pooling 60, barrier_overrides 31, pipeline_persist 42, persist_init 62,
pretest 162 (2 skips): 0 failures. pipeline_prepare: 2 failures, both #493 (accepted).
dictionaries: 9 failures (finding 2).
