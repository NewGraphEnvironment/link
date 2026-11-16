# Task: Backlog move 2: Which fish records count, and what each lift rests on (#470)

Move 2 of planning/backlog.md: batch 2 (#400, #398, #425: which records count) and batch 3 (#434, #426, #427, #236: what each lift rests on). One phase per batch where it fits, one PR; /gh-pr-merge ticks the move on merge.

## Context

Three things decide what a fish record does in link: whether it makes a segment read
"known" (`access_<sp>` = 2 rather than 1), whether it cuts the stream (each species'
top record per line under `default`), and whether it lifts a natural barrier. Today
each follows its own rule. Code 2 and the cuts count every record of the exact
species code, of any date. Lifts read `parameters_fresh.csv`'s per-species date,
count and species list. Alias codes are folded in four places by hand-copied CT-only
lists (`R/lnk_pipeline_break.R:240`, `R/lnk_presence_check.R:76`,
`R/lnk_presence_measures.R:89,115`), and the walk tests exact codes, so CT aliases
cut streams but never make CT "known" (#398). Steelhead and char aliases are dropped
everywhere (#425, 1,000+ records). Nothing records which records lifted which barrier
(#434), so knowledge#178 would have to re-implement `lnk_barrier_overrides()`.

The outcome: one record rule, held as data in the bundle, read by the observation
filter, the walk, the breaks, the lifts, the presence check and the validator. Each
lift is published with the records behind it. One release, `acc` rows moved, outputs
move at the next provincial re-model.

Found while exploring: bcfishpass's `load_observations.sql` (at `620dbe4` and
`3bd2824`) tests the record's raw code against a presence array holding only `CT`, so
`CCT`, `ACT` and `CT/RB` records never reach `bcfishpass.observations`; its remap of
them is dead code. link's `bcfishpass` bundle admits them, so it cuts at records
bcfishpass does not. This is to be confirmed on the reference database first (Phase 1).

## Decided at the gate (operator, 2026-11-16)

1. **Dates (#400):** under `default`, code 2 and the observation cuts use each
   species' lift floor (`observation_date_min`). Salmon, steelhead, GR and KO records
   need 1990-01-01 or later; residents (BT, RB, WCT) count any date, undated included.
2. **Pooling (#400):** code 2, the cuts and the lifts follow `species_pooling.csv`.
   BT's lift stops listing DV (`observation_species` `BT;DV` → `BT`); DV counts as BT
   only where the tracker pools it. Lifts and accessible km are measured before and
   after on coastal groups and reported.
3. **Two-way codes (#425):** `BT/DV` and `DV/BT` count as BT only where the tracker
   pools DV into BT; elsewhere, and `RB/CT` everywhere, they count as neither.
4. **#236:** its body is cut to multi-rule observation overrides only, and it stays
   open outside this move.
5. **The `bcfishpass` bundle** follows bcfishpass and is otherwise unchanged: no
   date floor on code 2, no pooling, alias records dropped if Phase 1 confirms that is
   what bcfishpass does.

Recommended in this plan, settled by approving it:

- **The alias rule is rows in `species_pooling.csv`** at a new `province` scope (the
  least specific level), each with its reason and issue. One tracker for "which
  records are which species". The `bcfishpass` bundle declares no tracker, so it folds
  nothing.
- **The date rule is a pipeline key**, `observation_record_date: lift_floor | any`
  (`any` when absent). `default` sets `lift_floor`.
- **#426:** `bcfishpass` takes `>` (parity) by writing its salmon and steelhead
  `observation_date_min` as `1990-01-02`, if `observation_date` is a date type (checked
  first). `default` keeps `>=`: a record dated 1 January 1990 usually means "sometime
  in 1990", which is inside a 1990 floor.
- **#434's table** is `<persist>.barrier_override_evidence`, one row per lifted
  barrier, species and evidence record, with the rule as applied on each row.
- **#427:** the threshold is decided mid-run from measurements (1, 2 and 5 records);
  `observation_control_apply` stays, so the control table still vetoes lifts at known
  falls.

## Phase 1: Check bcfishpass and the inputs before changing anything
- [x] On the bcfishpass reference DB, count `bcfishpass.observations` by `species_code`
      (are `CCT`, `ACT`, `CT/RB`, `SST`, `WST`, `ADV`, `ABT` and the two-way codes absent?),
      pinned to `bcfishpass.log.model_version`; record it in `findings.md`
- [x] Type of `bcfishobs.observations.observation_date` (date or timestamp) on local fwapg,
      which decides how #426's `>` is written
- [x] Count alias and two-way records per group on local fwapg, and pick measurement
      groups: FINA, UFRT, MFRA, VICT (#425), a group with CT aliases (#398), two coastal
      or lower-Skeena BT groups where DV lifts today (decision 2), and BULK, PARS for parity
- [x] Check `parameters_fresh.csv`'s provenance in both bundles (link's own file or a
      synced copy), which decides where #426's and decision 2's edits go

## Phase 2: One record rule (#400, #398, #425)
- [x] `lnk_species_pooling()`: a `province` scope level (`BC`), least specific; an evidence code
      that is no species column is an alias; dictionary text and tests
- [x] `default`'s `species_pooling.csv`: alias rows (`SST`, `WST` → ST; `ADV` → DV;
      `ABT` → BT; `CCT`, `ACT`, `CT/RB` → CT) and two-way rows (`BT/DV`, `DV/BT` → BT
      in each scope where DV pools into BT), each with its reason and issue
- [x] One helper, `.lnk_observation_species_map(cfg, loaded, wsgs)` (`R/lnk_observation_records.R`):
      per group, which recorded codes count as which present species (every presence column,
      not `cfg$species`: CT, DV, KO and RB records still cut), with the date floor and year limit.
      It replaces `.lnk_pipeline_break_obs_species()`'s hard-coded CT list. Pooling follows the
      record's own group, as presence does
- [x] `<schema>.observations` and `observations_province` built from the map: one row per
      record and model species, `species_code` the model species, the recorded code kept
      in `species_code_recorded`. Breaks, the walk and the lifts read them unchanged
- [x] `observation_record_date` pipeline key with its check; `default` sets `lift_floor`
- [x] `default`'s BT `observation_species` `BT;DV` → `BT`; WCT's floor `1900-01-01` → NA, so
      undated WCT records count toward code 2 and the cuts (its lift reads NA as 1900-01-01, unchanged)
- [x] Under `lift_floor`, a lift list that mixes date floors is refused
- [x] `.lnk_presence_check()` and `.lnk_presence_measures()` read aliases through
      `.lnk_record_aliases()` (the tracker, every species present), as their own records; the CT-only
      lists go, in the check's driver too (its SQL recounts and its alias sensitivity block).
      `lnk_habitat_validate()` already takes the tracker's resolution from its driver, so it counts
      alias codes with no change; it applies no date floor (it scores habitat, not access)
- [x] The cut spec carries a digest of the record rule where observations cut; the acc spec the
      rule resolved per group. Provisional rows `cut-full-top-2`, `cut-full-ssf-all-2`, `acc-v6`,
      `acc-bcfp-5` (predecessors retired at 0.84.0); their specs are recomputed after Phase 4
- [x] Pre-run gate map rows for `R/lnk_observation_records.R` and the inputs the rule reads;
      dictionary line references remapped; provenance checksums refreshed
- [x] Tests: a `CCT` record gives `access_ct` = 2 through the walk and 1 with exact codes;
      `SST` makes ST known; `BT/DV` counts as BT only where DV pools; a 1985 CH record is dropped
      under `lift_floor` and kept under `any`; the two-way rows track DV's pooling; the alias codes
      exist in bcfishobs; the `bcfishpass` bundle's tables lose alias records

## Phase 3: Measure the record rule
- [ ] `default` before and after on the Phase 1 groups: code 2 km by species (1 → 2 and
      2 → 1), segment counts, lifts and accessible km (the coastal BT groups for decision 2)
- [ ] `bcfishpass` before and after on BULK and PARS: segments and parity
- [ ] Evidence in `data-raw/logs/record_rule_470/` with a README; every change traced to a
      record a cut, a lift or code 2 now counts or drops (a lift moves access across the network
      above it). The README says the numbers are at the provisional acc-v6, before #426 and #427

## Phase 4: What each lift rests on (#434, #426, #427, #236)
- [ ] #434: `lnk_barrier_overrides()` also writes the evidence (observation lifts: each
      record's key, recorded code and date; habitat lifts: the habitat row; every row: the
      threshold, date floor, species list and comparison applied), DISTINCT over barrier, species
      and key (natural_barriers repeats positions); optional, and falling back to `species_code`
      for a caller's table with no `species_code_recorded`
- [ ] #434: `barrier_override_evidence` in `lnk_persist_init()` (`cols_*` vector,
      `.lnk_validate_persist_table()`), `lnk_pipeline_persist()`, consolidate's core table list,
      `_HOSTS_PERSIST_CORE` (`data-raw/study_area_hosts.sh`) and the tests that hold those lists equal
- [ ] #434: `study_area_verify.sql` asserts, over the run's own groups, that its (barrier,
      species) set equals `barrier_overrides`', and that each observation lift holds at least its
      threshold of distinct records; a schema without the table is a NOTE; negative cases in
      `study_area_verify_negative.sh`
- [ ] #426: `bcfishpass` takes `>`, `default` keeps `>=`; lifts counted before and after
      on BULK, PARS, ADMS, BABL and ELKR
- [ ] #426: correct RUNBOOK §5's "no date floor" line (an undated record never counts
      toward a lift)
- [ ] #427: measure thresholds 1, 2 and 5 for CH, CM, CO, PK, SK, ST, GR and KO on a few
      `default` groups (lifts added, accessible km added, new lifts resting on one record);
      bring the numbers to the operator, then set `default`'s threshold
- [ ] #236: rewrite its body to multi-rule overrides only (what pooling answered,
      what remains), and leave it open

