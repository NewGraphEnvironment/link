# Task: Backlog move 11: What blocks access at a barrier (#479)

**If we do it:** barrier rules are config and compared as scenarios, dams can be species-dependent, and copies of one barrier agree. **If we never do:** what blocks is fixed in code and scenarios cannot be compared.

Move 11 of `planning/backlog.md`, batch 16: #201, #83, #341, #386, #236. Planned 2026-11-24 from `origin/main` at `c7abea13` (link 0.92.0, fresh pinned v0.56.0). No plan gate ran in the planning pane: the plan is parked for the coordinator's plan gate, and the forks that are the owner's are under "Open decisions". A Plan review ran before the baseline (`planning/active/review-plan.md`); each phase says what it changed.

## What the plan found (read before the phases)

- **The batch is more than one PR.** It holds four mechanisms: copies of a barrier (#386), lift rules (#236), which crossings are human-made barriers (#341), and which barriers block which species with what a row carries (#201, #83). The last one changes the shape of the persisted `barriers` table and the access views; the first three do not. This plan carries the first three and the rule-table pattern, and drafts #201 + #83 as their own issue (last section), as the backlog's header rule says. Open decision 1 gives the owner the alternatives and what each costs.
- **Only #386 moves `default` or `bcfishpass` output here.** #236 and #341 land as mechanism with rows that reproduce today.
- **Under `observation_record_date: lift_floor` (which `default` sets, and `bcfishpass` does not), one lift rule cannot mix date floors** (`R/lnk_observation_records.R`, the refusal near line 93, which applies only under `lift_floor` and only to a rule with a threshold above 0). "BT on one BT record of any date" beside "BT on two salmon records since 1990" is exactly that mix, so #236 is what makes a salmon-evidence BT lift expressible in `default` at all.
- **`parameters_fresh.observation_date_min` is two things:** the lift's floor and each species' record floor for cuts and code 2. That is why rule 1 stays where it is (decision D2).
- **Controls are filed by group, and 7 of 238 rows are filed under a group that does not own their position** (planning probe on this host, below). Every reader of the control table matches by position and none assumes it holds only the group's rows (review, confirmed in `R/lnk_pipeline_prepare.R`). Whether bcfishpass applies its control table by position is believed and not yet read: Phase 1 reads `model/01_access/sql/barriers_gradient.sql` at `smnorris/bcfishpass@3bd2824` before the docs say so.
- **`crossings` has no `stream_crossing_id`.** A PSCIS crossing's id is `aggregated_crossings_id` (text) with `crossing_source = 'PSCIS'` (`R/lnk_crossings_union.R`). `whse_fish.pscis_assessment_svw` holds one row per crossing on this host (19,905 of 19,905).
- **`lnk_pipeline_run()` drops `<working>.observations_province` when it returns**, whatever `cleanup_working` is, and every build of a group shares `working_<wsg>` unless `schema =` is passed. The proofs below are written around both.

Planning probes, 2026-11-24, on this host's `fresh_default` (241 groups built at 0.78.2) and local FWA:

| measure | value |
|---|---|
| gradient barrier positions | 7,241,875 |
| positions held by more than one group | 1,224 (up to 13 holders) |
| rows at those positions | 3,087, of which 1,864 held by a group that does not own the segment |
| control rows (`default`) | 238: 67 `barrier_ind` true, 171 false |
| control rows filed under a group that does not own the position | 7 |
| control rows within 1 m of a multi-held gradient position | 1 |

`whse_fish.pscis_assessment_svw` is loaded on every host by `data-raw/snapshot_bcfp.sh` and carries `outlet_drop`, `outlet_pool_depth`, `culvert_slope`, `length_or_width`, `stream_width_ratio`, `downstream_channel_width`, `final_score`, `current_barrier_result_code`.

## Decided at the gate

Nobody approved a plan in the planning pane. These are mechanism decisions the planning session made (2026-11-24), each with its reason; the coordinator's plan gate or the owner may overturn any of them.

- **D1. Two bundle tables, not one.** `parameters_barrier_rules.csv` says which crossings are human-made barriers; `parameters_barrier_lifts.csv` holds further observation-lift rules. Condition rows and evidence-parameter rows share no columns, and one sparse table would need a dictionary per row type.
- **D2. Lift rule 1 stays in `parameters_fresh.csv`; the lifts table holds further rules only.** `observation_date_min` there is also the species' record floor, read by `.lnk_observation_species_map()`, the vocabulary, the presence check and the log. One reader, `.lnk_lift_rules(cfg, loaded)`, returns every rule; each rule lives in exactly one file.
- **D3. Rule rows combine as: same `rule_id` is AND, different `rule_id` is OR; a NULL value matches only the `is_null` operator; row order means nothing.** `applies_to` scopes a rule to a crossing source, which is how a scenario replaces the province's result for assessed crossings and keeps the modelled type for the rest. `species` accepts only `*` and `outcome` only `barrier` in this PR, and anything else is refused at load: the columns exist so the #201 + #83 piece adds rows, not a redesign. The lifts table carries `barrier_kinds` for the same reason, accepting only `natural`.
- **D4. Rules are evaluated once**, into `<schema>.crossings.barrier_rule_id`: every matching `rule_id`, sorted in `C` order and joined with `;`, NULL when none (review: "first in file order" contradicted D3, and the vocabulary sorts rows before hashing). An internal helper called from `lnk_pipeline_crossings()` writes it for every bundle, with the built-in rule's id (`status`) where the bundle declares no table. The four status sites read one SQL helper. Only a caller's own `crossings` table handed to `lnk_barriers_emit()` can lack the column, and that alone falls back to the built-in predicate. No new export, so no naming fork.
- **D5. A bundle that declares neither table behaves as today** (built-in status rule, rule `own` only). `default` and `bcfishpass` declare the rules table with the one reproducing row; the bundles that extend `default` inherit it (`files:` merges by key).
- **D6. The scenario compare needs no pipeline run**: a crossing rule moves no segment and no access, and `lnk_aggregate()` needs only a crossings table, a barriers table and a persist schema's streams and habitat. It runs from two rule files on one build. Whether a thin scenario bundle can also be modelled without a new token is open decision 6.
- **D7. fresh stays at v0.56.0.** 0.57.0 is its own move (owner, 2026-11-23). The stale-package check lists fresh 0.56.0 against 0.57.0 for that reason, and no upgrade is part of this plan.
- **D8. The recompute scheduler stays on the line rule in this PR.** The owner rule is complete by construction only for a schema whose every group was built at 0.93.0 or later; a schema part-way there still holds non-owner copies. The switch is owed after the next provincial run.
- **D9. One set of scratch builds proves every phase:** BEFORE (a worktree at `c7abea13`), AFTER-386 (the commit that ends Phase 1) and FINAL (the branch head), both bundles, the same groups, each in its own persist schema and its own working schemas (a proof driver passes `schema =` to `lnk_pipeline_run()`, so no build reads another's `working_<wsg>` and another session's run cannot replace them). Each build gets the recompute pass over every proof group before anything is compared: without it a group's access depends on whether its owner had landed.
- **D10. Habitat lifts read rule `own`'s species list only**, as today (`R/lnk_barrier_overrides.R`, the habitat join). A further rule adds observation evidence, not habitat evidence.
- **D11. The per-rule floor test is equality, as today's refusal is.** A further rule stricter than its species' record floor would be sound, and only a looser one silently loses records; allowing the stricter case is a later relaxation, not this PR's.

Owner's answers, 2026-11-24, at the plan gate (recorded in #479's `## Decisions`; the resume session asked 1, 2, 4 and 5 again, not having seen the body, and got the same answers):

