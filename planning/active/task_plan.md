# Task: Backlog move 16: Rainbow trout back in default, and the presence review's last rows (#501)

**If we do it:** `default` models rainbow trout again on records told apart from steelhead, and the presence review's remaining rows are decided. NewGraphEnvironment/knowledge#148 can then bring rainbow trout rearing back. **If we never do:** rainbow trout stays paused in `default`, with no access, habitat or mapping code anywhere, and the review's pending rows stay pending.

Batch 24 of `planning/backlog.md`: #497 (bring rainbow trout back to `default`: tell its records from steelhead, decide its three presence rows) and #402 (check each group's species presence against its fish records). One PR. Lands before the next provincial runs (move 17, #502) so they are not made stale by it.

## Decided at the gate

There was no plan gate in this pane: `/coordinator` dispatched this `park review` (soul#928), and its plan gate ran at the resume: the answers are under "Decided at the resume". The Plan review ran before the baseline (`planning/active/review-plan.md`); what it changed is marked *(review)* below.

What the plan takes as settled, from earlier owner decisions:
- The record rule is one rule, read by the cuts, code 2 and the lifts, written as rows of `configs/default/species_pooling.csv` (#470). A row counts one code as one target; aliases do not chain.
- Presence decisions that leave a cell unlike bcfishpass's copy are rows of `overrides/wsg_species_presence_overlay.csv` with their reason (#431, #472); a decision that agrees with the copy has no overlay row.
- The presence rule is one record dated 1950 or later, releases out, exclusions first, pooling applied (#402, operator 2026-10-30). The first review's precedents (2026-11-01, `research/species_presence.md`, "The first review") stand: cells resting only on stocked fish were removed; Mackenzie salmon were left unmarked as strays.
- A paused species keeps its rules, thresholds and presence column (#432); unpausing is a `species_modelled.csv` edit, a new `acc` row and a version bump.

## Decided at the resume (owner, 2026-11-23)

Asked after Phase 1's numbers (`data-raw/logs/rb_st_497/`):

1. **Record rule: (b).** An ST record counts as RB where RB is marked present; an RB record never counts as ST. Accepted costs: `cut-full-top-3`, RB's top per line moves in 77 groups, undated ST records cut for RB. Option (c) is not built.
2. **RB rows:** LPRO and UPET RB removed (stocked fish only, the first review's precedent). CRYL RB goes to the literature issue as a native-range question (Cry Lake, Dease River, Liard side).
3. **KO's 138 rows wait for kokanee's return (#432).** Their `issue` stays `#432`.
4. **The four cells since #470:** recommendations come from Phase 3's re-run (asked then).
5. **#402's 13 rows:** decide the 10 the records settle; TURN ST, CLRH CT and DUNC CT go to a literature issue naming move 16. The owner saw a cutthroat in the Duncan on a snorkel survey about 15 years ago (operator observation, for DUNC CT's story). Accepted cost: a second `acc` token later.
6. **#402 closes with this PR.** The rows split out carry the literature issue's number, and KO's carry `#432`.
7. **ST evidence may flag an RB cell** (no change to `.lnk_presence_check()`). The one new flag, TUTR RB (two Steelhead Database records, 1984 and 1991, Tutshi River, Yukon headwaters, where steelhead do not reach), goes to the literature issue.
8. **The SST/WST alias change is done here:** `SST` and `WST` count as RB as well as ST, in `.lnk_record_aliases()` and its three readers, with tests.

So the literature issue carries CRYL RB, TUTR RB, TURN ST, CLRH CT and DUNC CT.

## Open decisions

None open. Write any fork met from here under this heading.

## The forks as drafted at the park

Kept as the record of what was asked; the answers are above.

1. **How a rainbow trout record is told from a steelhead one** (before Phase 2; informed by Phase 1).
   - **(b, recommended pending Phase 1's numbers) One way: steelhead records count as rainbow trout, never the reverse.** A pooling row `RB ← ST` (province scope, or the regions Phase 1 supports). Where RB is marked present, an ST record counts as RB for RB's cuts, code 2 and lifts (lifts filter on the model species over `observations_province`, `R/lnk_barrier_overrides.R:253`). An RB record never counts toward ST, so a resident rainbow above a falls cannot open steelhead access. KOTL's steelhead record, judged a likely rainbow at the first review, then counts as RB. Costs *(review)*:
     - Records are dated by RB's floor, which is none. Undated and pre-1990 ST records cut and set RB's code 2, while the lift still drops undated ones (an empty floor reads `1900-01-01`, `R/lnk_barrier_overrides.R:181-182`).
     - In groups holding both species, RB's top record per line becomes the higher of the RB and ST tops. An old RB-only top can stop cutting, so segments move for every species.
     - The record-rule digest moves the cut spec: one new row, `cut-full-top-3`.
     - `SST` and `WST` do not count as RB under (b) alone: decision 8.
   - (a) Code alone: unpause RB with no new row. RB records count as RB and ST as ST, as the record rule reads them today. No cut token moves; only `acc` does.
   - (c) By place: an ST record above an unlifted ST-blocking natural barrier counts as RB instead of ST, and an RB record in steelhead-reachable water of a group where ST is present counts as neither. This is a new rule in code, since the record rule has no place term. If chosen, split it out (decision 8).
2. **The three pending RB rows** (before Phase 3).
   - CRYL RB (`absent_recorded`; one 1985 BC Lakes Database record, one lake at 1,212 m, Mackenzie): **add, recommended** (the one-record rule; a resident trout in a lake, not a stray), or keep absent as the Mackenzie salmon were.
   - LPRO RB (90 records) and UPET RB (2), both `present_unsupported`, releases only: **remove, recommended** (the first review removed THOM CT, LNTH CT, VICT DV and BULL GR for resting only on stocked fish), or keep (stocked fish live there). *(review)* LPRO's DV cell keeps RB's breaks there through `ct_dv_rb` promotion even after its RB cell goes. RB would then cut with no RB lifts, because the record rule reads raw presence while `.lnk_pipeline_prep_minimal()` promotes.
3. **KO's 138 rows** (before Phase 3). **Recommended: they wait for kokanee's own return** (#432 sources the column). Their `issue` stays `#432`, and #402 hands them over when it closes. Or decide them now as overlay rows: kokanee stays paused, but every KO cell added makes KO records cut streams. That moves the `acc` token and real cut positions. *(review)* It does not move the `cut` token: the record-rule digest is resolved with every species present (`R/lnk_observation_records.R:278-292`).
4. **The four cells the check reads differently since #470** (before Phase 3; Phase 3 seeds their rows and drafts a story for each):
   - VICT DV: removed at the first review for stocked fish; it now has one counting record under the alias codes.
   - FINA ST, MFRA BT and UFRT ST: flagged for the first time, one record each.

   A recommendation per cell comes from Phase 3's re-run.
5. **The 13 pending rows outside KO and RB** (before Phase 3): 8 BT cells resting on DV records (CHIL, CLWR, EUCH, LKEC, LSAL, MUSK, SALR, STUL), CT FINL and LOMI, TURN ST, CT CLRH and DUNC.
   - **Recommended: decide all 13 now from their records and the first review's precedents, provisionally, with no literature PR.** CLRH and DUNC CT rest on releases only, and the stocked-fish precedent says remove. TURN ST rests on two 1969–1981 Steelhead Database records in the Mackenzie basin.
   - Or decide the 10 that the records settle, and split TURN ST, CLRH CT and DUNC CT into a literature issue naming move 16, leaving #402 open on them.
   - *(review)* Moving any of #402's rows into a separate later PR means a second `acc` token before move 17, against the batch's "one `acc` row".
   - *(review)* RB is already marked present in CLRH, DUNC, FINL, LOMI and TURN, so their CT and DV decisions promote no new RB breaks. Promotion is new only where CT or DV is present and RB is not. In the current table that is 16 groups: BEAV BLUR CHUK COAL DEAL DEAR FROG JENR KTSU KUSR LKEC LRAN MBNK NBNK SWIR TOAD. A decision on LKEC's BT row does not change that.
6. **Whether #402 closes with this PR** (before Phase 6). Recommended: yes, if every row outside KO is decided and KO's rows are handed to #432.
7. *(review)* **Whether evidence pooled into RB may flag an RB presence cell** (before Phase 3, under option b). The presence check resolves pooling as if every species were present (`R/lnk_presence_check.R:76-82`). A province `RB ← ST` row would therefore flag `absent_recorded` RB in every group with a counting ST record and no RB cell. The pipeline pools only where RB is marked present. **Recommended: no.** Count RB's own records only for the RB flag, and keep the pooled count as context in the story. That is a change to `.lnk_presence_check()` with a test. Or yes: those groups become a decision class in Phase 3, and Phase 1 counts them.
8. *(review)* **Split out the alias change and option (c)** (before Phase 2). Counting `SST`, `WST` (or `CT/RB`) as RB as well as their own species is refused today (`.lnk_record_aliases()`, `R/lnk_observation_records.R:231-236`). The refusal protects three readers:
   - `.lnk_record_aliases_everywhere()`, which drops a two-target alias (`:257-262`), so SST would stop folding into ST in the historical zones;
   - `.lnk_presence_measures()`, which joins one target per group and code (`R/lnk_presence_measures.R:160-166`) and trips `data-raw/wsg_species_presence_check.R:126` on duplicates;
   - `data-raw/wsg_species_presence_map.R`.

   **Recommended: file the alias change (and option c, if chosen) as issues naming move 16**, and carry (b) on the `ST` code only.

## Phase 1: Measure rainbow trout and steelhead records by code and place (#497)

- [x] *(review)* State the host and build Phase 1 reads: a province-wide `fresh_default` whose `barriers` and lifts are current on local fwapg. Stamp that build's `run_uid` and tokens in the log.
- [x] *(review)* Extend `.lnk_presence_measures()` (`R/lnk_presence_measures.R`) so an RB-coded record can be measured against ST's blocking barriers. Today it matches barriers on the record's own code (`o.species_code = ANY (b.blocks_species)`), so RB records would find RB's 25 % barriers. This is an R change: add a test and a `data-raw/pretest_inputs.csv` row.
- [x] `data-raw/rb_st_records_check.R` takes every bcfishobs record coded `RB`, `ST`, `SST`, `WST`, `RB/CT`, `CT/RB` or ` RB` (leading space). It applies `observation_exclusions` (the copy and link's own) first, and tags releases as bcfishpass tags them. Per record it writes:
  - group, region and subregion (`inst/extdata/wsg_regions.csv`);
  - whether RB and ST are marked present in its group (overlay applied);
  - date, source, lake or stream, and elevation;
  - the nearest natural barrier below it that blocks ST (0.20 access gradient, falls, user-definite, subsurface), with its kind and whether a lift opens it for ST.
- [x] Per group and province, count four classes: RB records in steelhead-reachable water, RB records above the steelhead barrier, ST records above an unlifted steelhead barrier (likely rainbow), and ST records in reachable water. For each of options (a) to (c), count:
  - how many records count as RB;
  - how many RB lift positions each would open (RB lifts on one dated record);
  - how many groups' RB top-per-line moves;
  - *(review)* how many groups the presence check would newly flag RB in.

  Count independently in SQL for three groups.
- [x] `data-raw/logs/rb_st_497/` with a README (question, method, numbers, what they say about each option) and a stamp (`lnk_stamp()`, bcfishobs row count and newest date, the build read). Committed before Phase 2. The numbers go to the owner with Open decisions 1, 7 and 8.

Outcome: no `pretest_inputs.csv` row was needed (row 86 already maps `R/lnk_presence_measures.R` to `none`). Records are written gzipped (26 MB raw).

## Phase 2: The record rule for rainbow trout (#497)

- [x] Write the chosen rule into `configs/default/species_pooling.csv`, with its rationale, source (the Phase 1 log), verified date and issue `#497`. Update `configs/dictionary_species_pooling.csv` if a column's meaning changes.
- [x] Decision 8 keeps the alias change in this PR: change `.lnk_record_aliases()` and each of its readers named there, with tests. If it splits it out, file the issue naming move 16.
- [x] Tests in `test-lnk_observation_records.R` (and `test-lnk_barrier_overrides.R`) *(review)*:
  - an ST record counts as RB where RB is present and the row applies;
  - an RB record never counts as ST;
  - `SST` and `WST` count as RB and as ST (decision 8);
  - an undated ST record counted as RB cuts and sets code 2, but does not lift;
  - the record-rule digest moves.
- [x] RUNBOOK §7, "The record rule", updated in the same commit.

## Phase 3: Unpause rainbow trout and decide the presence review's remaining rows (#497, #402)

- [x] *(review)* First, set RB to `t` in `configs/default/species_modelled.csv` and clear its reason, date and issue as `configs/dictionary_species_modelled.csv` requires. The check's stories and its `modelled` column read `cfg$species` (`R/lnk_presence_check.R:360-371`), so the re-run must see RB modelled.
- [x] Decision 7 lets ST evidence flag RB: no change to `.lnk_presence_check()`.
- [x] Re-run `data-raw/wsg_species_presence_check.R --seed-tracker --out=data-raw/logs/presence_check_501/` at this branch's head, with Phase 2's rule and the unpause in force. This gives the four cells since #470 their tracker rows, and counts RB records under the new rule. Commit the log directory, and record the RB flag count before and after.
- [x] Record each decision in `configs/default/wsg_species_presence_review.csv` (`decision`, `reviewer`, `review_date`, `issue`), with the story opening on its reason. The rows to decide:
  - the 3 RB rows;
  - the 4 cells;
  - the 13 rows outside KO and RB;
  - any new RB flags (decision 7);
  - the 138 KO rows, as decision 3 settles.
- [x] Each decision that leaves a cell unlike bcfishpass's copy is a row of `overrides/wsg_species_presence_overlay.csv`, whose `reason` carries the decision, the rule and the story's opening, plus the `issue`. A decision that agrees with the copy has no row. VICT DV already has a removal row: change it or keep it.
- [x] Re-run the check; the decided rows drop out of its flags.
- [x] `test-lnk_csv_sync.R`: re-pin the loaded species-cell digest deliberately where cells moved.
- [x] *(review)* `data-raw/pretest_inputs.csv:123` maps the presence overlay to `segments` only, but a cell decides which records are seen (`observations`, `obs_upstream`). Add those rows, or say why not.
- [x] `research/species_presence.md`: revise it in place with the second review (rules applied, decisions by class, what is left), and update its `**Verified:**` line.

Outcome: the re-run seeded FINA ST, MFRA BT, UFRT ST, TUTR RB and UFRT RB; the owner decided them with the rest (2026-11-23): VICT DV and MFRA BT added, FINA and UFRT ST kept absent, UFRT RB to #515. The check also needed `--evidence=` and a zone fold for a two-target alias.

## Phase 4: Tokens and release (#497)

- [x] Tests that pin the pause or the tokens *(review)*:
  - `test-lnk_config.R:620-638` ("default and default_tuned pause KO and RB", and the `paused: +KO, RB` print);
  - `test-lnk_pipeline_species.R:124-129` (MURT and KOTL read the shipped bundle);
  - `test-lnk_vocabulary.R:74-87` (default's and default_tuned's tokens);
  - `test-lnk_log.R:744` (default_tuned's tokens).

  `test-lnk_pipeline_run.R:335` mocks the species and needs no change.
- [x] *(review)* Vocabulary rows are keyed by spec, not by bundle. Add `acc-v7`, which `default`, `default_tuned`, `default_minimal` and `default_parent` all share (`test-lnk_vocabulary.R:140-147`). Under option (b), also add `cut-full-top-3`, shared by `default`, `default_tuned` and `default_parent`. `default_minimal` does not cut at records, so `cut-min` and `grad-parent` stay (`R/lnk_vocabulary.R:149-153`). Retire the replaced rows at the release version; the append-only test must pass. Confirm with `lnk_vocabulary_resolve()` on all four.
- [x] Provenance checksums for the changed bundle files, written directly: `regen_provenance.R` re-dates `rules.yaml` every run.
- [x] Docs *(review)*:
  - `R/lnk_pipeline_species.R:50` example, then `devtools::document()` (`man/lnk_pipeline_species.Rd`);
  - `research/output_vocabulary.md:33`;
  - RUNBOOK §7, "Pausing a species": `default` pauses KO only. With RB modelled, a group with CT or DV marked present and no RB cell breaks streams at RB's barriers with no RB lifts (`ct_dv_rb`; 17 groups at #501, LPRO added by its RB removal). Done.
- [x] Version 0.90.0 in `DESCRIPTION` (main reached 0.89.0 after the park), a `NEWS.md` entry, and a `CLAUDE.md` status block (what moved, what is owed, facts not worth re-deriving).

## Phase 5: Verify on builds (#497)

- [x] *(review)* Pre-flight on local fwapg in scratch schemas. Build three states, each from its own `git worktree`:
  - `main`;
  - this branch with RB still paused (the record rule and presence alone);
  - this branch as it ships.

  Each difference then has one cause. Build three groups, the smallest that qualify:
  - one with ST and RB present (Skeena or Fraser);
  - one with RB present and no ST (interior);
  - one of the 16 groups where RB's breaks come only through promotion, CHUK excepted (not in the run).
- [x] Report per group:
  - segments in each state;
  - RB access km (codes 1 and 2), habitat km, and code 2 km;
  - lifts on RB resting on ST records (`barrier_override_evidence.species_code_recorded = 'ST'`) *(review)*;
  - that no other species' access or habitat moves beyond what re-segmentation explains (`data-raw/habitat_diff_segments.R`).

  Compare RB with the last pre-pause build of the same groups, if one exists (`acc-v4`, m1's `fresh_default_20261023`).
- [x] *(review)* From the presence table and records alone, count the groups whose cuts move province-wide: RB present with ST records, plus the 16 promoted groups.
- [x] `data-raw/logs/rb_return_501/` README with the stamp, commands and numbers.
- [ ] Run `devtools::test()`, `devtools::check()`, `lintr` per file against `origin/main`, and `pkgdown::check_pkgdown()`.

## Phase 6: Hand off and close (#497, #402)

- [ ] Edit the bodies of #497 and #402 to what was decided and shipped (edited, not appended). The PR closes #497, and #402 as Open decision 6 settles.
- [ ] Draft the knowledge#148 note in the PR body: which records now count as rainbow trout and as steelhead, the rule's rows, and the Phase 1 log. It is posted after the merge (below).

## Owed at the end (reported, done after merge)

- [ ] Post the knowledge#148 note once the rule is on `main`.
- [ ] Run the pre-run gate again before the next provincial run (`inst/extdata/` and `R/` changed).
- [ ] Every `default` group re-models at the next provincial run (move 17, #502) to `acc-v7`. Rebuild `streams_parent` after (`streams_parent_build.R --verify`, RUNBOOK §8d), and update #490's steps to name the new tokens.

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean, once over the branch with `/code-check branch` *(review: commits in Phases 2 and 3 leave the token pins red until Phase 4, so the per-commit gate cannot assume green)*
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

How each change is proved:
- **The record rule:** unit tests on the species map, the lift and the digest, and Phase 1's independent SQL count for three groups.
- **The presence decisions:** the check re-run drops every decided row, and the overlay loads (`lnk_load_overrides()` on `default`).
- **The unpause:**
  - `lnk_config("default")$species` includes RB;
  - the token resolver accepts every bundle extending `default`;
  - Phase 5's three-state builds show RB access and habitat back, with every other difference explained.
