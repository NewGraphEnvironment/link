# #402 — check each group's species presence against its fish records

## Outcome

`default`'s hand-authored `wsg_species_presence.csv` is now judged cell by cell against bcfishobs by `.lnk_presence_check()` (`R/lnk_presence_check.R`), run by `data-raw/wsg_species_presence_check.R`, and every disagreement sits in a review tracker in the bundle (`configs/default/wsg_species_presence_review.csv`) with a story drafted from its evidence and decision `pending`. The rule is the operator's: one record since 1950, releases (bcfishpass's tag) and `observation_exclusions.csv` out, CT aliases folded, `species_pooling.csv` applied. The first answer was five records; it was revised before any code, on the operator's point that a single fish caught above where a species was recorded before is real evidence. The tracker is deliberately left out of the bundle's `files:` so review edits do not move `config_hash`. The exclusion-key rule became one helper (`.lnk_observation_exclusion_keys()`) for prep, the validator and the check. The durable findings are in [`research/species_presence.md`](../../../research/species_presence.md).

What was learned, and the wrong turns kept: the plan rested on a premise that was false. It said `lnk_presence()`'s promotion makes a species' access and mapping code get built. Code-check round 3 found that it reaches only the break positions of a modelled species; access, classification and mapping code follow the cell as written. The 114 promoted stories, the research file, the RUNBOOK and CLAUDE.md had all repeated it. Four code-check rounds were needed: each of rounds 2 and 3 found a defect inside the previous round's fix, all of one mechanism — a sentence stating a pipeline consequence derived from a nearby value (the cell's species for the records' species; "promoted" for "modelled"; one bundle's thresholds for bcfishpass's). Round 4 ended it by enumeration (13 story sentence forms, each true on every row its condition admits, over all 351 rows). Plan review and the four rounds' findings: `review-plan.md`, `review-round1.md` to `review-round4.md`.

## Measurement

On local fwapg (bcfishobs 375,962 records, newest valid date 2026-10-10), 351 of 3,198 cells are flagged: 24 marked present with no counting record (12 with no record at all, 8 releases only, 4 undated only) and 327 not marked with records (82 with one record, 89 with two to four, 156 with five or more; 238 with a record since 1990). Kokanee are 137 of the 327 and 92 of the 156 large cells. 114 absent cells are promoted by their group and still unmodelled. An SQL recount of PARS, ADMS and ALBN (39 cells, 5,423 records) agrees exactly. Reruns reproduce every count and flag; the stories changed only by the review fixes.

Found on the way and left outside #402, filed after the PR opened:
- The pipeline's exact-code filter drops summer and winter steelhead (`SST` 404, `WST` 358), `ADV` 79, `ABT` 12, `BT/DV` 57, `DV/BT` 52 and `RB/CT` 23 records; counted, they would change 4 flags. The steelhead and char counterpart of #398: #425.
- link lifts on `observation_date >= '1990-01-01'`, bcfishpass on `> '1990-01-01'` (`smnorris/bcfishpass@620dbe4`): 561 lift-readable salmon and steelhead records sit on that date, which bears on the `bcfishpass` bundle's parity: #426.
- The operator noted that lifting a natural barrier needs 5 records since 1990 for salmon, steelhead, GR and KO in `default`, so one salmon above a falls gives code 2 and no lift: #427.
- RUNBOOK §5 says RB lifts have "no date floor"; `lnk_barrier_overrides()` substitutes 1900-01-01. Folded into #426.

## Evidence

`data-raw/logs/presence_check_402/` (its README indexes it).

## Owed

- **Operator review:** a decision on each tracker row. Each changed presence cell carries a `notes` entry naming the rule (#402, acceptance 2). The issue stays open until then.
- **Changing presence cells is its own PR:** the presence table is in the `acc` token spec (RUNBOOK §6b), so an edit needs a new `acc` vocabulary row and a version bump, plus the config provenance checksum. The affected groups re-model at the next provincial run (#377's runs row).
- The pre-run gate (#372) must run again: `R/lnk_pipeline_prepare.R` changes (behaviour-preserving, identical SQL) and `data-raw/pretest_inputs.csv` (the gate's own map) gains two `none` rows. It is already owed for #401.

Closed by: the PR from branch `402-check-each-group-s-species-presence-agai` (relates to #402; the issue stays open for the operator's review).