- **O1. Scope (a):** this PR carries #386, #236 and #341. #201 and #83 become one new issue from the draft in the last section, filed after the owner reads its body. That piece rebuilds every group's `barriers` once more before province-wide use.
- **O2. #386's rule (a), both:** controls apply by position whatever group a row is filed under, and a group persists a gradient barrier, override or evidence row only at a position on its own segments.
- **O3. A second BT lift rule in `default` (a), not in this PR.** The owner added: "we should have follow up planned. we dont just put it down and forget". So the build files a follow-up issue that adopts or rejects the rule from the measured lifts per group in `research/barrier_rules.md`, and names it in the PR body.
- **O4. Remove `lnk_thresholds()`, `thresholds_default.csv`, `lnk_score()` and `lnk_source()`** in this release, breaking in NEWS; their numbers become the scenario rule file's rows.
- **O5. `barrier_override_evidence` gains `lift_rule` in its primary key**, with the migration Phase 2 names.
- **O6. The `acc` spec names the lift rules and only those barrier rules that can move access** (`blocks`, none until the split piece).
- **O7. Cut tokens (b):** new cut rows as well as the `acc` rows, as #478 did (`cut-full-top-5`, `cut-full-ssf-all-4`, a successor to `cut-min`). A token that changes with the same output costs only bookkeeping, but a cut that changes under an unchanged token passes silently.
- **O8. A position whose owner does not hold it (a):** one named holder, the lowest group code among the groups that scan the line, counted in the verify report.