## Phase 5: Vocabulary, docs, release
- [ ] The `acc` spec carries the record rule (the pooling tracker, canonical, and
      `observation_record_date`); new rows `acc-v6` and `acc-bcfp-5`, `acc-v5` and
      `acc-bcfp-4` retired at 0.84.0, append-only test passes
- [ ] `data-raw/pretest_inputs.csv` rows for every changed file the gate maps
- [ ] RUNBOOK §2c, §5, §6b (the CT alias line) and §7 ("The record rule"), including that
      `default_extrabreaks` and `default_rearbreaks` have no tracker and lose CT alias admission;
      README or research text that states the old rule; `CLAUDE.md` status block; NEWS; version 0.84.0
- [ ] `devtools::document()`, `devtools::test()`, `lintr` (per-file against main),
      `devtools::check()`

## Owed at the end (reported, done after merge)
- [ ] Provincial re-model of `fresh_default` and `fresh` at `acc-v6` / `acc-bcfp-5`
      (operator's word), after the pre-run gate runs again (`R/` changed)
- [ ] The export carrying `barrier_override_evidence` for knowledge#178 (move 5, #473)
- [ ] #236 open with its narrowed body

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the fixture tests above go red with the old rule restored; Phase 3's
before/after builds move only where a counted or dropped record sits; the verify
assertion fails on a hand-deleted evidence row and passes on a real build; the
`bcfishpass` parity groups move no further from bcfishpass than Phase 1 predicts.