Mechanism decisions made during the build (2026-11-24, reported in the PR):

- **D12. A line dependency holding no barrier rows is refused** by `lnk_wsg_downstream_check()` (code-check round 2): from 0.93.0 only the owner holds a position, so a one-group or closure run into a schema without it would read those barriers as open. Warn at model time under the driver; the recompute's post-condition refuses, and takes the written-reason override (round 3).
- **D13. On a database whose FWA lacks a modelled group, the check names that group** (round 3): the line rule reads FWA and cannot see its lines.

Left open on #341 and not needed to build this: which measured rules `default` adopts and from what source, whether an unassessed crossing stays on its modelled type, and whether POTENTIAL stays a status. Phase 3's compare is the evidence for them.

Named and not built here: a lift rule scoped to watershed groups (#236 calls it optional); rule sources beyond PSCIS assessments, such as our own field assessments (#341; the source registry takes another entry); a side-by-side `lnk_scenario_export()` of two scenarios (#341; follows from open decision 6 (a)).

## Phase 1: Copies of one barrier agree (#386)

Review changed: where the persist filter sits (B3), the ownerless positions (B2), what the verify check can read (A2, B4), falls (G6), the proof's builds and diff (O2, O3, C3, A1, A6).

- [x] Measure before, as a committed script and its outputs under `data-raw/logs/barrier_copies_386/` (README indexes it): on the newest `fresh_default` this host holds, positions held by more than one group, rows held by a non-owner, copies that disagree (existence within 1 m, subtype, `blocks_species`), override copies that differ per species, positions whose owning group holds no row and whether that group is modelled, positions on no persisted segment, and each control row filed under a group that does not own its position with what it does today. The same ownership test for `user_barriers_definite.csv` rows and for the falls in fresh's `falls.csv`. The planning probes above are the expected magnitudes.
- [x] Read bcfishpass's `barriers_gradient.sql` at `3bd2824` and record whether its control table applies by position.
- [x] Open decisions 2 and 8 answered at the plan gate (O2 (a), O8 (a)); the boxes below are written for them.
- [x] Tests first (`tests/testthat/test-lnk_pipeline_prepare.R`, `test-lnk_barriers_unify.R`, `test-lnk_pipeline_persist.R`): a control row filed under another group prunes and locks at its position; a gradient position on another group's segment is not in the group's `barriers`, `barrier_overrides` or `barrier_override_evidence`; a position in the millimetre overlap or gap between two segments has exactly one owner; an override whose rounded measure falls on the neighbour's side of a group boundary is kept by the barrier's owner and by nobody else.
- [x] Controls by position: `.lnk_pipeline_prep_load_aux()` (`R/lnk_pipeline_prepare.R`) writes every control row to `<schema>.barriers_definite_control`, not the group's.
- [x] Owner-only persistence. The owner is taken once: the ltree `UPDATE` in `.lnk_pipeline_prep_gradient()` also writes the picked segment's group to a column on `gradient_barriers_raw` (its `ORDER BY downstream_route_measure, linear_feature_id` pick; a gap position by `.lnk_sql_locate()`'s nearest-segment order). `lnk_barriers_unify()` keeps the group's own gradient rows. `lnk_pipeline_persist()` writes an override or evidence row only where the group's own working `barriers` holds a natural row on that line within 1 m: never by the owner of the override's rounded position, and not by the own-segment test in `R/lnk_pipeline_classify.R`, which accepts either overlapping segment. The working tables stay whole-line, so the break-time reduction (`.lnk_pipeline_prep_minimal()`) and fresh's classify read what they read today.
- [x] Rewrite the comment in `.lnk_pipeline_prep_minimal()` that names the cost of group-filtered controls: with controls by position, a group's working copy of an override equals the owner's.
- [x] `data-raw/study_area_verify.sql`, from persisted data alone (gradient rows persist no `linear_feature_id`, and the file reads no FWA table): no two judged groups hold a gradient row at one line, measure and subtype, and no judged group holds an override or evidence row with no natural barrier row of its own within 1 m. Which groups are judged is a psql variable defaulting to 0.93.0, because the proof builds log 0.92.0 until the last commit; the check prints how many groups it judged. Add the failing and passing cases to `data-raw/study_area_verify_negative.sh`, each required to judge at least one group. That holder equals owner is proved in the unit tests and the diff script, which can read FWA.
- [x] `data-raw/recompute_deps.R` header and `R/lnk_wsg_deps.R` docs, worded to what was measured (gradient rows by construction; falls and user-definite rows by their files' groups): the owner rule holds for a schema wholly at 0.93.0 or later; the scheduler is unchanged (D8).
- [x] Choose the proof groups from the measurement: compute, for each candidate, the groups owning its non-owned positions, and take sets closed under that where they are small (the reproducibility pair ADMS and ELKR; BULK, which Phase 3's compare needs; a Peace set of FINA, LPCE, PCEA, UPCE, PARS; the groups the 7 control rows touch). Where the closure is the Fraser main-stem chain, take a few of its groups and give positions whose owner is outside the set their own diff category.
- [x] Build BEFORE and AFTER-386 for them, both bundles, from worktrees (never from a checkout being edited), with the recompute pass, each under a `run_uid`.
- [x] A diff script in `data-raw/logs/barrier_copies_386/`, keyed on source, line, measure and subtype (gradient ids and `id_segment` renumber when rows or cuts move), that stops on anything outside these categories and prints a count for each: a non-owner copy removed with nothing upstream changed; a row at or upstream of a position a re-filed control row touches; a row at or upstream of a position whose copies disagreed in BEFORE; a position whose owner is outside the set or does not hold it (open decision 8); a segment cut differently. It also asserts that every position and species lifted in BEFORE is lifted by its owner in AFTER-386, outside the control-touched positions. Commit its output.
- [x] Measure what a one-group run into an empty schema no longer holds, and what loading its dependencies from AFTER-386's rows restores (the published export holds builds older than 0.93.0, which still carry the copies).

## Phase 2: Several lift rules per species (#236)

Review changed: `.lnk_lift_rules()` takes `cfg` and stays on the vocabulary's path (B1), the key migration (G1), where the table's shape is tested (G2), the presence check's reader (G5), the measurement (O1), the verify wording (A5).

- [x] Tests first (`tests/testthat/test-lnk_barrier_overrides.R`, `test-lnk_observation_records.R`, `test-lnk_vocabulary.R`, `test-dictionaries.R`, `test-lnk_persist_init.R`): two rules for one species lift the union of what each lifts; a barrier neither rule meets alone is not lifted by their records together; the evidence names the rule; a duplicate (species, rule), a rule named `own`, a species absent from `parameters_fresh`, a `barrier_kinds` other than `natural`, and under `lift_floor` a rule whose listed species differ from its floor are each refused; a mixed-floor fixture still errors from `lnk_vocabulary_resolve()` before a run opens; the shipped `bcfishpass` bundle, whose BT rule mixes floors without `lift_floor`, still resolves; a `parameters_fresh`-shaped `params` gives today's output.
- [x] `parameters_barrier_lifts.csv`: `species_code, rule, barrier_kinds, observation_species, observation_threshold, observation_date_min, observation_buffer_m, observation_control_apply, date, source, notes`, with `inst/extdata/configs/dictionary_parameters_barrier_lifts.csv`. No bundle declares the file unless open decision 3 says (b): a declared header-only file would move `config_hash` for nothing. So its dictionary is tested against the reader's required-column constant and a fixture, outside `tests/testthat/test-dictionaries.R`'s generic loop, which needs a declaring bundle; `data-raw/audit_configs.R` reads it the same way.
- [x] `.lnk_lift_rules(cfg, loaded)`: one frame, a row per species and rule; rule `own` from `parameters_fresh` (first row per species, as the pipeline reads it) and the further rules from the lifts table. It holds the refusals above. The mixed-floor refusal moves here with both of its gates (`lift_floor` only, threshold above 0 only), per rule, and `.lnk_observation_species_map()` calls it, so `lnk_vocabulary_resolve()` still refuses before the log row opens.
- [x] `lnk_barrier_overrides()` (`R/lnk_barrier_overrides.R`) takes the rule frame and loops rules. `to` keeps its shape (a species is lifted where any rule is met). Habitat lifts run once per species on rule `own`'s list (D10). `.lnk_pipeline_prep_overrides()` gains `cfg` and passes `.lnk_lift_rules(cfg, loaded)`. `lift_readers` in `R/lnk_presence_check.R` reads the same frame.
- [x] (O5) `lift_rule` joins `cols_barrier_override_evidence` and the working table `lnk_barrier_overrides()` creates (the exported function's evidence shape changes: NEWS). `lnk_persist_init()` migrates an existing table in one transaction, each step skipped when the catalog shows it done: add the column, fill it from `evidence` (`own` for an observation row, `habitat` for a habitat row), set it not null, replace the primary key with one that includes it. `CREATE TABLE IF NOT EXISTS` does none of this on a table that exists. Test: a table built with the old key accepts two rows that differ only in `lift_rule` after init. `R/lnk_pipeline_persist.R` follows the column vector; `data-raw/schema_consolidate.R` copies shared columns by name, so it refuses a destination whose evidence table lacks the column instead of dropping it.
- [x] `data-raw/study_area_verify.sql`: every (lift, rule) present in the evidence reaches that rule's threshold of distinct records (only a rule that met its threshold writes rows); negative case added.
- [x] The run log records the rules applied (`R/lnk_log.R`, beside `log_parameters_fresh`).
- [x] Prove the mechanism runs where no shipped bundle uses it: on one proof group, run prepare and persist into a scratch schema with a scratch bundle (loaded by path) declaring a further rule, and read the evidence rows by rule. Those phases resolve no vocabulary; confirm that before relying on it.
- [x] Measure the candidate rule without a full run: on AFTER-386's kept working schemas for the proof groups, rebuild `observations_province` with `.lnk_pipeline_prep_observations()` (the run dropped it), call `lnk_barrier_overrides()` with rule `own` alone and with the candidate added, each to its own `to =`, count lifts added per group and species, and drop the rebuilt table. Output under `data-raw/logs/lift_rules_236/`.
- [x] (O3) Draft the follow-up issue that adopts or rejects the candidate BT rule from those counts; file it (our repo) and name it in the PR body. `default` declares no lifts table here.

## Phase 3: Which crossings are human-made barriers, as rules (#341)

Review changed: the PSCIS join key (S1), the column always written and what it holds (S2, S3), a derived column and a null operator (G3), where the compare's inputs come from (O4), a proof that cannot pass with the helper dead (A3).

- [x] Tests first (`tests/testthat/test-lnk_barriers_emit.R`, `test-lnk_barriers_unify.R`, `test-lnk_pipeline_crossings.R`, `test-dictionaries.R`, and a new test file for the rule helper): the reproducing row gives today's set; a non-reproducing rule file moves all four sites the same way; AND within a `rule_id`, OR across; `applies_to` scopes; a NULL measurement matches only `is_null`; an unknown source table, column, operator, a non-`*` species and an outcome other than `barrier` are refused at load; a value cannot inject SQL; `barrier_rule_id` does not depend on row order; a caller's `crossings` table with no `barrier_rule_id` falls back to the built-in rule, and the pipeline never produces one.
- [x] `parameters_barrier_rules.csv`: `rule_id, applies_to, source_table, column, operator, value, species, outcome, date, source, notes`, with `inst/extdata/configs/dictionary_parameters_barrier_rules.csv`. `default` and `bcfishpass` each ship one row (`status`: `crossings.barrier_status in BARRIER;POTENTIAL`, every source, every species, `barrier`), declared under `files:` in each `config.yaml` with provenance checksums written directly (`data-raw/regen_provenance.R` redates `rules.yaml`). The `bcfishpass` copy is link's own file: its provenance `source` must not be the string the weekly sync selects on.
- [x] A source registry in code: `crossings` (the row itself) and `pscis_assessment` (`whse_fish.pscis_assessment_svw`, joined on `aggregated_crossings_id = stream_crossing_id::text AND crossing_source = 'PSCIS'`, refused if the view holds two rows for one crossing), the latter with a derived `slope_length` as `lnk_score()` computes it (`R/lnk_score.R`), since a rule compares one column. Operators: `in`, `=`, `>`, `>=`, `<`, `<=`, `is_null`, `not_null`. A rule's column is checked against the source's columns, its value typed by the column and quoted through DBI.
- [x] The helper that writes `<schema>.crossings.barrier_rule_id` for every bundle (D4), called from `lnk_pipeline_crossings()` after the per-row overrides and before `lnk_barriers_emit()` (`R/lnk_pipeline_crossings.R`; nothing rebuilds `crossings` afterwards), and the SQL helper the four sites read: `R/lnk_barriers_emit.R` (three) and `R/lnk_barriers_unify.R` (one). A grep over `R/` finds no other status-set literal for the barrier set; the remediation definition (`pscis_status = 'REMEDIATED' AND barrier_status = 'PASSABLE'`) and fresh's break labels in `R/lnk_pipeline_classify.R` stay on `barrier_status`, which remains the source's own status.
- [x] The run log records the rule set applied (`R/lnk_log.R`, `R/lnk_persist_init.R`), so each total traces to its rules.
- [x] (O4) Remove `R/lnk_thresholds.R`, `R/lnk_score.R`, `R/lnk_source.R`, `inst/extdata/thresholds_default.csv`, their tests and the `tests/testthat/setup.R` line, their mentions in `R/lnk_pipeline_load.R` and `R/lnk_db_conn.R`, their rows in `data-raw/pretest_inputs.csv`, and the Score and Bridge sections of `CLAUDE.md`.
- [x] Measure whether a rule change needs a re-model, under `data-raw/logs/barrier_rules_341/`: marks through `lnk_access()` over a barriers table built under another rule file, totals through `lnk_aggregate(barriers = )`, seconds per group, and whether a rule that widens the set needs crossings the persisted `barriers` does not hold. State the finding, not the hypothesis.
- [x] Compare two rule sets on #321's parity groups, ADMS and BULK under the `bcfishpass` bundle (`data-raw/logs/crossings_upstream_478/stamp.csv`), reading AFTER-386's persist schema and kept working `crossings` (`crossings` is not persisted): the province's result against measured rules (outlet drop above 0.6 m, slope × length above 120), both added to it and in place of it for assessed crossings, the in-place set keeping the province's result where a measurement is null. Count crossings that change class each way, assessed crossings with no measurement, and the per-crossing below-barrier km that change, per species.

## Phase 4: Tokens, proofs, docs, release

Review changed: the token decisions are the owner's (C2), what "equal" compares (A4), the proof that the helpers ran (A3), the gate map (G7).

- [x] Open decisions 6 and 7 answered at the plan gate (O6 (a), O7 (b)).
- [x] `R/lnk_vocabulary.R`: the `acc` spec reads the lift rules and the barrier-rule rows decision 6 names (rule columns only, never `date`, `source`, `notes`); `.lnk_vocabulary_canonical()` is not edited (an edit re-specs every `acc` row). `inst/extdata/vocabulary.csv` retires `acc-v7` and `acc-bcfp-5` at 0.93.0 and adds `acc-v8` and `acc-bcfp-6`, and (O7) retires `cut-full-top-4`, `cut-full-ssf-all-3` and `cut-min` for successors; `tests/testthat/test-lnk_vocabulary.R`. Every shipped bundle that resolved before still resolves (`default`, `default_tuned`, `default_minimal`, `default_parent`, `bcfishpass`); `default_extrabreaks` and `default_rearbreaks` have no rows before or after.
- [x] Build FINAL for the proof groups, with the recompute pass. Under O3 (a), FINAL equals AFTER-386 by digest in every persisted model table, the evidence table compared on AFTER-386's columns with `lift_rule` in (`own`, `habitat`) and the log tables left out. On FINAL, `barrier_rule_id` is non-NULL on exactly the crossings today's predicate selects, in every proof group's kept working schema.
- [x] `bcfishpass` bundle against the reference on the proof groups that bcfishpass models: accessible and observed km unchanged or closer, each move named.
- [x] `data-raw/pretest_inputs.csv`: a row for each new `R/` file and for each new file under `inst/extdata/` (the rules table drives crossings, the lifts table observations), each with the input it drives, and `tests/testthat/test-pretest.R` green. The unmapped-file test catches a missing row, not a wrong input: read each new row against what the file changes.
- [x] `RUNBOOK.md`: §2a (the barrier set comes from rules), §5 (several lift rules; one holder per position), §6b if a token rule changed, §7 (the two tables and who owns which column), §8c (what a one-group run needs), §8d (the owner rule and the verify checks).
- [x] `research/barrier_rules.md` (new, with the header line and a row in `research/README.md`): what is known about copies, lift rules, the rule compare and the recompute finding. `research/bcfishpass_parity.md` only if parity moved.
- [x] `CLAUDE.md` status block for 0.93.0 (owed, facts not worth re-deriving) and its function lists.
- [x] `devtools::document()`, lint compared per file against `origin/main`, `devtools::test()`, `devtools::check()`, `pkgdown::check_pkgdown()`.
- [x] `/code-check branch`, fixes as follow-up commits (3 rounds and an enumeration; `review-round1..3.md`, `review-enumeration.md`, `review-verdict.md`).
- [x] `planning/backlog.md`: batch 16's carry line names the split issue (O1) and the BT-rule follow-up (O3).
- [x] `NEWS.md` and `DESCRIPTION` to 0.93.0 as the last commit.

## Owed at the end (reported, done after merge)

- [ ] Every group re-models at the next provincial run (`acc-v8`, `acc-bcfp-6`), after the pre-run gate runs again (`R/`, `inst/extdata/`, `pretest_inputs.csv` changed).
- [ ] `lnk_persist_init()` once per host on each persist schema at a quiet time, for the evidence table's column and key, before any consolidate into it.
- [ ] The scheduler's move to the owner rule, after a provincial run leaves every group at 0.93.0 or later (speed track).
- [ ] The #201 + #83 issue filed from the draft below once the owner has read its body.
- [ ] #341's body edited to what remains open (which rules `default` adopts, unassessed crossings, POTENTIAL, sources beyond PSCIS, the side-by-side export); #236's optional group-scoped rule named where it is left.
- [ ] A full bcfishpass parity re-score on the 17-group closure, at the provincial run.

## Validation

- [x] Tests pass
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

How each change is proved:

- **#386:** the diff script puts every changed row between BEFORE and AFTER-386 in a named category with a count and stops otherwise; no lift is lost outside the control-touched positions; the verify check judges at least one group, passes on AFTER-386, and its negative cases fail as written.
- **#236:** unit tests for the union, the refusals and the evidence; one group run through prepare and persist with a further rule; FINAL equals AFTER-386 with no further rule declared; the candidate rule's lifts counted without a build.
- **#341:** a non-reproducing rule file moves all four sites in tests; on FINAL the marker sits on exactly today's set and FINAL equals AFTER-386 (the issue's byte-identical run, on every proof group); the compare reports class changes and km for two rule files.
- **Tokens:** each shipped bundle resolves to exactly one live row per axis; the append-only vocabulary test passes in the checkout.
- **A guard is shown firing:** for each refusal and each verify check, the test or negative case restores the defect and goes red.

## Draft issue for the split piece: which barriers block which species (#201, #83)

Not filed. Under open decision 1 (a) or (c) the owner reads this body, then it is filed and named in batch 16's carry line. Under (b) its phases follow Phase 3 here.

> **If we do it:** a bundle can say that a kind of human-made barrier blocks a species, and the same evidence rules that lift a natural barrier can lift a dam. **If we never do:** dams, assessed crossings and modelled crossings never block access for any species, whatever is known about them.
>
> Split from move 11 (#479), which shipped the rule tables this builds on: `parameters_barrier_rules.csv` (its `species` and `outcome` columns accept only `*` and `barrier` today) and several lift rules per species (`barrier_kinds` accepts only `natural` today).
>
> **What changes**
> - `barriers` carries what a row is made of rather than a precomputed `blocks_species`: `gradient_class` for gradient rows, and every crossing on a main line with its status, not only the ones in today's barrier set. The access views decide per species from the bundle's rules. Every group's `barriers` is rebuilt once for this, unless move 11 already stored the new columns and rows.
> - A rule row with `outcome = blocks` and a species puts matching crossings in that species' access set, in the break-time recipe and in the persisted view alike (one generator for both). The rule lives in the barrier rules table, not in `dimensions.csv` as #83 first proposed.
> - A lift rule names the barrier kinds it may lift, so a dam with fish recorded above it opens for the species the rule names.
> - `default` and `bcfishpass` ship no `blocks` row: their output does not move until the owner adds one.
>
> **Decisions for the plan gate**
> - Drop `blocks_species` from the persisted table, or keep it as a derived column for one release.
> - Which species and dam classes `default` blocks, if any, and from what source (`dam_use`, passability, fish passage type).
> - Whether assessed and modelled crossings can block, or only dams.
> - Whether a rule needs a date or age condition, for a dam decommissioned recently (#83's question).
> - Fresh's classify still reads crossings as non-blocking, and the habitat gate settles habitat on link's access afterwards; whether that is enough, or fresh takes a per-species blocking label.
>
> **Phases**
> 1. Ingredients on `barriers` and a migration for existing persist schemas, with the access views reading them; digests unchanged for both bundles.
> 2. `blocks` rows: access views, the break-time sets and the downstream-state guard read one recipe; proved on LFRA (Coquitlam, Alouette, Stave) and PARS with a scratch rule file.
> 3. Lift rules scoped to barrier kinds; the evidence table names the kind.
> 4. Docs, research, release.
>
> Answers the questions #201 and #83 ask.
